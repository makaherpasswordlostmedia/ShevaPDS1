// Demos.m — Built-in demo programs for Imlac PDS-1
// Ported from Demos.swift (originally Demos.java)
#import "Demos.h"
#import "MazeWarGame.h"

#define MW 18
#define MH 14

@interface Demos () {
    Machine *_M;
    double _angle;
    double _t;

    double _ballX, _ballY, _ballVx, _ballVy;
    double _trailX[16];
    double _trailY[16];
    NSInteger _trailN;

    NSInteger _mazeGrid[MH][MW];
    BOOL _mazeReady;

    double _sw1x, _sw1y, _sw1a, _sw1vx, _sw1vy;
    double _sw2x, _sw2y, _sw2a, _sw2vx, _sw2vy;
    double _bx[4], _by[4], _bvx[4], _bvy[4];
    NSInteger _blife[4];
    BOOL _swInit;
    double _textScroll;
}
@end

@implementation Demos

- (instancetype)initWithMachine:(Machine *)machine {
    self = [super init];
    if (self) {
        _M = machine;
        _current = DemoTypeStar;
        _angle = 0.0; _t = 0.0; _frame = 0;
        _ballX = 512.0; _ballY = 512.0; _ballVx = 7.3; _ballVy = 5.8;
        _trailN = 0;
        _mazeReady = NO;
        _sw1x = 350.0; _sw1y = 512.0; _sw1a = 0.0; _sw1vx = 0.0; _sw1vy = 0.0;
        _sw2x = 674.0; _sw2y = 512.0; _sw2a = M_PI; _sw2vx = 0.0; _sw2vy = 0.0;
        _swInit = NO;
        _textScroll = 0.0;
        memset(_bx, 0, sizeof(_bx)); memset(_by, 0, sizeof(_by));
        memset(_bvx, 0, sizeof(_bvx)); memset(_bvy, 0, sizeof(_bvy));
        memset(_blife, 0, sizeof(_blife));
    }
    return self;
}

- (MazeWarGame *)getMazeWarGame { return _mazeWarGame; }
- (NSInteger)currentDemoIndex { return _current; }

- (void)initMazeWar {
    if (_mazeWarGame == nil) { _mazeWarGame = [[MazeWarGame alloc] initWithMachine:_M]; }
}

- (void)setDemo:(DemoType)t { _current = t; }

- (void)runCurrentDemo {
    switch (_current) {
        case DemoTypeLines:     [self demoLines]; break;
        case DemoTypeStar:      [self demoStar]; break;
        case DemoTypeLissajous: [self demoLissajous]; break;
        case DemoTypeText:      [self demoText]; break;
        case DemoTypeBounce:    [self demoBounce]; break;
        case DemoTypeMaze:      [self demoMaze]; break;
        case DemoTypeSpacewar:  [self demoSpacewar]; break;
        case DemoTypeScope:     [self demoScope]; break;
        case DemoTypeUserAsm:   break;
        case DemoTypeMazeWar:   [self demoMazeWar]; break;
    }
    _angle += 0.018; _t += 0.016; _frame += 1;
}

#pragma mark - Helpers

- (void)vl:(NSInteger)x1 y1:(NSInteger)y1 x2:(NSInteger)x2 y2:(NSInteger)y2 b:(float)b {
    [_M dlLine:x1 y1:y1 x2:x2 y2:y2 bright:b];
}
- (void)vp:(NSInteger)x y:(NSInteger)y b:(float)b {
    [_M dlPoint:x y:y bright:b];
}
- (void)rect:(NSInteger)x y:(NSInteger)y w:(NSInteger)w h:(NSInteger)h b:(float)b {
    [self vl:x y1:y x2:x+w y2:y b:b];
    [self vl:x+w y1:y x2:x+w y2:y+h b:b];
    [self vl:x+w y1:y+h x2:x y2:y+h b:b];
    [self vl:x y1:y+h x2:x y2:y b:b];
}
- (void)circle:(NSInteger)cx cy:(NSInteger)cy r:(NSInteger)r segs:(NSInteger)segs b:(float)b {
    NSInteger px = cx + r, py = cy;
    for (NSInteger i = 1; i <= segs; i++) {
        double a = (double)i / (double)segs * 2 * M_PI;
        NSInteger nx = cx + (NSInteger)(cos(a) * r), ny = cy + (NSInteger)(sin(a) * r);
        [self vl:px y1:py x2:nx y2:ny b:b];
        px = nx; py = ny;
    }
}
- (void)border:(float)b { [self rect:20 y:20 w:984 h:984 b:b]; }

