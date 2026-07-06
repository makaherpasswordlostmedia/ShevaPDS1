// CrtView.m — Phosphor CRT renderer using Core Graphics for iOS
// Ported from CrtView.swift (originally CrtView.java, Android Canvas)
#import "CrtView.h"

#define CRT_PDS 1024

@interface CrtView () {
    UIColor *_colorCore;
    UIColor *_colorMid;
    UIColor *_colorOuter;
    UIColor *_colorDecay;

    UIImage *_offBitmap;
    CGContextRef _offContext;
    CGSize _offSize;

    CADisplayLink *_displayLink;
    CFTimeInterval _fpsTime;
    NSInteger _fpsCnt;
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
    self.contentMode = UIViewContentModeRedraw;
    _colorCore  = [UIColor colorWithRed:20.0/255 green:1.0 blue:65.0/255 alpha:1.0];
    _colorMid   = [UIColor colorWithRed:0 green:200.0/255 blue:50.0/255 alpha:0.43];
    _colorOuter = [UIColor colorWithRed:0 green:140.0/255 blue:35.0/255 alpha:0.14];
    _colorDecay = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.15];
    _maxFps = 30;
    _offSize = CGSizeZero;
}

- (void)dealloc {
    if (_offContext) { CGContextRelease(_offContext); _offContext = NULL; }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!CGSizeEqualToSize(self.bounds.size, _offSize)) { [self recreateBitmap]; }
}

- (void)start {
    [self stop];
    [self recreateBitmap];
    _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
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
    CGFloat scale = [UIScreen mainScreen].scale;
    NSInteger w = (NSInteger)(sz.width * scale), h = (NSInteger)(sz.height * scale);
    if (!(w > 0 && h > 0)) return;

    if (_offContext) { CGContextRelease(_offContext); _offContext = NULL; }
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    _offContext = CGBitmapContextCreate(NULL, w, h, 8, w * 4, cs,
                                         kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(cs);
    if (_offContext) {
        CGContextSetFillColorWithColor(_offContext, [UIColor blackColor].CGColor);
        CGContextFillRect(_offContext, CGRectMake(0, 0, w, h));
    }
}

- (void)tick:(CADisplayLink *)link {
    CFTimeInterval now = link.timestamp;
    double frameDur = 1.0 / (double)_maxFps;
    if (now - _lastFrame < frameDur * 0.95) return;
    _lastFrame = now;

    Machine *m = self.machine;
    Demos *d = self.demos;
    if (!m || !d || !_offContext) return;

    [m dlClear];
    [d runCurrentDemo];
    [self renderFrame:m ctx:_offContext];

    CGImageRef cgImg = CGBitmapContextCreateImage(_offContext);
    if (cgImg) {
        _offBitmap = [UIImage imageWithCGImage:cgImg scale:[UIScreen mainScreen].scale orientation:UIImageOrientationUp];
        CGImageRelease(cgImg);
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [self setNeedsDisplay];
    });

    _fpsCnt += 1;
    if (now - _fpsTime >= 1.0) {
        _actualFps = (float)_fpsCnt;
        _fpsCnt = 0;
        _fpsTime = now;
    }
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    if (_offBitmap) {
        [_offBitmap drawInRect:self.bounds];
    }

    // Scanlines overlay
    CGFloat h = self.bounds.size.height;
    CGContextSetLineWidth(ctx, 1.0);
    CGContextSetStrokeColorWithColor(ctx, [UIColor colorWithWhite:0 alpha:0.07].CGColor);
    CGFloat y = 0;
    while (y < h) {
        CGContextMoveToPoint(ctx, 0, y);
        CGContextAddLineToPoint(ctx, self.bounds.size.width, y);
        y += 3;
    }
    CGContextStrokePath(ctx);

    // Vignette
    CGPoint center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    CGFloat radius = MAX(self.bounds.size.width, self.bounds.size.height) * 0.65;
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGFloat locations[2] = {0, 1};
    NSArray *colors = @[(id)[UIColor clearColor].CGColor, (id)[UIColor colorWithWhite:0 alpha:0.6].CGColor];
    CGGradientRef grad = CGGradientCreateWithColors(cs, (CFArrayRef)colors, locations);
    if (grad) {
        CGContextDrawRadialGradient(ctx, grad, center, 0, center, radius, 0);
        CGGradientRelease(grad);
    }
    CGColorSpaceRelease(cs);
}

