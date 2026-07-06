// MazeWarGame.m — Maze War (1974) for Imlac PDS-1 iOS
// Ported from MazeWarGame.swift (originally MazeWarGame.java)
#import "MazeWarGame.h"
#import "NetSession.h"

#define VX0 40
#define VX1 780
#define VY0 80
#define VY1 940
#define VCX ((VX0+VX1)/2)
#define VCY ((VY0+VY1)/2)
#define VW  (VX1-VX0)
#define VH  (VY1-VY0)
#define MZ 16

typedef NS_ENUM(NSInteger, GameState) { GameStateTitle, GameStateLobby, GameStatePlay, GameStateDead };

@interface Enemy : NSObject
@property (nonatomic) NSInteger x, y, dir;
@property (nonatomic) NSInteger think, fireCd;
@property (nonatomic) BOOL alive;
@end
@implementation Enemy
- (instancetype)initWithX:(NSInteger)x y:(NSInteger)y dir:(NSInteger)dir {
    self = [super init];
    if (self) { _x = x; _y = y; _dir = dir; _think = 30; _fireCd = 80; _alive = YES; }
    return self;
}
@end

@interface Bullet : NSObject
@property (nonatomic) double x, y;
@property (nonatomic) NSInteger dir, life;
@property (nonatomic) BOOL fromPlayer, alive;
@end
@implementation Bullet
- (instancetype)initWithX:(double)x y:(double)y dir:(NSInteger)dir fromPlayer:(BOOL)fp {
    self = [super init];
    if (self) { _x = x; _y = y; _dir = dir; _life = 55; _fromPlayer = fp; _alive = YES; }
    return self;
}
@end

@interface MazeWarGame () <NetSessionEventListener> {
    NSInteger _maze[MZ * MZ];
    NSInteger _DX[4], _DY[4], _OPP[4];

    NSInteger _px, _py, _pdir, _hp, _score, _level;
    NSInteger _moveCd, _turnCd, _fireCd, _hitFlash, _killFlash;

    NSInteger _netX, _netY, _netDir, _netHp, _netScore;
    BOOL _netAlive; NSInteger _netHitFlash;

    BOOL _multiMode; NSInteger _netSendCd;

    NSMutableArray<Enemy *> *_aiEnemies;
    NSMutableArray<Bullet *> *_bullets;

    GameState _state;
    NSInteger _frame;
    NSString *_msg; NSInteger _msgT; NSString *_lobbyStatus;

    BOOL _pUp, _pDown, _pLeft, _pRight, _pFire;

    Machine *_M;
}
@end

@implementation MazeWarGame

- (instancetype)initWithMachine:(Machine *)machine {
    self = [super init];
    if (self) {
        _M = machine;
        _DX[0]=0; _DX[1]=1; _DX[2]=0; _DX[3]=-1;
        _DY[0]=1; _DY[1]=0; _DY[2]=-1; _DY[3]=0;
        _OPP[0]=2; _OPP[1]=3; _OPP[2]=0; _OPP[3]=1;
        for (int i = 0; i < MZ*MZ; i++) { _maze[i] = 0xF; }
        _px=1; _py=1; _pdir=0; _hp=3; _score=0; _level=1;
        _netX=14; _netY=14; _netDir=2; _netHp=3; _netScore=0;
        _netAlive=YES;
        _aiEnemies = [NSMutableArray array];
        _bullets = [NSMutableArray array];
        _state = GameStateTitle;
        _msg = @""; _lobbyStatus = @"";
    }
    return self;
}

#pragma mark - Public API

- (void)tick {
    NSInteger k = _M.keyboard & 0x7F;
    _iUp    = _iUp    || (k == 'W');
    _iDown  = _iDown  || (k == 'S');
    _iLeft  = _iLeft  || (k == 'A');
    _iRight = _iRight || (k == 'D');
    _iFire  = _iFire  || (k == 32 || k == 'F');

    switch (_state) {
        case GameStateTitle: [self tickTitle]; break;
        case GameStateLobby: break;
        case GameStatePlay:  [self tickPlay]; break;
        case GameStateDead:  [self tickDead]; break;
    }
    _pUp=_iUp; _pDown=_iDown; _pLeft=_iLeft; _pRight=_iRight; _pFire=_iFire;
    _iUp=NO; _iDown=NO; _iLeft=NO; _iRight=NO; _iFire=NO;
    _frame += 1;
}