#pragma mark - Vector font

// FONT[charIndex] = array of segments [x1,y1,x2,y2]
static const float kFontData[37][8][4] = {
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
    {}, // space (index 36, no segments)
};
static const int kFontSegCount[37] = {3,8,3,5,4,3,5,3,3,3,3,2,4,3,4,5,5,6,5,2,3,2,4,2,3,3,5,3,5,4,3,5,5,2,5,4,0};

static NSString * const kChars = @"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ";

- (void)vchar:(unichar)c ox:(NSInteger)ox oy:(NSInteger)oy sc:(float)sc b:(float)b {
    unichar upc = (unichar)toupper((int)c);
    NSRange r = [kChars rangeOfString:[NSString stringWithCharacters:&upc length:1]];
    if (r.location == NSNotFound) return;
    NSInteger idx = r.location;
    if (idx >= 37) return;
    int n = kFontSegCount[idx];
    for (int s = 0; s < n; s++) {
        const float *seg = kFontData[idx][s];
        [self vl:ox + (NSInteger)(seg[0]*sc) y1:oy + (NSInteger)(seg[1]*sc)
              x2:ox + (NSInteger)(seg[2]*sc) y2:oy + (NSInteger)(seg[3]*sc) b:b];
    }
}

- (void)vtext:(NSString *)s ox:(NSInteger)ox oy:(NSInteger)oy sc:(float)sc b:(float)b {
    NSInteger x = ox;
    NSString *up = [s uppercaseString];
    for (NSInteger i = 0; i < (NSInteger)up.length; i++) {
        unichar c = [up characterAtIndex:i];
        [self vchar:c ox:x oy:oy sc:sc b:b];
        x += (NSInteger)(sc * 5.5f);
    }
}

#pragma mark - LINES

- (void)demoLines {
    NSInteger cx = 512, cy = 512; double r = 450.0;
    for (NSInteger i = 0; i < 20; i++) {
        double a1 = (double)i / 20 * 2 * M_PI + _angle;
        double a2 = (double)(i + 7) / 20 * 2 * M_PI + _angle * 0.7;
        [self vl:cx + (NSInteger)(cos(a1)*r) y1:cy + (NSInteger)(sin(a1)*r)
              x2:cx + (NSInteger)(cos(a2)*r/2) y2:cy + (NSInteger)(sin(a2)*r/2) b:0.85f];
    }
    for (NSInteger i = 0; i < 8; i++) {
        double a = (double)i / 8 * 2 * M_PI - _angle * 0.3;
        [self vl:cx y1:cy x2:cx + (NSInteger)(cos(a)*r) y2:cy + (NSInteger)(sin(a)*r) b:0.3f];
    }
    [self border:0.5f];
    [self vtext:@"IMLAC PDS-1" ox:280 oy:80 sc:16 b:0.7f];
    [self vtext:@"ROTATING LINES" ox:200 oy:30 sc:10 b:0.4f];
}

#pragma mark - STAR

- (void)drawStar:(NSInteger)cx cy:(NSInteger)cy pts:(NSInteger)pts r1:(NSInteger)r1 r2:(NSInteger)r2 a0:(double)a0 b:(float)b {
    NSInteger n = pts * 2;
    for (NSInteger i = 0; i < n; i++) {
        double a1 = (double)i / (double)n * 2 * M_PI + a0;
        double a2 = (double)(i + 1) / (double)n * 2 * M_PI + a0;
        NSInteger ra = (i % 2 == 0) ? r1 : r2;
        NSInteger rb = ((i + 1) % 2 == 0) ? r1 : r2;
        [self vl:cx + (NSInteger)(cos(a1)*ra) y1:cy + (NSInteger)(sin(a1)*ra)
              x2:cx + (NSInteger)(cos(a2)*rb) y2:cy + (NSInteger)(sin(a2)*rb) b:b];
    }
}

