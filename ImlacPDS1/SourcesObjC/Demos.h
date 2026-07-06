// Demos.h — Built-in demo programs for Imlac PDS-1
#import <Foundation/Foundation.h>
#import "Machine.h"

typedef NS_ENUM(NSInteger, DemoType) {
    DemoTypeLines = 0,
    DemoTypeStar,
    DemoTypeLissajous,
    DemoTypeText,
    DemoTypeBounce,
    DemoTypeMaze,
    DemoTypeSpacewar,
    DemoTypeScope,
    DemoTypeUserAsm,
    DemoTypeMazeWar
};

@class MazeWarGame;

@interface Demos : NSObject

@property (nonatomic) DemoType current;
@property (nonatomic) NSInteger frame;
@property (nonatomic, strong, nullable) MazeWarGame *mazeWarGame;

- (instancetype)initWithMachine:(Machine *)machine;

- (nullable MazeWarGame *)getMazeWarGame;
- (NSInteger)currentDemoIndex;
- (void)initMazeWar;

- (void)setDemo:(DemoType)t;
- (void)runCurrentDemo;

- (void)vchar:(unichar)c ox:(NSInteger)ox oy:(NSInteger)oy sc:(float)sc b:(float)b;
- (void)vtext:(NSString *)s ox:(NSInteger)ox oy:(NSInteger)oy sc:(float)sc b:(float)b;

@end