- (void)draw {
    switch (_state) {
        case GameStateTitle: [self drawTitle]; break;
        case GameStateLobby: [self drawLobby]; break;
        case GameStatePlay:  [self drawPlay]; break;
        case GameStateDead:  [self drawDead]; break;
    }
}

- (void)startSinglePlayer {
    _multiMode = NO;
    [self startGameWithSeed:(uint64_t)arc4random() << 32 | arc4random()];
}

- (void)hostMulti:(NetSession *)n {
    self.net = n; _multiMode = YES; n.eventListener = self;
    _state = GameStateLobby; _lobbyStatus = @"HOSTING... WAIT FOR GUEST";
}
- (void)joinMulti:(NetSession *)n {
    self.net = n; _multiMode = YES; n.eventListener = self;
    _state = GameStateLobby; _lobbyStatus = @"SEARCHING FOR HOST...";
}
- (void)stopNet {
    [self.net stop]; self.net = nil; _multiMode = NO; _state = GameStateTitle;
}

#pragma mark - Title / Lobby / Dead

- (void)tickTitle {
    BOOL anyNew = (_iUp||_iDown||_iLeft||_iRight||_iFire) && !(_pUp||_pDown||_pLeft||_pRight||_pFire);
    if (anyNew) { [self startGameWithSeed:(uint64_t)arc4random() << 32 | arc4random()]; }
}

- (void)drawTitle {
    NSInteger ex = VCX+100, ey = VCY, rx = 90, ry = 55;
    [self circle:ex cy:ey rx:rx ry:ry segs:20 b:0.9f];
    [self circle:ex cy:ey rx:rx/3 ry:(NSInteger)(ry*0.8f) segs:12 b:1.0f];
    for (NSInteger i = -3; i <= 3; i++) {
        if (i == 0) continue;
        [self vl:ex+i*28 y1:ey+ry+2 x2:ex+i*28+i*5 y2:ey+ry+28 b:0.55f];
    }
    [self txt:@"MAZE WAR" ox:VX0+10 oy:VCY+60 sc:18 b:1.0f];
    [self txt:@"IMLAC PDS-1  1974" ox:VX0+10 oy:VCY+10 sc:10 b:0.5f];
    [self txt:@"SINGLE  -  ANY BUTTON" ox:VX0+10 oy:VCY-40 sc:8 b:0.4f];
    [self txt:@"MULTI   -  HOST OR JOIN" ox:VX0+10 oy:VCY-70 sc:8 b:0.35f];
    if ((_frame/20)%2==0) { [self txt:@"PRESS ANY BUTTON" ox:VX0+10 oy:VCY-110 sc:9 b:0.8f]; }
}

- (void)drawLobby {
    NSArray<NSString *> *spin = @[@"|",@"/",@"-",@"\\"];
    [self txt:@"MAZE WAR  ONLINE" ox:VCX-200 oy:VCY+80 sc:13 b:0.9f];
    [self txt:_lobbyStatus ox:VCX-(NSInteger)_lobbyStatus.length*11 oy:VCY+10 sc:11 b:0.7f];
    [self txt:spin[(_frame/8)%4] ox:VCX-10 oy:VCY-50 sc:16 b:0.6f];
    [self txt:@"CANCEL  -  DISC BUTTON" ox:VCX-200 oy:VCY-110 sc:8 b:0.25f];
}

- (void)drawDead {
    [self txt:@"GAME OVER" ox:VCX-190 oy:VCY+80 sc:18 b:0.9f];
    [self txt:[NSString stringWithFormat:@"SCORE %ld", (long)_score] ox:VCX-160 oy:VCY+10 sc:13 b:0.7f];
    if ((_frame/20)%2==0) { [self txt:@"PRESS ANY BUTTON" ox:VCX-215 oy:VCY-70 sc:11 b:0.85f]; }
}

- (void)tickDead {
    BOOL anyNew = (_iUp||_iDown||_iLeft||_iRight||_iFire) && !(_pUp||_pDown||_pLeft||_pRight||_pFire);
    if (anyNew) { _multiMode = NO; _state = GameStateTitle; }
}

#pragma mark - Maze generation

- (void)startGameWithSeed:(uint64_t)seed {
    [self genMazeWithSeed:(NSInteger)(seed & 0x7FFFFFFF)];
    _px=1; _py=1; _pdir=0; _hp=3; _score=0; _level=1;
    _moveCd=0; _turnCd=0; _fireCd=0; _hitFlash=0; _killFlash=0;
    [_bullets removeAllObjects]; [_aiEnemies removeAllObjects];
    if (!_multiMode) { [self spawnAI:_level+1]; }
    _state = GameStatePlay;
}