- (void)demoStar {
    [self drawStar:512 cy:512 pts:7 r1:400 r2:160 a0:_angle b:1.0f];
    [self drawStar:512 cy:512 pts:5 r1:120 r2:50 a0:-_angle*2.5 b:0.7f];
    [self border:0.4f];
    [self vtext:@"STAR" ox:380 oy:60 sc:20 b:0.6f];
}

#pragma mark - LISSAJOUS

- (void)demoLissajous {
    NSInteger px = -1, py = -1;
    for (NSInteger i = 0; i <= 600; i++) {
        double tt = (double)i / 600 * 2 * M_PI;
        NSInteger x = 512 + (NSInteger)(460 * sin(3*tt + _angle));
        NSInteger y = 512 + (NSInteger)(460 * sin(2*tt));
        if (px >= 0) { [self vl:px y1:py x2:x y2:y b:0.85f]; }
        px = x; py = y;
    }
    [self border:0.4f];
    [self vtext:@"LISSAJOUS" ox:300 oy:60 sc:16 b:0.5f];
}

#pragma mark - TEXT

- (NSArray<NSString *> *)textLines {
    return @[@"IMLAC PDS-1",@"1970 MIT AI LAB",@"PROGRAMMED",@"DISPLAY SYSTEM",
        @"16-BIT CPU",@"4096 WORDS RAM",@"VECTOR CRT",@"1024 X 1024",@"LIGHT PEN",@"SPACEWAR 1974",
        @"ARPANET NODE",@"LOGO LANGUAGE"];
}

- (void)demoText {
    NSArray<NSString *> *lines = [self textLines];
    for (NSInteger i = 0; i < (NSInteger)lines.count; i++) {
        double raw = 780.0 - (double)i * 140 + _textScroll;
        double modv = fmod(raw, 1100.0);
        if (modv < 0) modv += 1100.0;
        NSInteger y = (NSInteger)modv - 100;
        if (y > -80 && y < 1050) { [self vtext:lines[i] ox:80 oy:y sc:20 b:0.9f]; }
    }
    _textScroll += 1.5;
    if (_textScroll > (double)lines.count * 145) { _textScroll = 0; }
    [self border:0.3f];
}

#pragma mark - BOUNCE

- (void)demoBounce {
    _ballX += _ballVx; _ballY += _ballVy;
    if (_ballX < 60 || _ballX > 964) { _ballVx *= -1; _ballX = MAX(60.0, MIN(964.0, _ballX)); }
    if (_ballY < 60 || _ballY > 964) { _ballVy *= -1; _ballY = MAX(60.0, MIN(964.0, _ballY)); }
    if (_trailN < 15) {
        _trailX[_trailN] = _ballX; _trailY[_trailN] = _ballY; _trailN += 1;
    } else {
        for (int i = 0; i < 14; i++) { _trailX[i] = _trailX[i+1]; _trailY[i] = _trailY[i+1]; }
        _trailX[14] = _ballX; _trailY[14] = _ballY;
    }
    for (NSInteger i = 0; i < _trailN - 1; i++) {
        [self vp:(NSInteger)_trailX[i] y:(NSInteger)_trailY[i] b:(float)(i+1) / (float)_trailN * 0.4f];
    }
    [self circle:(NSInteger)_ballX cy:(NSInteger)_ballY r:35 segs:16 b:1.0f];
    [self vl:(NSInteger)_ballX-50 y1:(NSInteger)_ballY x2:(NSInteger)_ballX+50 y2:(NSInteger)_ballY b:0.25f];
    [self vl:(NSInteger)_ballX y1:(NSInteger)_ballY-50 x2:(NSInteger)_ballX y2:(NSInteger)_ballY+50 b:0.25f];
    NSArray<NSNumber *> *corners = @[@60, @964];
    for (NSNumber *xn in corners) {
        for (NSNumber *yn in corners) {
            [self circle:[xn integerValue] cy:[yn integerValue] r:20 segs:8 b:0.4f];
        }
    }
    [self rect:20 y:20 w:984 h:984 b:0.6f];
    [self vtext:@"BOUNCE" ox:350 oy:40 sc:14 b:0.6f];
}

