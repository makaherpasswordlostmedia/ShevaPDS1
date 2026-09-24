// CrtView.m — Phosphor CRT renderer using Core Graphics for iOS 7+
// Ported from CrtView.swift (originally CrtView.java, Android Canvas)
//
// Performance notes (tuned for A5-class devices such as the iPad 2):
//  * A frame is rendered into an opaque BGRA bitmap and handed to Core Animation
//    as layer contents (GPU composited). No drawRect: pass, no per-frame UIImage.
//  * Scanlines + vignette are baked ONCE into a static overlay layer instead of
//    being redrawn (and a radial gradient re-created) every frame.
//  * Vectors are grouped by quantized brightness and stroked with a handful of
//    CGContextStrokeLineSegments calls instead of 3 strokes + 3 UIColors per vector.
//  * The render resolution adapts automatically (1.0x -> 0.75x -> 0.5x of native
//    pixels) when a frame does not fit into the frame budget.
#import "CrtView.h"
#import <QuartzCore/QuartzCore.h>

#define CRT_PDS        1024
#define CRT_BUCKETS    10       // brightness levels: 0.1, 0.2 ... 1.0
#define CRT_MIN_SCALE  0.5      // lowest render scale (relative to native pixels)

// BEGIN_GROUP (also unit-tested standalone, keep it free of UIKit/ObjC)
static inline int CrtBucket(float b) {
    int q = (int)(b * CRT_BUCKETS + 0.5f);
    if (q < 1) return -1;                       // invisible
    if (q > CRT_BUCKETS) q = CRT_BUCKETS;
    return q - 1;
}

// Counting sort of the display list into per-brightness buckets.
// Lines  -> segPts (2 points per line), bucket k = [lineOff[k], lineOff[k+1])
// Points -> ptPts  (1 point),           bucket k = [ptOff[k],   ptOff[k+1])
// Bounds-checked on write: the MP thread may touch the list while we read it.
static void CrtGroupVectors(const MachineVec *vecs, NSInteger nv, CGFloat sx, CGFloat sy,
                            CGPoint *segPts, NSInteger *lineOff,
                            CGPoint *ptPts, NSInteger *ptOff) {
    NSInteger lc[CRT_BUCKETS], pc[CRT_BUCKETS];
    NSInteger lpos[CRT_BUCKETS], ppos[CRT_BUCKETS];
    for (int k = 0; k < CRT_BUCKETS; k++) { lc[k] = 0; pc[k] = 0; }

    for (NSInteger i = 0; i < nv; i++) {
        int k = CrtBucket(vecs[i].bright);
        if (k < 0) continue;
        if (vecs[i].isPoint) pc[k]++; else lc[k]++;
    }
    lineOff[0] = 0; ptOff[0] = 0;
    for (int k = 0; k < CRT_BUCKETS; k++) {
        lpos[k] = lineOff[k]; ppos[k] = ptOff[k];
        lineOff[k + 1] = lineOff[k] + lc[k];
        ptOff[k + 1]   = ptOff[k]   + pc[k];
    }
    for (NSInteger i = 0; i < nv; i++) {
        MachineVec v = vecs[i];
        int k = CrtBucket(v.bright);
        if (k < 0) continue;
        if (v.isPoint) {
            if (ppos[k] < ptOff[k + 1]) {
                ptPts[ppos[k]++] = CGPointMake((CGFloat)v.x1 * sx, (CGFloat)v.y1 * sy);
            }
        } else if (lpos[k] < lineOff[k + 1]) {
            // No axis flip: font glyph data is authored in screen-space (Y down).
            NSInteger j = 2 * lpos[k]++;
            segPts[j]     = CGPointMake((CGFloat)v.x1 * sx, (CGFloat)v.y1 * sy);
            segPts[j + 1] = CGPointMake((CGFloat)v.x2 * sx, (CGFloat)v.y2 * sy);
        }
    }
}
// END_GROUP