- (void)genMazeWithSeed:(NSInteger)seed {
    for (int i = 0; i < MZ*MZ; i++) { _maze[i] = 0xF; }
    NSInteger rng = seed;
    BOOL vis[MZ*MZ];
    memset(vis, 0, sizeof(vis));
    [self carveX:1 y:1 vis:vis rng:&rng];
}

- (NSInteger)nextRnd:(NSInteger *)rng {
    *rng = (*rng) * 1664525 + 1013904223;
    return (*rng >> 16) & 0x7FFF;
}

- (void)carveX:(NSInteger)x y:(NSInteger)y vis:(BOOL *)vis rng:(NSInteger *)rng {
    vis[y*MZ+x] = YES;
    NSInteger d[4] = {0,1,2,3};
    for (NSInteger i = 3; i >= 1; i--) {
        NSInteger j = [self nextRnd:rng] % (i+1);
        NSInteger tmp = d[i]; d[i] = d[j]; d[j] = tmp;
    }
    for (int k = 0; k < 4; k++) {
        NSInteger dd = d[k];
        NSInteger nx = x + _DX[dd], ny = y + _DY[dd];
        if (nx<1||nx>=MZ-1||ny<1||ny>=MZ-1||vis[ny*MZ+nx]) continue;
        _maze[y*MZ+x]   &= ~(1<<dd);
        _maze[ny*MZ+nx] &= ~(1<<_OPP[dd]);
        [self carveX:nx y:ny vis:vis rng:rng];
    }
}

- (BOOL)wall:(NSInteger)x y:(NSInteger)y dir:(NSInteger)dir {
    if (x<0||x>=MZ||y<0||y>=MZ) return YES;
    return (_maze[y*MZ+x] & (1<<dir)) != 0;
}

- (BOOL)solid:(NSInteger)x y:(NSInteger)y {
    if (x<0||x>=MZ||y<0||y>=MZ) return YES;
    return _maze[y*MZ+x] == 0xF;
}

- (void)spawnAI:(NSInteger)n {
    for (NSInteger i = 0; i < n; i++) {
        NSInteger ex = 0, ey = 0;
        for (NSInteger tries = 0; tries < 200; tries++) {
            ex = 2 + (NSInteger)(arc4random_uniform((uint32_t)(MZ-4)));
            ey = 2 + (NSInteger)(arc4random_uniform((uint32_t)(MZ-4)));
            if (![self solid:ex y:ey] && (labs(ex-_px)+labs(ey-_py) > 3)) break;
        }
        [_aiEnemies addObject:[[Enemy alloc] initWithX:ex y:ey dir:(NSInteger)arc4random_uniform(4)]];
    }
}

#pragma mark - Play tick

- (void)tickPlay {
    if (_moveCd>0) _moveCd--; if (_turnCd>0) _turnCd--;
    if (_fireCd>0) _fireCd--; if (_hitFlash>0) _hitFlash--;
    if (_killFlash>0) _killFlash--; if (_msgT>0) _msgT--; if (_netHitFlash>0) _netHitFlash--;

    if (_turnCd==0) {
        if (_iLeft && !_pLeft)  { _pdir=(_pdir+3)%4; _turnCd=8; }
        if (_iRight && !_pRight) { _pdir=(_pdir+1)%4; _turnCd=8; }
    }
    if (_moveCd==0) {
        if (_iUp && ![self wall:_px y:_py dir:_pdir]) { _px+=_DX[_pdir]; _py+=_DY[_pdir]; _moveCd=12; }
        else if (_iDown && ![self wall:_px y:_py dir:(_pdir+2)%4]) { _px-=_DX[_pdir]; _py-=_DY[_pdir]; _moveCd=12; }
    }
    if (_iFire && !_pFire && _fireCd==0) {
        [_bullets addObject:[[Bullet alloc] initWithX:(double)_px+0.5 y:(double)_py+0.5 dir:_pdir fromPlayer:YES]];
        _fireCd=20;
        [self.net sendBullet:_pdir];
    }
    [self tickBullets];
    if (!_multiMode) { [self tickAI]; [self checkWin]; }
    else { if (!_netAlive && _netHitFlash<=0) { _netAlive=YES; } }
    if (_multiMode && self.net && [self.net isConnected]) {
        if (_netSendCd<=0) { [self.net sendMazeStateX:_px y:_py dir:_pdir hp:_hp score:_score]; _netSendCd=3; }
        else { _netSendCd--; }
    }
}