#pragma mark - MAZE

static const NSInteger kCDX[4] = {0, 1, 0, -1};
static const NSInteger kCDY[4] = {1, 0, -1, 0};
static const NSInteger kCOPP[4] = {2, 3, 0, 1};

- (void)demoMaze {
    if (!_mazeReady) { [self initMaze]; }
    NSInteger cw = (1024 - 60) / MW, ch = (1024 - 60) / MH, ox = 30, oy = 30;
    for (NSInteger y = 0; y < MH; y++) {
        for (NSInteger x = 0; x < MW; x++) {
            NSInteger cell = _mazeGrid[y][x];
            NSInteger px = ox + x*cw, py = oy + y*ch;
            if (cell & 1) { [self vl:px y1:py+ch x2:px+cw y2:py+ch b:0.85f]; }
            if (cell & 2) { [self vl:px+cw y1:py x2:px+cw y2:py+ch b:0.85f]; }
            if (cell & 4) { [self vl:px y1:py x2:px+cw y2:py b:0.85f]; }
            if (cell & 8) { [self vl:px y1:py x2:px y2:py+ch b:0.85f]; }
        }
    }
    [self circle:ox+cw/2 cy:oy+ch/2 r:12 segs:8 b:0.6f];
    [self circle:ox+(MW-1)*cw+cw/2 cy:oy+(MH-1)*ch+ch/2 r:12 segs:8 b:1.0f];
    [self vtext:@"MAZE" ox:370 oy:965 sc:14 b:0.55f];
}

- (void)initMaze {
    for (NSInteger y = 0; y < MH; y++) {
        for (NSInteger x = 0; x < MW; x++) { _mazeGrid[y][x] = 0xF; }
    }
    BOOL vis[MH][MW];
    memset(vis, 0, sizeof(vis));
    [self carveMazeX:0 y:0 vis:vis];
    _mazeReady = YES;
}

- (void)carveMazeX:(NSInteger)x y:(NSInteger)y vis:(BOOL[MH][MW])vis {
    vis[y][x] = YES;
    NSMutableArray<NSNumber *> *dirs = [@[@0,@1,@2,@3] mutableCopy];
    // Fisher-Yates shuffle
    for (NSInteger i = dirs.count - 1; i > 0; i--) {
        NSInteger j = arc4random_uniform((uint32_t)(i + 1));
        [dirs exchangeObjectAtIndex:i withObjectAtIndex:j];
    }
    for (NSNumber *dn in dirs) {
        NSInteger d = [dn integerValue];
        NSInteger nx = x + kCDX[d], ny = y + kCDY[d];
        if (nx < 0 || nx >= MW || ny < 0 || ny >= MH || vis[ny][nx]) continue;
        _mazeGrid[y][x]   &= ~(1 << d);
        _mazeGrid[ny][nx] &= ~(1 << kCOPP[d]);
        [self carveMazeX:nx y:ny vis:vis];
    }
}

#pragma mark - SPACEWAR