- (void)renderFrame:(Machine *)m ctx:(CGContextRef)ctx {
    CGFloat scale = [UIScreen mainScreen].scale;
    CGFloat sw = _offSize.width * scale;
    CGFloat sh = _offSize.height * scale;
    CGFloat sx = sw / (CGFloat)CRT_PDS;
    CGFloat sy = sh / (CGFloat)CRT_PDS;

    // Phosphor decay
    CGContextSetFillColorWithColor(ctx, _colorDecay.CGColor);
    CGContextFillRect(ctx, CGRectMake(0, 0, sw, sh));

    CGContextSetLineCap(ctx, kCGLineCapRound);

    NSInteger nv = m.nvec;
    MachineVec *vecs = m.vecs;
    for (NSInteger i = 0; i < nv; i++) {
        MachineVec v = vecs[i];
        float b = v.bright;
        if (b < 0.04f) continue;

        // No axis flip: font glyph data is authored in screen-space (Y down).
        CGFloat x1 = (CGFloat)v.x1 * sx;
        CGFloat y1 = (CGFloat)v.y1 * sy;

        if (v.isPoint) {
            // Outer glow
            CGContextSetFillColorWithColor(ctx, [UIColor colorWithRed:0 green:140.0/255 blue:35.0/255 alpha:b*0.12].CGColor);
            CGContextFillEllipseInRect(ctx, CGRectMake(x1-5, y1-5, 10, 10));
            // Mid
            CGContextSetFillColorWithColor(ctx, [UIColor colorWithRed:0 green:200.0/255 blue:50.0/255 alpha:b*0.35].CGColor);
            CGContextFillEllipseInRect(ctx, CGRectMake(x1-2.5, y1-2.5, 5, 5));
            // Core
            CGContextSetFillColorWithColor(ctx, [UIColor colorWithRed:20.0/255 green:1.0 blue:65.0/255 alpha:b].CGColor);
            CGContextFillEllipseInRect(ctx, CGRectMake(x1-1.2, y1-1.2, 2.4, 2.4));
        } else {
            CGFloat x2 = (CGFloat)v.x2 * sx;
            CGFloat y2 = (CGFloat)v.y2 * sy;
            // Outer glow
            CGContextSetStrokeColorWithColor(ctx, [UIColor colorWithRed:0 green:140.0/255 blue:35.0/255 alpha:b*0.12].CGColor);
            CGContextSetLineWidth(ctx, 8);
            CGContextMoveToPoint(ctx, x1, y1); CGContextAddLineToPoint(ctx, x2, y2); CGContextStrokePath(ctx);
            // Mid
            CGContextSetStrokeColorWithColor(ctx, [UIColor colorWithRed:0 green:200.0/255 blue:50.0/255 alpha:b*0.38].CGColor);
            CGContextSetLineWidth(ctx, 3.5);
            CGContextMoveToPoint(ctx, x1, y1); CGContextAddLineToPoint(ctx, x2, y2); CGContextStrokePath(ctx);
            // Core
            CGContextSetStrokeColorWithColor(ctx, [UIColor colorWithRed:20.0/255 green:1.0 blue:65.0/255 alpha:b].CGColor);
            CGContextSetLineWidth(ctx, 1.3);
            CGContextMoveToPoint(ctx, x1, y1); CGContextAddLineToPoint(ctx, x2, y2); CGContextStrokePath(ctx);
        }
    }
}

- (CGPoint)screenToPDS:(CGPoint)pt {
    CGFloat x = pt.x / self.bounds.size.width * (CGFloat)CRT_PDS;
    CGFloat y = pt.y / self.bounds.size.height * (CGFloat)CRT_PDS;
    return CGPointMake(x, y);
}

@end