- (void)tickBullets {
    for (Bullet *b in _bullets) {
        if (!b.alive) continue;
        b.life--; if (b.life<=0) { b.alive=NO; continue; }
        b.x += (double)_DX[b.dir]*0.2; b.y += (double)_DY[b.dir]*0.2;
        if ([self solid:(NSInteger)b.x y:(NSInteger)b.y]) { b.alive=NO; continue; }
        if (b.fromPlayer) {
            for (Enemy *e in _aiEnemies) {
                if (!e.alive) continue;
                if (fabs(b.x-((double)e.x+0.5))<0.6 && fabs(b.y-((double)e.y+0.5))<0.6) {
                    e.alive=NO; b.alive=NO; _score+=1; _killFlash=12; _msg=@"KILL"; _msgT=30;
                    break;
                }
            }
            if (_multiMode && _netAlive && fabs(b.x-((double)_netX+0.5))<0.6 && fabs(b.y-((double)_netY+0.5))<0.6) {
                b.alive=NO; _netAlive=NO; _netHitFlash=20; _score+=1;
                [self.net sendKill];
                _msg=@"YOU KILLED OPPONENT!"; _msgT=50;
            }
        } else {
            if (fabs(b.x-((double)_px+0.5))<0.55 && fabs(b.y-((double)_py+0.5))<0.55) {
                b.alive=NO; _hp-=1; _hitFlash=18;
                _msg = _hp>0 ? [NSString stringWithFormat:@"HIT! HP:%ld", (long)_hp] : @"YOU DIED";
                _msgT=45;
                if (_hp<=0) { _state = GameStateDead; }
            }
        }
    }
    [_bullets filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(Bullet *b, NSDictionary *bindings) {
        return b.alive;
    }]];
}

- (void)tickAI {
    for (Enemy *e in _aiEnemies) {
        if (!e.alive) continue;
        e.think--; e.fireCd--;
        if (e.think<=0) {
            e.think = 15 + (NSInteger)arc4random_uniform(25);
            NSInteger dx = _px-e.x, dy = _py-e.y;
            NSInteger want = -1;
            if (labs(dx)>labs(dy)) { want = dx>0 ? 1:3; }
            else if (dy != 0) { want = dy>0 ? 0:2; }
            double r = (double)arc4random() / (double)UINT32_MAX;
            if (r<0.6 && want>=0 && ![self wall:e.x y:e.y dir:want]) {
                e.dir=want; e.x+=_DX[want]; e.y+=_DY[want];
            } else {
                NSInteger ds[4] = {0,1,2,3};
                for (NSInteger i = 3; i >= 1; i--) {
                    NSInteger j = arc4random_uniform((uint32_t)(i+1));
                    NSInteger tmp = ds[i]; ds[i] = ds[j]; ds[j] = tmp;
                }
                for (int k = 0; k < 4; k++) {
                    NSInteger dd = ds[k];
                    if (![self wall:e.x y:e.y dir:dd]) { e.dir=dd; e.x+=_DX[dd]; e.y+=_DY[dd]; break; }
                }
            }
        }
        if (e.fireCd<=0) {
            BOOL sh = NO;
            if (e.dir==0 && e.x==_px && _py>e.y) { sh = [self los:e.x y1:e.y x2:_px y2:_py]; }
            if (e.dir==2 && e.x==_px && _py<e.y) { sh = [self los:_px y1:_py x2:e.x y2:e.y]; }
            if (e.dir==1 && e.y==_py && _px>e.x) { sh = [self los:e.x y1:e.y x2:_px y2:_py]; }
            if (e.dir==3 && e.y==_py && _px<e.x) { sh = [self los:_px y1:_py x2:e.x y2:e.y]; }
            if (sh) {
                [_bullets addObject:[[Bullet alloc] initWithX:(double)e.x+0.5 y:(double)e.y+0.5 dir:e.dir fromPlayer:NO]];
                e.fireCd = 60 + (NSInteger)arc4random_uniform(60);
            }
        }
    }
}

- (BOOL)los:(NSInteger)x1 y1:(NSInteger)y1 x2:(NSInteger)x2 y2:(NSInteger)y2 {
    if (x1==x2) { for (NSInteger y = y1; y < y2; y++) { if ([self wall:x1 y:y dir:0]) return NO; } }
    else        { for (NSInteger x = x1; x < x2; x++) { if ([self wall:x y:y1 dir:1]) return NO; } }
    return YES;
}

