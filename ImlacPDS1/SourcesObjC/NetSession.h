// NetSession.h — UDP LAN multiplayer for Imlac PDS-1 iOS
#import <Foundation/Foundation.h>

@protocol NetSessionEventListener <NSObject>
- (void)onConnectedAsHost:(BOOL)asHost seed:(NSInteger)seed;
- (void)onPeerMazeStateX:(NSInteger)x y:(NSInteger)y dir:(NSInteger)dir hp:(NSInteger)hp score:(NSInteger)score;
- (void)onPeerSyncDemoIdx:(NSInteger)demoIdx keyboard:(NSInteger)keyboard;
- (void)onPeerBulletDir:(NSInteger)dir;
- (void)onPeerKilled;
- (void)onDisconnected;
@end

@protocol NetSessionChatListener <NSObject>
- (void)onChatMessageFrom:(NSString *)from msg:(NSString *)msg;
@end

@interface NetSession : NSObject

+ (NSInteger)PORT_GAME;
+ (NSInteger)PORT_BCAST;

@property (nonatomic, readonly) NSString *peerAddr;

@property (nonatomic) NSInteger peerMazeX;
@property (nonatomic) NSInteger peerMazeY;
@property (nonatomic) NSInteger peerMazeDir;
@property (nonatomic) NSInteger peerMazeHp;
@property (nonatomic) NSInteger peerMazeScore;
@property (nonatomic) NSInteger mazeSeed;
@property (nonatomic) NSInteger myId;

@property (nonatomic, weak, nullable) id<NetSessionEventListener> eventListener;
@property (nonatomic, weak, nullable) id<NetSessionChatListener> chatListener;

- (void)host:(NSInteger)seed;
- (void)discover;
- (void)stop;

- (void)sendSync:(NSInteger)demoIdx keyboard:(NSInteger)keyboard;
- (void)sendMazeStateX:(NSInteger)x y:(NSInteger)y dir:(NSInteger)dir hp:(NSInteger)hp score:(NSInteger)score;
- (void)sendBullet:(NSInteger)dir;
- (void)sendKill;
- (void)sendChat:(NSString *)text;

- (BOOL)isConnected;

@end
