// NetSession.m — UDP LAN multiplayer for Imlac PDS-1 iOS
// Ported from NetSession.swift (originally NetSession.java)
#import "NetSession.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>

#define NET_PKT 32
#define NET_PEER_TIMEOUT 6.0

typedef NS_ENUM(NSInteger, NetRole)   { NetRoleNone, NetRoleHost, NetRoleGuest };
typedef NS_ENUM(NSInteger, NetStatus) { NetStatusIdle, NetStatusHosting, NetStatusSearching, NetStatusConnected, NetStatusDisconnected };

@interface NetSession () {
    NetRole _role;
    NetStatus _status;
    NSString *_peerAddrStr;

    int _gameSocket;
    int _bcastSocket;
    BOOL _running;
    dispatch_queue_t _netQueue;
    NSMutableArray<NSData *> *_sendQueue;
    NSLock *_sendLock;
    NSDate *_lastPeerTime;
}
@end

@implementation NetSession

+ (NSInteger)PORT_GAME  { return 7474; }
+ (NSInteger)PORT_BCAST { return 7475; }

- (instancetype)init {
    self = [super init];
    if (self) {
        _role = NetRoleNone;
        _status = NetStatusIdle;
        _gameSocket = -1;
        _bcastSocket = -1;
        _running = NO;
        _netQueue = dispatch_queue_create("net.session", DISPATCH_QUEUE_SERIAL);
        dispatch_set_target_queue(_netQueue, dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0));
        _sendQueue = [NSMutableArray array];
        _sendLock = [[NSLock alloc] init];
        _peerMazeX = 1; _peerMazeY = 1; _peerMazeDir = 0; _peerMazeHp = 3; _peerMazeScore = 0;
    }
    return self;
}

- (NSString *)peerAddr { return _peerAddrStr; }

#pragma mark - Host

- (void)host:(NSInteger)seed {
    [self stop];
    _mazeSeed = seed; _role = NetRoleHost; _myId = 0; _status = NetStatusHosting; _running = YES;
    __weak NetSession *weakSelf = self;
    dispatch_async(_netQueue, ^{ [weakSelf hostLoop]; });
}

- (void)hostLoop {
    _gameSocket  = [self makeUDPSocketPort:(int)[NetSession PORT_GAME]  broadcast:NO];
    _bcastSocket = [self makeUDPSocketPort:(int)[NetSession PORT_BCAST] broadcast:YES];
    if (!(_gameSocket >= 0 && _bcastSocket >= 0)) { [self fail]; return; }

    struct timeval timeout = { .tv_sec = 0, .tv_usec = 300000 };
    setsockopt(_bcastSocket, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(_gameSocket,  SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));

    uint8_t buf[NET_PKT];
    while (_running && _status == NetStatusHosting) {
        struct sockaddr_storage srcAddr;
        socklen_t srcLen = sizeof(srcAddr);
        memset(&srcAddr, 0, sizeof(srcAddr));
        ssize_t n = recvfrom(_bcastSocket, buf, NET_PKT, 0, (struct sockaddr *)&srcAddr, &srcLen);
        if (n == NET_PKT && buf[0] == 'D') {
            _peerAddrStr = [self addrToString:&srcAddr];
            NSData *welcome = [self makePacketType:'W' idv:0 demo:0 kbd:0 seed:(int)_mazeSeed];
            [self sendTo:_gameSocket data:welcome addr:&srcAddr addrLen:srcLen];
        }
        ssize_t n2 = recvfrom(_gameSocket, buf, NET_PKT, 0, (struct sockaddr *)&srcAddr, &srcLen);
        if (n2 == NET_PKT && buf[0] == 'J') {
            _peerAddrStr = [self addrToString:&srcAddr];
            _status = NetStatusConnected;
            _lastPeerTime = [NSDate date];
            NSInteger seedCopy = _mazeSeed;
            __weak NetSession *weakSelf = self;
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf.eventListener onConnectedAsHost:YES seed:seedCopy];
            });
        }
    }
    if (_status == NetStatusConnected) { [self gameLoop]; }
    else { [self fail]; }
}

#pragma mark - Guest

- (void)discover {
    [self stop];
    _role = NetRoleGuest; _myId = 1; _status = NetStatusSearching; _running = YES;
    __weak NetSession *weakSelf = self;
    dispatch_async(_netQueue, ^{ [weakSelf guestLoop]; });
}