- (void)checkWin {
    BOOL allDead = YES;
    for (Enemy *e in _aiEnemies) { if (e.alive) { allDead = NO; break; } }
    if (allDead) {
        _level += 1;
        _msg = [NSString stringWithFormat:@"LEVEL %ld!", (long)_level]; _msgT = 60;
        [self genMazeWithSeed:(NSInteger)arc4random()];
        _px=1; _py=1; _pdir=0;
        [_bullets removeAllObjects]; [_aiEnemies removeAllObjects];
        [self spawnAI:MIN(_level+1, 7)];
    }
}

#pragma mark - Draw

- (void)drawPlay {
    [self vl:VX0 y1:VY0 x2:VX1 y2:VY0 b:0.5f]; [self vl:VX1 y1:VY0 x2:VX1 y2:VY1 b:0.5f];
    [self vl:VX1 y1:VY1 x2:VX0 y2:VY1 b:0.5f]; [self vl:VX0 y1:VY1 x2:VX0 y2:VY0 b:0.5f];
    if (_hitFlash>0) {
        float f = (float)_hitFlash/18;
        [self vl:VX0 y1:VY0 x2:VX1 y2:VY0 b:f]; [self vl:VX1 y1:VY0 x2:VX1 y2:VY1 b:f];
        [self vl:VX1 y1:VY1 x2:VX0 y2:VY1 b:f]; [self vl:VX0 y1:VY1 x2:VX0 y2:VY0 b:f];
    }
    [self draw3D]; [self drawEnemiesInView]; [self drawHUD];
    if (_msgT>0) { [self txt:_msg ox:VCX-(NSInteger)_msg.length*11 oy:VCY-60 sc:13 b:MIN(1.0f, (float)_msgT/20)]; }
    if (_multiMode) {
        BOOL connected = self.net && [self.net isConnected];
        [self txt:(connected ? @"NET OK" : @"NET...") ox:VX0+8 oy:VY0-22 sc:7 b:0.4f];
    }
}

- (void)draw3D {
    NSInteger MAXD = 10; NSInteger depth = 0, wx = _px, wy = _py;
    for (NSInteger d = 1; d <= MAXD; d++) {
        if ([self wall:wx y:wy dir:_pdir]) { depth = d-1; break; }
        wx += _DX[_pdir]; wy += _DY[_pdir];
        if ([self solid:wx y:wy]) { depth = d-1; break; }
        depth = d;
    }
    depth = MAX((NSInteger)0, depth);
    NSInteger lt[MAXD+2], rt[MAXD+2], tp[MAXD+2], bt[MAXD+2];
    for (NSInteger d = 0; d <= depth+1; d++) {
        float sc = 1.4f / (float)(d+1);
        lt[d] = [self clampX:VCX-(NSInteger)((float)VW/2*sc)]; rt[d] = [self clampX:VCX+(NSInteger)((float)VW/2*sc)];
        tp[d] = [self clampY:VCY-(NSInteger)((float)VH/2*sc)]; bt[d] = [self clampY:VCY+(NSInteger)((float)VH/2*sc)];
    }
    NSInteger cx2 = _px, cy2 = _py;
    for (NSInteger d = 0; d <= depth; d++) {
        float bright = MAX(0.2f, 1.0f - (float)d*0.1f);
        BOOL hl = ![self wall:cx2 y:cy2 dir:(_pdir+3)%4];
        BOOL hr = ![self wall:cx2 y:cy2 dir:(_pdir+1)%4];
        BOOL hf = ![self wall:cx2 y:cy2 dir:_pdir] && d < depth;
        if (!hl) {
            [self vl:lt[d] y1:tp[d] x2:lt[d+1] y2:tp[d+1] b:bright*0.8f];
            [self vl:lt[d] y1:bt[d] x2:lt[d+1] y2:bt[d+1] b:bright*0.8f];
            [self vl:lt[d+1] y1:tp[d+1] x2:lt[d+1] y2:bt[d+1] b:bright*0.6f];
        } else {
            [self vl:lt[d] y1:tp[d] x2:lt[d] y2:bt[d] b:bright*0.5f];
        }
        if (!hr) {
            [self vl:rt[d] y1:tp[d] x2:rt[d+1] y2:tp[d+1] b:bright*0.8f];
            [self vl:rt[d] y1:bt[d] x2:rt[d+1] y2:bt[d+1] b:bright*0.8f];
            [self vl:rt[d+1] y1:tp[d+1] x2:rt[d+1] y2:bt[d+1] b:bright*0.6f];
        } else {
            [self vl:rt[d] y1:tp[d] x2:rt[d] y2:bt[d] b:bright*0.5f];
        }
        if (!hf) {
            [self vl:lt[d+1] y1:tp[d+1] x2:rt[d+1] y2:tp[d+1] b:bright];
            [self vl:lt[d+1] y1:bt[d+1] x2:rt[d+1] y2:bt[d+1] b:bright];
            [self vl:lt[d+1] y1:tp[d+1] x2:lt[d+1] y2:bt[d+1] b:bright*0.8f];
            [self vl:rt[d+1] y1:tp[d+1] x2:rt[d+1] y2:bt[d+1] b:bright*0.8f];
            break;
        }
        cx2 += _DX[_pdir]; cy2 += _DY[_pdir];
    }
    [self vl:VX0 y1:VY0 x2:lt[0] y2:tp[0] b:0.35f]; [self vl:VX1 y1:VY0 x2:rt[0] y2:tp[0] b:0.35f];
    [self vl:VX0 y1:VY1 x2:lt[0] y2:bt[0] b:0.35f]; [self vl:VX1 y1:VY1 x2:rt[0] y2:bt[0] b:0.35f];
    [self vl:VCX-12 y1:VCY x2:VCX-4 y2:VCY b:0.6f]; [self vl:VCX+4 y1:VCY x2:VCX+12 y2:VCY b:0.6f];
    [self vl:VCX y1:VCY-12 x2:VCX y2:VCY-4 b:0.6f]; [self vl:VCX y1:VCY+4 x2:VCX y2:VCY+12 b:0.6f];
}