- (void)demoSpacewar {
    if (!_swInit) { memset(_blife, 0, sizeof(_blife)); _swInit = YES; }
    _sw1a += 0.025; _sw2a += 0.025;
    double dx1 = 512 - _sw1x, dy1 = 512 - _sw1y; double d1 = sqrt(dx1*dx1 + dy1*dy1);
    if (d1 > 1) { _sw1vx += dx1/d1*0.15; _sw1vy += dy1/d1*0.15; }
    double dx2 = 512 - _sw2x, dy2 = 512 - _sw2y; double d2 = sqrt(dx2*dx2 + dy2*dy2);
    if (d2 > 1) { _sw2vx += dx2/d2*0.15; _sw2vy += dy2/d2*0.15; }
    _sw1x += _sw1vx; _sw1y += _sw1vy; _sw2x += _sw2vx; _sw2y += _sw2vy;

    _sw1x = fmod(_sw1x, 1024); if (_sw1x < 0) _sw1x += 1024;
    _sw1y = fmod(_sw1y, 1024); if (_sw1y < 0) _sw1y += 1024;
    _sw2x = fmod(_sw2x, 1024); if (_sw2x < 0) _sw2x += 1024;
    _sw2y = fmod(_sw2y, 1024); if (_sw2y < 0) _sw2y += 1024;

    if (_frame % 40 == 0) { [self fireSW:_sw1x y:_sw1y a:_sw1a vx:_sw1vx vy:_sw1vy]; }
    if (_frame % 53 == 0) { [self fireSW:_sw2x y:_sw2y a:_sw2a vx:_sw2vx vy:_sw2vy]; }

    for (NSInteger i = 0; i < 4; i++) {
        if (_blife[i] <= 0) continue;
        _blife[i] -= 1;
        _bx[i] += _bvx[i]; _by[i] += _bvy[i];
        [self vp:(NSInteger)_bx[i] y:(NSInteger)_by[i] b:1.0f];
    }
    [self circle:512 cy:512 r:25 segs:12 b:0.6f];
    [self circle:512 cy:512 r:8 segs:8 b:1.0f];
    [self drawShip:(NSInteger)_sw1x cy:(NSInteger)_sw1y a:_sw1a b:1.0f];
    [self drawShip:(NSInteger)_sw2x cy:(NSInteger)_sw2y a:_sw2a + M_PI b:0.85f];
    [self vtext:@"SPACEWAR" ox:310 oy:960 sc:14 b:0.5f];
    [self rect:20 y:20 w:984 h:984 b:0.3f];
}

- (void)fireSW:(double)x y:(double)y a:(double)a vx:(double)vx vy:(double)vy {
    for (NSInteger i = 0; i < 4; i++) {
        if (_blife[i] > 0) continue;
        _bx[i] = x; _by[i] = y;
        _bvx[i] = cos(a)*9 + vx; _bvy[i] = sin(a)*9 + vy;
        _blife[i] = 80;
        break;
    }
}

- (void)drawShip:(NSInteger)cx cy:(NSInteger)cy a:(double)a b:(float)b {
    double r1 = 30.0, r2 = 20.0, da = 2.5;
    NSInteger p1x = cx + (NSInteger)(cos(a)*r1), p1y = cy + (NSInteger)(sin(a)*r1);
    NSInteger p2x = cx + (NSInteger)(cos(a+da)*r2), p2y = cy + (NSInteger)(sin(a+da)*r2);
    NSInteger p3x = cx + (NSInteger)(cos(a-da)*r2), p3y = cy + (NSInteger)(sin(a-da)*r2);
    [self vl:p1x y1:p1y x2:p2x y2:p2y b:b];
    [self vl:p2x y1:p2y x2:p3x y2:p3y b:b];
    [self vl:p3x y1:p3y x2:p1x y2:p1y b:b];
}

#pragma mark - SCOPE

- (void)demoScope {
    double freqA[4] = {1.0, 2.0, 3.0, 5.0};
    double freqB[4] = {1.0, 3.0, 4.0, 4.0};
    float brs[4] = {0.9f, 0.7f, 0.55f, 0.4f};
    for (NSInteger f = 0; f < 4; f++) {
        double ph = _angle * (double)(f+1) * 0.3;
        NSInteger px = -1, py = -1;
        for (NSInteger i = 0; i <= 400; i++) {
            double tt = (double)i / 400 * 2 * M_PI;
            NSInteger x = 512 + (NSInteger)(440 * sin(freqA[f]*tt + ph));
            NSInteger y = 512 + (NSInteger)(440 * sin(freqB[f]*tt));
            if (px >= 0) { [self vl:px y1:py x2:x y2:y b:brs[f]]; }
            px = x; py = y;
        }
    }
    [self border:0.4f];
    [self vtext:@"SCOPE" ox:380 oy:60 sc:14 b:0.5f];
}

#pragma mark - MAZE WAR

- (void)demoMazeWar {
    if (_mazeWarGame == nil) { _mazeWarGame = [[MazeWarGame alloc] initWithMachine:_M]; }
    [_mazeWarGame tick];
    [_mazeWarGame draw];
}

@end