@interface CrtView () {
    CGContextRef _offContext;
    CGSize       _offSize;          // view size (points) the bitmap was built for
    size_t       _bmpW, _bmpH;      // bitmap size in pixels
    CGFloat      _renderScale;      // 1.0 = native pixels, lower = cheaper

    CALayer     *_frameLayer;       // holds the rendered phosphor image
    CALayer     *_overlayLayer;     // static scanlines + vignette
    CGSize       _overlaySize;

    CGPoint     *_segPts;           // scratch: line endpoints grouped by brightness
    CGPoint     *_ptPts;            // scratch: point centers grouped by brightness

    CFTimeInterval _avgCost;        // moving average of CPU time per frame
    NSInteger      _framesSinceScale;

    CADisplayLink *_displayLink;
    CFTimeInterval _fpsTime;
    NSInteger      _fpsCnt;
    CFTimeInterval _lastFrame;
}
@end

@implementation CrtView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) { [self commonInit]; }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) { [self commonInit]; }
    return self;
}

- (void)commonInit {
    self.backgroundColor = [UIColor blackColor];
    self.opaque = YES;
    self.contentMode = UIViewContentModeScaleToFill;
    _maxFps = 30;
    _offSize = CGSizeZero;
    _overlaySize = CGSizeZero;

    // Retina: start at point resolution (0.5x native); non-retina: native.
    _renderScale = ([UIScreen mainScreen].scale >= 2.0) ? 0.5 : 1.0;

    _segPts = (CGPoint *)malloc(sizeof(CGPoint) * 2 * MACHINE_MAX_VEC);
    _ptPts  = (CGPoint *)malloc(sizeof(CGPoint) * MACHINE_MAX_VEC);

    // Plain CALayers (no delegate) are never redrawn by UIKit; kill implicit animations.
    NSDictionary *noAnim = @{ @"contents": [NSNull null],
                              @"bounds":   [NSNull null],
                              @"position": [NSNull null] };

    _frameLayer = [CALayer layer];
    _frameLayer.opaque = YES;
    _frameLayer.actions = noAnim;
    _frameLayer.magnificationFilter = kCAFilterLinear;
    [self.layer addSublayer:_frameLayer];

    _overlayLayer = [CALayer layer];
    _overlayLayer.opaque = NO;
    _overlayLayer.actions = noAnim;
    [self.layer addSublayer:_overlayLayer];
}

- (void)dealloc {
    [_displayLink invalidate];
    if (_offContext) { CGContextRelease(_offContext); _offContext = NULL; }
    free(_segPts);
    free(_ptPts);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _frameLayer.frame = self.bounds;
    _overlayLayer.frame = self.bounds;
    [CATransaction commit];
    if (!CGSizeEqualToSize(self.bounds.size, _offSize)) { [self recreateBitmap]; }
}