- (void)drawEnemiesInView {
    for (Enemy *e in _aiEnemies) { if (e.alive) { [self drawEntityIfVisible:e.x ey:e.y isNet:NO]; } }
    if (_multiMode && _netAlive) { [self drawEntityIfVisible:_netX ey:_netY isNet:YES]; }
}

- (void)drawEntityIfVisible:(NSInteger)ex ey:(NSInteger)ey isNet:(BOOL)isNet {
    NSInteger relDir = -1;
    if (_pdir==0 && ex==_px && ey>_py) relDir=0;
    if (_pdir==1 && ey==_py && ex>_px) relDir=1;
    if (_pdir==2 && ex==_px && ey<_py) relDir=2;
    if (_pdir==3 && ey==_py && ex<_px) relDir=3;
    if (relDir != _pdir) return;
    NSInteger dist = (_pdir==0||_pdir==2) ? labs(ey-_py) : labs(ex-_px);
    if (!(dist>=1 && dist<=8)) return;
    for (NSInteger d = 0; d < dist; d++) {
        if ([self wall:_px+_DX[_pdir]*d y:_py+_DY[_pdir]*d dir:_pdir]) return;
    }
    float sc = 1.4f / ((float)dist + 0.5f);
    NSInteger sz = MAX((NSInteger)8, MIN((NSInteger)((float)VH*0.25f*sc), (NSInteger)120));
    float b = MAX(0.3f, 0.9f - (float)dist*0.08f);
    if (isNet && _netHitFlash>0) { b = 1.0f; }
    [self drawEye:VCX cy:VCY sz:sz b:b];
}

- (void)drawEye:(NSInteger)cx cy:(NSInteger)cy sz:(NSInteger)sz b:(float)b {
    NSInteger rx = sz, ry = (NSInteger)((float)sz*0.55f);
    [self circle:cx cy:cy rx:rx ry:ry segs:16 b:b];
    [self circle:cx cy:cy rx:rx/3 ry:(NSInteger)((float)ry*0.7f) segs:10 b:b*1.1f];
    [self vl:cx-rx y1:cy x2:cx+rx y2:cy b:b*0.3f];
    if (sz>25) {
        for (NSInteger i = -2; i <= 2; i++) {
            if (i==0) continue;
            [self vl:cx+i*(rx/3) y1:cy+ry+2 x2:cx+i*(rx/3)+i*4 y2:cy+ry+20 b:b*0.6f];
        }
    }
}