- (void)guestLoop {
    _gameSocket = [self makeUDPSocketPort:(int)[NetSession PORT_GAME] broadcast:YES];
    if (!(_gameSocket >= 0)) { [self fail]; return; }

    struct timeval timeout = { .tv_sec = 0, .tv_usec = 300000 };
    setsockopt(_gameSocket, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));

    NSData *bcastData = [self makePacketType:'D' idv:1 demo:0 kbd:0 seed:0];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:30];
    uint8_t buf[NET_PKT];

    while (_running && _status == NetStatusSearching && [[NSDate date] compare:deadline] == NSOrderedAscending) {
        [self broadcastSend:_gameSocket data:bcastData port:(int)[NetSession PORT_BCAST]];

        struct sockaddr_storage srcAddr;
        socklen_t srcLen = sizeof(srcAddr);
        memset(&srcAddr, 0, sizeof(srcAddr));
        ssize_t n = recvfrom(_gameSocket, buf, NET_PKT, 0, (struct sockaddr *)&srcAddr, &srcLen);
        if (n == NET_PKT && buf[0] == 'W') {
            _peerAddrStr = [self addrToString:&srcAddr];
            _mazeSeed = [self decodeSeed:buf offset:12];
            NSData *join = [self makePacketType:'J' idv:1 demo:0 kbd:0 seed:0];
            [self sendTo:_gameSocket data:join addr:&srcAddr addrLen:srcLen];
            _status = NetStatusConnected;
            _lastPeerTime = [NSDate date];
            NSInteger seedCopy = _mazeSeed;
            __weak NetSession *weakSelf = self;
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf.eventListener onConnectedAsHost:NO seed:seedCopy];
            });
        }
    }
    if (_status == NetStatusConnected) { [self gameLoop]; }
    else { [self fail]; }
}

#pragma mark - Game loop

- (void)gameLoop {
    struct timeval timeout = { .tv_sec = 0, .tv_usec = 200000 };
    setsockopt(_gameSocket, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    uint8_t buf[NET_PKT];

    while (_running) {
        [_sendLock lock];
        NSArray<NSData *> *pending = [_sendQueue copy];
        [_sendQueue removeAllObjects];
        [_sendLock unlock];
        for (NSData *pkt in pending) { [self sendToPeer:_gameSocket data:pkt]; }

        struct sockaddr_storage srcAddr;
        socklen_t srcLen = sizeof(srcAddr);
        memset(&srcAddr, 0, sizeof(srcAddr));
        ssize_t n = recvfrom(_gameSocket, buf, NET_PKT, 0, (struct sockaddr *)&srcAddr, &srcLen);
        if (n == NET_PKT) {
            _lastPeerTime = [NSDate date];
            [self handlePacket:buf];
        }

        if (_lastPeerTime && [[NSDate date] timeIntervalSinceDate:_lastPeerTime] > NET_PEER_TIMEOUT) {
            [self fail];
            return;
        }
    }
}

- (void)handlePacket:(uint8_t *)p {
    char type = (char)p[0];
    __weak NetSession *weakSelf = self;
    switch (type) {
        case 'S': {
            NSInteger demo = p[2], kbd = (p[3] << 8) | p[4];
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf.eventListener onPeerSyncDemoIdx:demo keyboard:kbd];
            });
            break;
        }
        case 'M': {
            NSInteger x = p[5], y = p[6], dir = p[7], hp = p[8], sc = (p[9] << 8) | p[10];
            _peerMazeX = x; _peerMazeY = y; _peerMazeDir = dir; _peerMazeHp = hp; _peerMazeScore = sc;
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf.eventListener onPeerMazeStateX:x y:y dir:dir hp:hp score:sc];
            });
            break;
        }
        case 'B': {
            NSInteger dir = p[11];
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf.eventListener onPeerBulletDir:dir];
            });
            break;
        }
        case 'K': {
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf.eventListener onPeerKilled];
            });
            break;
        }
        case 'C': {
            NSString *msg = [self decodeChat:p offset:16];
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf.chatListener onChatMessageFrom:@"OPP" msg:msg];
            });
            break;
        }
        case 'X':
            [self fail];
            break;
        default: break;
    }
}

#pragma mark - Send (thread-safe)

- (void)sendSync:(NSInteger)demoIdx keyboard:(NSInteger)keyboard {
    if (![self isConnected]) return;
    uint8_t p[NET_PKT]; memset(p, 0, sizeof(p));
    p[0] = 'S'; p[1] = (uint8_t)_myId; p[2] = (uint8_t)demoIdx;
    p[3] = (uint8_t)((keyboard >> 8) & 0xFF); p[4] = (uint8_t)(keyboard & 0xFF);
    [self enqueue:[NSData dataWithBytes:p length:NET_PKT]];
}

- (void)sendMazeStateX:(NSInteger)x y:(NSInteger)y dir:(NSInteger)dir hp:(NSInteger)hp score:(NSInteger)score {
    if (![self isConnected]) return;
    uint8_t p[NET_PKT]; memset(p, 0, sizeof(p));
    p[0] = 'M'; p[1] = (uint8_t)_myId;
    p[5] = (uint8_t)x; p[6] = (uint8_t)y; p[7] = (uint8_t)dir; p[8] = (uint8_t)hp;
    p[9] = (uint8_t)((score >> 8) & 0xFF); p[10] = (uint8_t)(score & 0xFF);
    [self enqueue:[NSData dataWithBytes:p length:NET_PKT]];
}

- (void)sendBullet:(NSInteger)dir {
    if (![self isConnected]) return;
    uint8_t p[NET_PKT]; memset(p, 0, sizeof(p));
    p[0] = 'B'; p[1] = (uint8_t)_myId; p[11] = (uint8_t)dir;
    [self enqueue:[NSData dataWithBytes:p length:NET_PKT]];
}

