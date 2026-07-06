// CrtView.h — Phosphor CRT renderer for iOS
#import <UIKit/UIKit.h>
#import "Machine.h"
#import "Demos.h"

@interface CrtView : UIView

@property (nonatomic, strong, nullable) Machine *machine;
@property (nonatomic, strong, nullable) Demos *demos;
@property (nonatomic, readonly) float actualFps;
@property (nonatomic) NSInteger maxFps;

- (void)start;
- (void)stop;

// Returns PDS-space coordinates for a point in view-local coordinates.
- (CGPoint)screenToPDS:(CGPoint)pt;

@end