- (void)drawHUD {
    for (NSInteger i = 0; i < 3; i++) {
        NSInteger hx = VX0+20+i*28;
        [self circle:hx cy:VY1+25 rx:9 ry:9 segs:8 b:(i<_hp ? 0.9f : 0.2f)];
    }
    [self txt:[NSString stringWithFormat:@"%04ld", (long)_score] ox:VX1-120 oy:VY1+18 sc:9 b:0.7f];
    NSArray<NSString *> *dirNames = @[@"N",@"E",@"S",@"W"];
    [self txt:dirNames[_pdir] ox:VX1+15 oy:VY1+18 sc:10 b:0.6f];
    [self txt:[NSString stringWithFormat:@"LV%ld", (long)_level] ox:VCX-32 oy:VY0-22 sc:9 b:0.35f];
    if (_fireCd>0) {
        [self vl:VCX-40 y1:VY1+52 x2:VCX-40+(NSInteger)((float)_fireCd/20*80) y2:VY1+52 b:0.4f];
    }
    if (_multiMode) {
        [self txt:[NSString stringWithFormat:@"OPP:%04ld", (long)_netScore] ox:VX0+8 oy:VY1+18 sc:9 b:0.5f];
    }
}

#pragma mark - Draw helpers

- (void)vl:(NSInteger)x1 y1:(NSInteger)y1 x2:(NSInteger)x2 y2:(NSInteger)y2 b:(float)b {
    [_M dlLine:x1 y1:y1 x2:x2 y2:y2 bright:b];
}
- (NSInteger)clampX:(NSInteger)x { return MAX((NSInteger)VX0, MIN((NSInteger)VX1, x)); }
- (NSInteger)clampY:(NSInteger)y { return MAX((NSInteger)VY0, MIN((NSInteger)VY1, y)); }

- (void)circle:(NSInteger)cx cy:(NSInteger)cy rx:(NSInteger)rx ry:(NSInteger)ry segs:(NSInteger)segs b:(float)b {
    NSInteger ppx = cx+rx, ppy = cy;
    for (NSInteger i = 1; i <= segs; i++) {
        double a = (double)i/(double)segs*2*M_PI;
        NSInteger nx = cx+(NSInteger)(cos(a)*rx), ny = cy+(NSInteger)(sin(a)*ry);
        [self vl:ppx y1:ppy x2:nx y2:ny b:b];
        ppx=nx; ppy=ny;
    }
}

#pragma mark - Vector font

static const float kMWFontData[37][8][4] = {
    {{0,0,2,4},{2,4,4,0},{1,2,3,2}},
    {{0,0,0,4},{0,4,2,4},{0,2,2,2},{0,0,2,0},{2,4,3,3},{3,3,2,2},{2,2,3,1},{3,1,2,0}},
    {{3,4,0,4},{0,4,0,0},{0,0,3,0}},
    {{0,0,0,4},{0,4,2,4},{2,4,4,2},{4,2,2,0},{2,0,0,0}},
    {{0,0,0,4},{0,4,4,4},{0,2,3,2},{0,0,4,0}},
    {{0,0,0,4},{0,4,4,4},{0,2,3,2}},
    {{3,4,0,4},{0,4,0,0},{0,0,4,0},{4,0,4,2},{4,2,2,2}},
    {{0,0,0,4},{4,0,4,4},{0,2,4,2}},
    {{1,0,3,0},{1,4,3,4},{2,0,2,4}},
    {{1,4,3,4},{3,4,3,0},{3,0,0,0}},
    {{0,0,0,4},{0,2,4,4},{0,2,4,0}},
    {{0,4,0,0},{0,0,4,0}},
    {{0,0,0,4},{0,4,2,2},{2,2,4,4},{4,4,4,0}},
    {{0,0,0,4},{0,4,4,0},{4,0,4,4}},
    {{0,0,4,0},{4,0,4,4},{4,4,0,4},{0,4,0,0}},
    {{0,0,0,4},{0,4,3,4},{3,4,4,3},{4,3,3,2},{3,2,0,2}},
    {{0,0,4,0},{4,0,4,4},{4,4,0,4},{0,4,0,0},{2,2,4,0}},
    {{0,0,0,4},{0,4,3,4},{3,4,4,3},{4,3,3,2},{3,2,0,2},{2,2,4,0}},
    {{4,4,0,4},{0,4,0,2},{0,2,4,2},{4,2,4,0},{4,0,0,0}},
    {{0,4,4,4},{2,4,2,0}},
    {{0,4,0,0},{0,0,4,0},{4,0,4,4}},
    {{0,4,2,0},{2,0,4,4}},
    {{0,4,1,0},{1,0,2,2},{2,2,3,0},{3,0,4,4}},
    {{0,0,4,4},{4,0,0,4}},
    {{0,4,2,2},{4,4,2,2},{2,2,2,0}},
    {{0,4,4,4},{4,4,0,0},{0,0,4,0}},
    {{0,0,4,0},{4,0,4,4},{4,4,0,4},{0,4,0,0},{0,0,4,4}},
    {{1,4,2,4},{2,4,2,0},{1,0,3,0}},
    {{0,4,4,4},{4,4,4,3},{4,3,0,1},{0,1,0,0},{0,0,4,0}},
    {{0,4,4,4},{4,4,4,0},{0,0,4,0},{0,2,4,2}},
    {{0,4,0,2},{0,2,4,2},{4,4,4,0}},
    {{4,4,0,4},{0,4,0,2},{0,2,4,2},{4,2,4,0},{4,0,0,0}},
    {{4,4,0,4},{0,4,0,0},{0,0,4,0},{4,0,4,2},{4,2,0,2}},
    {{0,4,4,4},{4,4,2,0}},
    {{0,0,4,0},{4,0,4,4},{4,4,0,4},{0,4,0,0},{0,2,4,2}},
    {{4,0,4,4},{4,4,0,4},{0,4,0,2},{0,2,4,2}},
    {},
};
static const int kMWFontSegCount[37] = {3,8,3,5,4,3,5,3,3,3,3,2,4,3,4,5,5,6,5,2,3,2,4,2,3,3,5,3,5,4,3,5,5,2,5,4,0};
static NSString * const kMWChars = @"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ";