- (void)start {
    [self stop];
    [self recreateBitmap];
    _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    // 60 Hz display, 30 fps target -> fire every 2nd vsync
    NSInteger interval = (NSInteger)lround(60.0 / (double)MAX((NSInteger)1, _maxFps));
    _displayLink.frameInterval = MAX((NSInteger)1, interval);
    [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)stop {
    [_displayLink invalidate];
    _displayLink = nil;
}

- (void)recreateBitmap {
    CGSize sz = self.bounds.size;
    if (!(sz.width > 0 && sz.height > 0)) return;
    _offSize = sz;
    CGFloat px = [UIScreen mainScreen].scale * _renderScale;
    size_t w = (size_t)(sz.width * px), h = (size_t)(sz.height * px);
    if (!(w > 0 && h > 0)) return;

    if (_offContext) { CGContextRelease(_offContext); _offContext = NULL; }
    // Opaque BGRA = Core Animation's native format (no conversion on upload).
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    _offContext = CGBitmapContextCreate(NULL, w, h, 8, w * 4, cs,
        (CGBitmapInfo)(kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little));
    CGColorSpaceRelease(cs);
    if (_offContext) {
        _bmpW = w; _bmpH = h;
        CGContextSetRGBFillColor(_offContext, 0, 0, 0, 1);
        CGContextFillRect(_offContext, CGRectMake(0, 0, (CGFloat)w, (CGFloat)h));
        CGContextSetLineCap(_offContext, kCGLineCapRound);
    }
    if (!CGSizeEqualToSize(sz, _overlaySize)) { [self rebuildOverlay]; }
}

// Scanlines + vignette, rendered once at native screen resolution.
- (void)rebuildOverlay {
    CGSize sz = self.bounds.size;
    CGFloat scale = [UIScreen mainScreen].scale;
    size_t w = (size_t)(sz.width * scale), h = (size_t)(sz.height * scale);
    if (!(w > 0 && h > 0)) return;

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(NULL, w, h, 8, w * 4, cs,
        (CGBitmapInfo)(kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little));
    if (c) {
        CGContextClearRect(c, CGRectMake(0, 0, (CGFloat)w, (CGFloat)h));

        // Scanlines: 1pt dark line every 3pt
        CGContextSetRGBFillColor(c, 0, 0, 0, 0.07);
        CGContextBeginPath(c);
        for (CGFloat y = 0; y < (CGFloat)h; y += 3.0 * scale) {
            CGContextAddRect(c, CGRectMake(0, y, (CGFloat)w, scale));
        }
        CGContextFillPath(c);

        // Vignette
        CGPoint center = CGPointMake((CGFloat)w * 0.5, (CGFloat)h * 0.5);
        CGFloat radius = (CGFloat)MAX(w, h) * 0.65;
        CGFloat comps[8] = { 0, 0, 0, 0,   0, 0, 0, 0.6 };
        CGFloat locs[2] = { 0, 1 };
        CGGradientRef grad = CGGradientCreateWithColorComponents(cs, comps, locs, 2);
        if (grad) {
            CGContextDrawRadialGradient(c, grad, center, 0, center, radius, 0);
            CGGradientRelease(grad);
        }

        CGImageRef img = CGBitmapContextCreateImage(c);
        if (img) {
            _overlayLayer.contents = (__bridge id)img;
            CGImageRelease(img);
            _overlaySize = sz;
        }
        CGContextRelease(c);
    }
    CGColorSpaceRelease(cs);
}

- (void)tick:(CADisplayLink *)link {
    CFTimeInterval now = link.timestamp;
    double frameDur = 1.0 / (double)_maxFps;
    if (now - _lastFrame < frameDur * 0.95) return;
    _lastFrame = now;

    Machine *m = self.machine;
    Demos *d = self.demos;
    if (!m || !d || !_offContext) return;

    CFTimeInterval t0 = CACurrentMediaTime();

    [m dlClear];
    [d runCurrentDemo];
    [self renderFrame:m ctx:_offContext];

    CGImageRef cgImg = CGBitmapContextCreateImage(_offContext);
    if (cgImg) {
        _frameLayer.contents = (__bridge id)cgImg;   // Core Animation retains it
        CGImageRelease(cgImg);
    }

    // Adaptive quality: step the render resolution down if we blow the frame budget.
    CFTimeInterval cost = CACurrentMediaTime() - t0;
    _avgCost = (_avgCost <= 0) ? cost : (_avgCost * 0.9 + cost * 0.1);
    _framesSinceScale += 1;
    if (_framesSinceScale >= 20 && _avgCost > frameDur * 0.8 &&
        _renderScale > CRT_MIN_SCALE + 0.01) {
        _renderScale = MAX(CRT_MIN_SCALE, _renderScale - 0.25);
        _framesSinceScale = 0;
        _avgCost = 0;
        [self recreateBitmap];
    }

    _fpsCnt += 1;
    if (now - _fpsTime >= 1.0) {
        _actualFps = (float)_fpsCnt;
        _fpsCnt = 0;
        _fpsTime = now;
    }
}

- (void)renderFrame:(Machine *)m ctx:(CGContextRef)ctx {
    const CGFloat sw = (CGFloat)_bmpW, sh = (CGFloat)_bmpH;
    const CGFloat sx = sw / (CGFloat)CRT_PDS;
    const CGFloat sy = sh / (CGFloat)CRT_PDS;
    const CGFloat rs = _renderScale;

    // Phosphor decay
    CGContextSetRGBFillColor(ctx, 0, 0, 0, 0.15);
    CGContextFillRect(ctx, CGRectMake(0, 0, sw, sh));

    NSInteger lineOff[CRT_BUCKETS + 1], ptOff[CRT_BUCKETS + 1];
    CrtGroupVectors(m.vecs, m.nvec, sx, sy, _segPts, lineOff, _ptPts, ptOff);

    // Three passes: outer glow, mid glow, core. Each pass strokes every brightness
    // bucket in one call, so cores always sit on top of all glows.
    static const CGFloat kR[3]      = { 0.0,         0.0,         20.0 / 255 };
    static const CGFloat kG[3]      = { 140.0 / 255, 200.0 / 255, 1.0        };
    static const CGFloat kB[3]      = { 35.0 / 255,  50.0 / 255,  65.0 / 255 };
    static const CGFloat kLineA[3]  = { 0.12, 0.38, 1.0 };
    static const CGFloat kPointA[3] = { 0.12, 0.35, 1.0 };
    // widths/radii are in bitmap pixels; scale with render resolution, keep them visible
    const CGFloat lineW[3]  = { (CGFloat)MAX(3.0, 8.0 * rs), (CGFloat)MAX(1.5, 3.5 * rs), (CGFloat)MAX(1.0, 1.3 * rs) };
    const CGFloat pointR[3] = { (CGFloat)MAX(2.5, 5.0 * rs), (CGFloat)MAX(1.5, 2.5 * rs), (CGFloat)MAX(1.0, 1.2 * rs) };

    for (int pass = 0; pass < 3; pass++) {
        CGContextSetLineWidth(ctx, lineW[pass]);
        for (int k = 0; k < CRT_BUCKETS; k++) {
            NSInteger n = lineOff[k + 1] - lineOff[k];
            if (n <= 0) continue;
            CGFloat a = (CGFloat)(k + 1) / (CGFloat)CRT_BUCKETS;
            CGContextSetRGBStrokeColor(ctx, kR[pass], kG[pass], kB[pass], a * kLineA[pass]);
            CGContextStrokeLineSegments(ctx, _segPts + 2 * lineOff[k], (size_t)(2 * n));
        }
        const CGFloat r = pointR[pass];
        for (int k = 0; k < CRT_BUCKETS; k++) {
            NSInteger n = ptOff[k + 1] - ptOff[k];
            if (n <= 0) continue;
            CGFloat a = (CGFloat)(k + 1) / (CGFloat)CRT_BUCKETS;
            CGContextSetRGBFillColor(ctx, kR[pass], kG[pass], kB[pass], a * kPointA[pass]);
            const CGPoint *p = _ptPts + ptOff[k];
            CGContextBeginPath(ctx);
            for (NSInteger i = 0; i < n; i++) {
                CGContextAddEllipseInRect(ctx, CGRectMake(p[i].x - r, p[i].y - r, 2 * r, 2 * r));
            }
            CGContextFillPath(ctx);
        }
    }
}

- (CGPoint)screenToPDS:(CGPoint)pt {
    CGFloat x = pt.x / self.bounds.size.width * (CGFloat)CRT_PDS;
    CGFloat y = pt.y / self.bounds.size.height * (CGFloat)CRT_PDS;
    return CGPointMake(x, y);
}

@end