- (void)sendKill {
    if (![self isConnected]) return;
    uint8_t p[NET_PKT]; memset(p, 0, sizeof(p));
    p[0] = 'K'; p[1] = (uint8_t)_myId;
    [self enqueue:[NSData dataWithBytes:p length:NET_PKT]];
}

- (void)sendChat:(NSString *)text {
    if (![self isConnected]) return;
    uint8_t p[NET_PKT]; memset(p, 0, sizeof(p));
    p[0] = 'C'; p[1] = (uint8_t)_myId;
    const char *utf8 = [text UTF8String];
    NSInteger len = MIN((NSInteger)strlen(utf8), 15);
    for (NSInteger i = 0; i < len; i++) { p[16 + i] = (uint8_t)utf8[i]; }
    [self enqueue:[NSData dataWithBytes:p length:NET_PKT]];
    __weak NetSession *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf.chatListener onChatMessageFrom:@"ME" msg:text];
    });
}

- (void)enqueue:(NSData *)d {
    [_sendLock lock];
    [_sendQueue addObject:d];
    [_sendLock unlock];
}

#pragma mark - Socket utils

- (int)makeUDPSocketPort:(int)port broadcast:(BOOL)broadcast {
    int fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (fd < 0) return -1;
    int on = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &on, sizeof(on));
    if (broadcast) { setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &on, sizeof(on)); }
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons((uint16_t)port);
    addr.sin_addr.s_addr = INADDR_ANY;
    bind(fd, (struct sockaddr *)&addr, sizeof(addr));
    return fd;
}

- (void)sendTo:(int)fd data:(NSData *)data addr:(struct sockaddr_storage *)addr addrLen:(socklen_t)addrLen {
    sendto(fd, data.bytes, data.length, 0, (struct sockaddr *)addr, addrLen);
}

- (void)sendToPeer:(int)fd data:(NSData *)data {
    if (!_peerAddrStr) return;
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons((uint16_t)[NetSession PORT_GAME]);
    addr.sin_addr.s_addr = inet_addr([_peerAddrStr UTF8String]);
    sendto(fd, data.bytes, data.length, 0, (struct sockaddr *)&addr, sizeof(addr));
}

- (void)broadcastSend:(int)fd data:(NSData *)data port:(int)port {
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons((uint16_t)port);
    addr.sin_addr.s_addr = INADDR_BROADCAST;
    sendto(fd, data.bytes, data.length, 0, (struct sockaddr *)&addr, sizeof(addr));
}

- (NSString *)addrToString:(struct sockaddr_storage *)addr {
    char buf[INET_ADDRSTRLEN];
    struct sockaddr_in *sin = (struct sockaddr_in *)addr;
    inet_ntop(AF_INET, &(sin->sin_addr), buf, INET_ADDRSTRLEN);
    return [NSString stringWithUTF8String:buf];
}

- (NSData *)makePacketType:(char)type idv:(int)idv demo:(int)demo kbd:(int)kbd seed:(int)seed {
    uint8_t p[NET_PKT]; memset(p, 0, sizeof(p));
    p[0] = (uint8_t)type; p[1] = (uint8_t)idv; p[2] = (uint8_t)demo;
    p[3] = (uint8_t)((kbd >> 8) & 0xFF); p[4] = (uint8_t)(kbd & 0xFF);
    p[12] = (uint8_t)((seed >> 24) & 0xFF); p[13] = (uint8_t)((seed >> 16) & 0xFF);
    p[14] = (uint8_t)((seed >> 8) & 0xFF);  p[15] = (uint8_t)(seed & 0xFF);
    return [NSData dataWithBytes:p length:NET_PKT];
}

- (NSInteger)decodeSeed:(uint8_t *)p offset:(int)offset {
    return ((NSInteger)p[offset] << 24) | ((NSInteger)p[offset+1] << 16) | ((NSInteger)p[offset+2] << 8) | (NSInteger)p[offset+3];
}

- (NSString *)decodeChat:(uint8_t *)p offset:(int)offset {
    char buf[16];
    int i = 0;
    for (; i < 15; i++) {
        uint8_t b = p[offset + i];
        if (b == 0) break;
        buf[i] = (char)b;
    }
    buf[i] = 0;
    NSString *s = [NSString stringWithUTF8String:buf];
    return s ?: @"";
}

- (void)fail {
    _status = NetStatusDisconnected;
    __weak NetSession *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf.eventListener onDisconnected];
    });
    [self closeAll];
}

- (void)stop {
    _running = NO;
    [self closeAll];
    _status = NetStatusIdle;
    _role = NetRoleNone;
}

- (void)closeAll {
    if (_gameSocket >= 0) { close(_gameSocket); _gameSocket = -1; }
    if (_bcastSocket >= 0) { close(_bcastSocket); _bcastSocket = -1; }
}

- (BOOL)isConnected { return _status == NetStatusConnected; }

@end