- (void)ch:(unichar)c ox:(NSInteger)ox oy:(NSInteger)oy sc:(float)sc b:(float)b {
    unichar upc = (unichar)toupper((int)c);
    NSRange r = [kMWChars rangeOfString:[NSString stringWithCharacters:&upc length:1]];
    if (r.location == NSNotFound) return;
    NSInteger idx = r.location;
    if (idx >= 37) return;
    int n = kMWFontSegCount[idx];
    for (int s = 0; s < n; s++) {
        const float *seg = kMWFontData[idx][s];
        [self vl:ox+(NSInteger)(seg[0]*sc) y1:oy+(NSInteger)(seg[1]*sc)
              x2:ox+(NSInteger)(seg[2]*sc) y2:oy+(NSInteger)(seg[3]*sc) b:b];
    }
}

- (void)txt:(NSString *)s ox:(NSInteger)ox oy:(NSInteger)oy sc:(float)sc b:(float)b {
    NSInteger x = ox;
    NSString *up = [s uppercaseString];
    for (NSInteger i = 0; i < (NSInteger)up.length; i++) {
        unichar c = [up characterAtIndex:i];
        [self ch:c ox:x oy:oy sc:sc b:b];
        x += (NSInteger)(sc*5.5f);
    }
}

#pragma mark - NetSessionEventListener

- (void)onConnectedAsHost:(BOOL)asHost seed:(NSInteger)seed {
    [self genMazeWithSeed:seed];
    if (asHost) { _px=1; _py=1; _pdir=0; _netX=14; _netY=14; _netDir=2; }
    else        { _px=14; _py=14; _pdir=2; _netX=1; _netY=1; _netDir=0; }
    _hp=3; _score=0; _netHp=3; _netScore=0; _netAlive=YES;
    [_bullets removeAllObjects];
    _state = GameStatePlay; _msg = @"CONNECTED! FIGHT!"; _msgT = 50;
}

- (void)onPeerMazeStateX:(NSInteger)x y:(NSInteger)y dir:(NSInteger)dir hp:(NSInteger)hp2 score:(NSInteger)sc {
    _netX=x; _netY=y; _netDir=dir; _netHp=hp2; _netScore=sc; _netAlive=(hp2>0);
}

- (void)onPeerSyncDemoIdx:(NSInteger)demoIdx keyboard:(NSInteger)keyboard {}

- (void)onPeerBulletDir:(NSInteger)dir {
    [_bullets addObject:[[Bullet alloc] initWithX:(double)_netX+0.5 y:(double)_netY+0.5 dir:dir fromPlayer:NO]];
}

- (void)onPeerKilled {
    _netAlive=NO; _netHitFlash=20; _msg=@"OPPONENT KILLED!"; _msgT=40;
}

- (void)onDisconnected {
    _msg=@"DISCONNECTED"; _msgT=80; _multiMode=NO;
    _state = (_state == GameStatePlay) ? GameStateDead : GameStateTitle;
}

@end
