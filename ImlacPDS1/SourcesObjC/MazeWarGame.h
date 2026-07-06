// MazeWarGame.h — Maze War (1974) for Imlac PDS-1 iOS
#import <Foundation/Foundation.h>
#import "Machine.h"

@class NetSession;

@interface MazeWarGame : NSObject

@property (nonatomic, strong, nullable) NetSession *net;

// Input flags — set true by the UI layer before calling tick.
@property (nonatomic) BOOL iUp;
@property (nonatomic) BOOL iDown;
@property (nonatomic) BOOL iLeft;
@property (nonatomic) BOOL iRight;
@property (nonatomic) BOOL iFire;

- (instancetype)initWithMachine:(Machine *)machine;

- (void)tick;
- (void)draw;

- (void)startSinglePlayer;
- (void)hostMulti:(NetSession *)n;
- (void)joinMulti:(NetSession *)n;
- (void)stopNet;

// NetSession event callbacks (equivalent to NetSessionEventListener conformance)
- (void)onConnectedAsHost:(BOOL)asHost seed:(NSInteger)seed;
- (void)onPeerMazeStateX:(NSInteger)x y:(NSInteger)y dir:(NSInteger)dir hp:(NSInteger)hp2 score:(NSInteger)sc;
- (void)onPeerSyncDemoIdx:(NSInteger)demoIdx keyboard:(NSInteger)keyboard;
- (void)onPeerBulletDir:(NSInteger)dir;
- (void)onPeerKilled;
- (void)onDisconnected;

@end
