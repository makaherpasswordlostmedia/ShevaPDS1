// EmulatorViewController.m — Main iOS UI for Imlac PDS-1 Emulator
// Ported from EmulatorViewController.swift (originally EmulatorActivity.java)
#import "EmulatorViewController.h"
#import "Machine.h"
#import "Demos.h"
#import "CrtView.h"
#import "NetSession.h"
#import "MazeWarGame.h"

// iOS 9.3+/12.0-compatible monospaced font helper.
// UIFont.monospacedSystemFont(ofSize:weight:) requires iOS 13+, so we use
// the Menlo monospace family (available since iOS 2) with a system-font
// fallback in case Menlo is ever unavailable.
static UIFont *MonoFont(CGFloat size) {
    UIFont *f = [UIFont fontWithName:@"Menlo-Regular" size:size];
    return f ?: [UIFont systemFontOfSize:size];
}
static UIFont *MonoFontBold(CGFloat size) {
    UIFont *f = [UIFont fontWithName:@"Menlo-Bold" size:size];
    return f ?: [UIFont boldSystemFontOfSize:size];
}

@interface EmulatorViewController () <UITextFieldDelegate, NetSessionEventListener, NetSessionChatListener> {
    BOOL _mpRunning;
    NSInteger _lastPeerDemo;
    NSInteger _syncSendCd;
    BOOL _keyboardVisible;
    NSMutableArray<NSString *> *_chatLines;
}

// Core
@property (nonatomic, strong) Machine *machine;
@property (nonatomic, strong) Demos *demos;
@property (nonatomic, strong) CrtView *crtView;

// Net
@property (nonatomic, strong, nullable) NetSession *netSession;

// UI — Labels
@property (nonatomic, strong) UILabel *tvFps;
@property (nonatomic, strong) UILabel *tvPc;
@property (nonatomic, strong) UILabel *tvAc;
@property (nonatomic, strong) UILabel *tvNetStatus;
@property (nonatomic, strong) UILabel *tvChatLog;
// Panels
@property (nonatomic, strong) UIView *panelChat;
@property (nonatomic, strong) UIView *panelController;
@property (nonatomic, strong) UIView *panelKeyboard;
// Inputs
@property (nonatomic, strong) UITextField *etChat;
// Buttons (dpad)
@property (nonatomic, strong, nullable) UIButton *btnUp;
@property (nonatomic, strong, nullable) UIButton *btnDown;
@property (nonatomic, strong, nullable) UIButton *btnLeft;
@property (nonatomic, strong, nullable) UIButton *btnRight;

@property (nonatomic, strong) NSTimer *fpsTimer;

@end

@implementation EmulatorViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    _machine = [[Machine alloc] init];
    _chatLines = [NSMutableArray array];
    _lastPeerDemo = -1;
    _demos = [[Demos alloc] initWithMachine:self.machine];
    [self buildUI];
    [self startMP];
    self.crtView.machine = self.machine;
    self.crtView.demos = self.demos;
    [self.crtView start];
    [self startFpsTicker];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.crtView stop];
    _mpRunning = NO;
}

- (BOOL)prefersStatusBarHidden { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskLandscape; }

#pragma mark - Build UI

- (void)buildUI {
    CGFloat W = [UIScreen mainScreen].bounds.size.width;
    CGFloat H = [UIScreen mainScreen].bounds.size.height;

    // CRT display (left ~72%)
    CGFloat crtW = W * 0.72;
    self.crtView = [[CrtView alloc] initWithFrame:CGRectMake(0, 0, crtW, H)];
    self.crtView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.crtView];

    // Right panel
    CGFloat panelX = crtW;
    CGFloat panelW = W - crtW;
    UIScrollView *panel = [[UIScrollView alloc] initWithFrame:CGRectMake(panelX, 0, panelW, H)];
    panel.backgroundColor = [UIColor colorWithWhite:0.04 alpha:1];
    panel.showsVerticalScrollIndicator = NO;
    [self.view addSubview:panel];

    CGFloat y = 8;

    // FPS + registers
    self.tvFps = [self monoLabel:@"31fps" size:8 color:[UIColor greenColor]];
    [panel addSubview:self.tvFps]; self.tvFps.frame = CGRectMake(4, y, panelW-8, 12); y += 14;
    self.tvPc = [self monoLabel:@"PC:0000  AC:0000" size:7 color:[UIColor colorWithWhite:0.6 alpha:1]];
    [panel addSubview:self.tvPc]; self.tvPc.frame = CGRectMake(4, y, panelW-8, 10); y += 12;
    self.tvAc = [self monoLabel:@"IR:0000  L:0" size:7 color:[UIColor colorWithWhite:0.5 alpha:1]];
    [panel addSubview:self.tvAc]; self.tvAc.frame = CGRectMake(4, y, panelW-8, 10); y += 14;

    UIColor *cyan = [UIColor colorWithRed:50.0/255 green:173.0/255 blue:230.0/255 alpha:1];
    UIColor *green = [UIColor colorWithRed:52.0/255 green:199.0/255 blue:89.0/255 alpha:1];
    UIColor *blue = [UIColor colorWithRed:0 green:122.0/255 blue:255.0/255 alpha:1];
    UIColor *red = [UIColor colorWithRed:255.0/255 green:59.0/255 blue:48.0/255 alpha:1];

    // Control buttons row
    y = [self addButtonRow:panel y:y panelW:panelW
        titles:@[@"PWR",@"RST",@"RUN",@"HLT",@"STP"]
        colors:@[green, [UIColor grayColor], blue, red, [UIColor grayColor]]
        actions:@[@"onPwr",@"onRst",@"onRun",@"onHlt",@"onStp"]];

    // Demo buttons
    y = [self addButtonRow:panel y:y panelW:panelW
        titles:@[@"STAR",@"WAVE",@"LISS",@"TEXT",@"BNCE"]
        colors:@[cyan, cyan, cyan, cyan, cyan]
        actions:@[@"onStar",@"onScope",@"onLiss",@"onText",@"onBounce"]];
    y = [self addButtonRow:panel y:y panelW:panelW
        titles:@[@"MAZE",@"WARS",@"SPWR",@"MAZE WAR",@"GAMES"]
        colors:@[cyan, cyan, cyan, [UIColor colorWithRed:0.1 green:0.8 blue:0.1 alpha:1], blue]
        actions:@[@"onMaze",@"onMazeWar",@"onSpacewar",@"onMazeWar",@"onGames"]];

    // Multiplayer
    y = [self addButtonRow:panel y:y panelW:panelW
        titles:@[@"HOST",@"JOIN",@"DISC"]
        colors:@[[UIColor colorWithRed:0.8 green:0.8 blue:0 alpha:1],
                  [UIColor colorWithRed:0 green:0.8 blue:0.8 alpha:1],
                  [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:1]]
        actions:@[@"onHost",@"onJoin",@"onDisc"]];

    // Chat panel (hidden by default)
    self.panelChat = [[UIView alloc] initWithFrame:CGRectMake(4, y, panelW-8, 80)];
    self.panelChat.hidden = YES;
    [panel addSubview:self.panelChat];

    self.tvNetStatus = [self monoLabel:@"● OFFLINE" size:7 color:[UIColor colorWithRed:0.4 green:0 blue:0 alpha:1]];
    self.tvNetStatus.frame = CGRectMake(0, 0, panelW-8, 10);
    [self.panelChat addSubview:self.tvNetStatus];

    self.tvChatLog = [self monoLabel:@"" size:7 color:[UIColor colorWithRed:0 green:0.7 blue:0 alpha:1]];
    self.tvChatLog.frame = CGRectMake(0, 12, panelW-8, 44);
    self.tvChatLog.numberOfLines = 0;
    self.tvChatLog.backgroundColor = [UIColor colorWithWhite:0.02 alpha:1];
    [self.panelChat addSubview:self.tvChatLog];

    // Chat input
    UIView *chatRow = [[UIView alloc] initWithFrame:CGRectMake(0, 58, panelW-8, 20)];
    [self.panelChat addSubview:chatRow];
    self.etChat = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, panelW-50, 20)];
    self.etChat.backgroundColor = [UIColor colorWithWhite:0.05 alpha:1];
    self.etChat.textColor = [UIColor colorWithRed:0 green:0.8 blue:0.2 alpha:1];
    self.etChat.font = MonoFont(8);
    self.etChat.placeholder = @"chat...";
    self.etChat.returnKeyType = UIReturnKeySend;
    self.etChat.delegate = self;
    [chatRow addSubview:self.etChat];
    UIButton *btnSend = [UIButton buttonWithType:UIButtonTypeSystem];
    btnSend.frame = CGRectMake(panelW-50, 0, 40, 20);
    [btnSend setTitle:@"▶" forState:UIControlStateNormal];
    btnSend.tintColor = [UIColor colorWithRed:0 green:1 blue:0.3 alpha:1];
    btnSend.backgroundColor = [UIColor colorWithWhite:0.06 alpha:1];
    [btnSend addTarget:self action:@selector(sendChat) forControlEvents:UIControlEventTouchUpInside];
    [chatRow addSubview:btnSend];
    y += 86;

    // Divider
    UIView *div = [[UIView alloc] initWithFrame:CGRectMake(4, y, panelW-8, 1)];
    div.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1];
    [panel addSubview:div]; y += 5;

    // Toggle keyboard/controller
    UIButton *btnToggle = [self makeButton:@"⌨ KBD" textColor:[UIColor yellowColor] bgColor:[UIColor colorWithWhite:0.06 alpha:1]];
    btnToggle.frame = CGRectMake(4, y, panelW-8, 20);
    [btnToggle addTarget:self action:@selector(toggleInput) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:btnToggle]; y += 22;

    // Controller panel (dpad + action buttons)
    self.panelController = [self buildControllerPanelWithWidth:panelW atY:y];
    [panel addSubview:self.panelController]; y += self.panelController.bounds.size.height + 4;

    // Keyboard panel (hidden)
    self.panelKeyboard = [self buildKeyboardPanelWithWidth:panelW atY:y];
    self.panelKeyboard.hidden = YES;
    [panel addSubview:self.panelKeyboard]; y += self.panelKeyboard.bounds.size.height + 4;

    // Hint
    UILabel *hint = [self monoLabel:@"W=fwd S=back A/D=turn SPACE=fire" size:6 color:[UIColor colorWithWhite:0.3 alpha:1]];
    hint.frame = CGRectMake(4, y, panelW-8, 16);
    hint.numberOfLines = 2;
    [panel addSubview:hint]; y += 20;

    panel.contentSize = CGSizeMake(panelW, y+20);
}

#pragma mark - Controller panel

- (UIView *)buildControllerPanelWithWidth:(CGFloat)width atY:(CGFloat)atY {
    CGFloat h = 160;
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, atY, width, h)];

    CGFloat btnSz = 44;
    CGFloat cx = width/2 - btnSz/2;
    CGFloat cy = h/2 - btnSz/2;

    UIColor *dpadColor = [UIColor colorWithRed:0 green:0.8 blue:0.2 alpha:1];
    UIColor *bgColor = [UIColor colorWithWhite:0.08 alpha:1];

    self.btnUp = [self dpadButton:@"▲" x:cx y:cy-btnSz-4 sz:btnSz dir:0 textColor:dpadColor bgColor:bgColor container:container];
    self.btnDown = [self dpadButton:@"▼" x:cx y:cy+btnSz+4 sz:btnSz dir:1 textColor:dpadColor bgColor:bgColor container:container];
    self.btnLeft = [self dpadButton:@"◀" x:cx-btnSz-4 y:cy sz:btnSz dir:2 textColor:dpadColor bgColor:bgColor container:container];
    self.btnRight = [self dpadButton:@"▶" x:cx+btnSz+4 y:cy sz:btnSz dir:3 textColor:dpadColor bgColor:bgColor container:container];

    // B / Fire
    UIButton *btnB = [self makeButton:@"B" textColor:[UIColor colorWithRed:0 green:122.0/255 blue:255.0/255 alpha:1] bgColor:bgColor];
    btnB.frame = CGRectMake(width-btnSz*2-8, cy-20, btnSz, btnSz);
    btnB.layer.cornerRadius = btnSz/2;
    btnB.tag = 4;
    [btnB addTarget:self action:@selector(dpadDown:) forControlEvents:UIControlEventTouchDown];
    [btnB addTarget:self action:@selector(dpadUp:) forControlEvents:UIControlEventTouchUpInside];
    [btnB addTarget:self action:@selector(dpadUp:) forControlEvents:UIControlEventTouchUpOutside];
    [btnB addTarget:self action:@selector(dpadUp:) forControlEvents:UIControlEventTouchCancel];
    [container addSubview:btnB];

    // A / Fire
    UIButton *btnA = [self makeButton:@"A" textColor:[UIColor colorWithRed:255.0/255 green:204.0/255 blue:0 alpha:1] bgColor:bgColor];
    btnA.frame = CGRectMake(width-btnSz-4, cy-20, btnSz, btnSz);
    btnA.layer.cornerRadius = btnSz/2;
    btnA.tag = 5;
    [btnA addTarget:self action:@selector(dpadDown:) forControlEvents:UIControlEventTouchDown];
    [btnA addTarget:self action:@selector(dpadUp:) forControlEvents:UIControlEventTouchUpInside];
    [btnA addTarget:self action:@selector(dpadUp:) forControlEvents:UIControlEventTouchUpOutside];
    [btnA addTarget:self action:@selector(dpadUp:) forControlEvents:UIControlEventTouchCancel];
    [container addSubview:btnA];

    return container;
}

- (UIButton *)dpadButton:(NSString *)title x:(CGFloat)x y:(CGFloat)y sz:(CGFloat)sz dir:(NSInteger)dir
                textColor:(UIColor *)textColor bgColor:(UIColor *)bgColor container:(UIView *)container {
    UIButton *btn = [self makeButton:title textColor:textColor bgColor:bgColor];
    btn.frame = CGRectMake(x, y, sz, sz);
    btn.layer.cornerRadius = 8;
    btn.tag = dir;
    [btn addTarget:self action:@selector(dpadDown:) forControlEvents:UIControlEventTouchDown];
    [btn addTarget:self action:@selector(dpadDown:) forControlEvents:UIControlEventTouchDragEnter];
    [btn addTarget:self action:@selector(dpadUp:) forControlEvents:UIControlEventTouchUpInside];
    [btn addTarget:self action:@selector(dpadUp:) forControlEvents:UIControlEventTouchUpOutside];
    [btn addTarget:self action:@selector(dpadUp:) forControlEvents:UIControlEventTouchCancel];
    [container addSubview:btn];
    return btn;
}

#pragma mark - Keyboard panel

- (UIView *)buildKeyboardPanelWithWidth:(CGFloat)width atY:(CGFloat)atY {
    NSArray<NSString *> *rows = @[@"1234567890",@"QWERTYUIOP",@"ASDFGHJKL",@"ZXCVBNM"];
    CGFloat y = 0;
    CGFloat btnH = 22;
    UIView *container = [[UIView alloc] init];

    for (NSString *row in rows) {
        CGFloat rowW = width - 8;
        CGFloat btnW = rowW / (CGFloat)row.length;
        for (NSInteger i = 0; i < (NSInteger)row.length; i++) {
            NSString *chStr = [row substringWithRange:NSMakeRange(i, 1)];
            UIButton *btn = [self makeButton:chStr textColor:[UIColor colorWithRed:0 green:0.9 blue:0.3 alpha:1]
                                     bgColor:[UIColor colorWithWhite:0.05 alpha:1]];
            btn.frame = CGRectMake(4 + (CGFloat)i*btnW, y, btnW-1, btnH);
            btn.titleLabel.font = MonoFont(8);
            btn.layer.borderWidth = 0.5;
            btn.layer.borderColor = [UIColor colorWithWhite:0.2 alpha:1].CGColor;
            [btn addTarget:self action:@selector(kbdTap:) forControlEvents:UIControlEventTouchUpInside];
            btn.accessibilityLabel = chStr;
            [container addSubview:btn];
        }
        y += btnH + 2;
    }
    // Special keys
    NSArray *specials = @[
        @[@"SPC", @(4), @(y), @(width*0.35-5)],
        @[@"ENT", @(width*0.35), @(y), @(width*0.3-2)],
        @[@"BSP", @(width*0.65), @(y), @(width*0.35-12)],
        @[@"ESC", @(4), @(y+btnH+2), @(width-16)],
    ];
    for (NSArray *spec in specials) {
        NSString *title = spec[0];
        CGFloat x = [spec[1] doubleValue];
        CGFloat sy = [spec[2] doubleValue];
        CGFloat w = [spec[3] doubleValue];
        UIButton *btn = [self makeButton:title textColor:[UIColor colorWithRed:0 green:0.9 blue:0.3 alpha:1]
                                 bgColor:[UIColor colorWithWhite:0.05 alpha:1]];
        btn.frame = CGRectMake(x, sy, w, btnH);
        btn.titleLabel.font = MonoFont(7);
        btn.accessibilityLabel = title;
        [btn addTarget:self action:@selector(kbdTap:) forControlEvents:UIControlEventTouchUpInside];
        [container addSubview:btn];
    }
    container.frame = CGRectMake(0, atY, width, y+btnH*2+6);
    return container;
}

- (void)kbdTap:(UIButton *)sender {
    NSString *label = sender.accessibilityLabel ?: (sender.currentTitle ?: @"");
    NSInteger code = 0;
    if ([label isEqualToString:@"SPC"]) { code = 32; }
    else if ([label isEqualToString:@"ENT"]) { code = 13; }
    else if ([label isEqualToString:@"BSP"]) { code = 8; }
    else if ([label isEqualToString:@"ESC"]) { code = 27; }
    else {
        NSString *up = [label uppercaseString];
        code = up.length > 0 ? [up characterAtIndex:0] : 0;
    }
    self.machine.keyboard = code;
    __weak EmulatorViewController *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (weakSelf.machine.keyboard == code) { weakSelf.machine.keyboard = 0; }
    });
}

- (void)toggleInput {
    _keyboardVisible = !_keyboardVisible;
    self.panelKeyboard.hidden = !_keyboardVisible;
    self.panelController.hidden = _keyboardVisible;
}

#pragma mark - Dpad

- (void)dpadDown:(UIButton *)sender {
    sender.alpha = 0.45;
    NSInteger tag = sender.tag;
    __weak EmulatorViewController *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        EmulatorViewController *strongSelf = weakSelf;
        if (!strongSelf) return;
        switch (tag) {
            case 0: strongSelf.machine.keyboard = 'W'; break;
            case 1: strongSelf.machine.keyboard = 'S'; break;
            case 2: strongSelf.machine.keyboard = 'A'; break;
            case 3: strongSelf.machine.keyboard = 'D'; break;
            case 4: case 5: strongSelf.machine.keyboard = 32; break;
            default: break;
        }
    });
    MazeWarGame *mwg = [self.demos getMazeWarGame];
    if (mwg) {
        switch (tag) {
            case 0: mwg.iUp = YES; break;
            case 1: mwg.iDown = YES; break;
            case 2: mwg.iLeft = YES; break;
            case 3: mwg.iRight = YES; break;
            case 4: case 5: mwg.iFire = YES; break;
            default: break;
        }
    }
}

- (void)dpadUp:(UIButton *)sender {
    sender.alpha = 1.0;
    self.machine.keyboard = 0;
    MazeWarGame *mwg = [self.demos getMazeWarGame];
    if (mwg) {
        switch (sender.tag) {
            case 0: mwg.iUp = NO; break;
            case 1: mwg.iDown = NO; break;
            case 2: mwg.iLeft = NO; break;
            case 3: mwg.iRight = NO; break;
            case 4: case 5: mwg.iFire = NO; break;
            default: break;
        }
    }
}

#pragma mark - MP thread

- (void)mpThreadMain {
    __weak EmulatorViewController *weakSelf = self;
    while (YES) {
        __strong EmulatorViewController *strongSelf = weakSelf;
        if (!strongSelf || !strongSelf->_mpRunning) break;
        if (strongSelf.machine.mp_run) {
            for (int i = 0; i < 200; i++) { [strongSelf.machine mpStep]; }
            for (int i = 0; i < 50; i++) { [strongSelf.machine dpStep]; }
        }
        strongSelf = nil;
        [NSThread sleepForTimeInterval:0.001];
    }
}

- (void)startMP {
    _mpRunning = YES;
    NSThread *t = [[NSThread alloc] initWithTarget:self selector:@selector(mpThreadMain) object:nil];
    t.name = @"mp-thread";
    [t start];
}

#pragma mark - FPS ticker

- (void)fpsTick:(NSTimer *)timer {
    float fps = self.crtView.actualFps;
    NSInteger target = self.crtView.maxFps;
    self.tvFps.text = [NSString stringWithFormat:@"%d/%ldfps", (int)fps, (long)target];
    self.tvPc.text = [NSString stringWithFormat:@"PC:%04lX  AC:%04lX", (long)self.machine.mp_pc, (long)self.machine.mp_ac];
    self.tvAc.text = [NSString stringWithFormat:@"IR:%04lX  L:%ld", (long)self.machine.mp_ir, (long)self.machine.mp_link];
}

- (void)startFpsTicker {
    self.fpsTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
                                                       target:self
                                                     selector:@selector(fpsTick:)
                                                     userInfo:nil
                                                      repeats:YES];
}

#pragma mark - Demo buttons

- (void)onStar     { self.demos.current = DemoTypeStar; }
- (void)onScope    { self.demos.current = DemoTypeScope; }
- (void)onLiss     { self.demos.current = DemoTypeLissajous; }
- (void)onText     { self.demos.current = DemoTypeText; }
- (void)onBounce   { self.demos.current = DemoTypeBounce; }
- (void)onMaze     { self.demos.current = DemoTypeMaze; }
- (void)onSpacewar { self.demos.current = DemoTypeSpacewar; }
- (void)onGames    { self.demos.current = DemoTypeLines; }
- (void)onMazeWar {
    [self.demos initMazeWar];
    self.demos.current = DemoTypeMazeWar;
    [[self.demos getMazeWarGame] startSinglePlayer];
}

#pragma mark - Machine buttons

- (void)onPwr { [self.machine powerOn]; }
- (void)onRst { [self.machine reset]; }
- (void)onRun { self.machine.mp_halt = NO; self.machine.mp_run = YES; }
- (void)onHlt { self.machine.mp_halt = YES; self.machine.mp_run = NO; }
- (void)onStp { [self.machine mpStep]; }

#pragma mark - Multiplayer

- (void)onHost {
    [self.netSession stop];
    self.netSession = [[NetSession alloc] init];
    self.netSession.chatListener = self;
    self.netSession.eventListener = self;
    NSInteger seed = 1 + (NSInteger)arc4random_uniform(UINT32_MAX - 1);
    [self.demos initMazeWar];
    [[self.demos getMazeWarGame] hostMulti:self.netSession];
    self.demos.current = DemoTypeMazeWar;
    [self.netSession host:seed];
    [self setNetStatus:@"⚡ HOSTING — waiting for guest..."];
    [self showChatPanel:YES];
    [self addChat:[NSString stringWithFormat:@"SYS: hosting on port %ld", (long)[NetSession PORT_GAME]]];
    [self showToast:@"Hosting — waiting for guest"];
}

- (void)onJoin {
    [self.netSession stop];
    self.netSession = [[NetSession alloc] init];
    self.netSession.chatListener = self;
    self.netSession.eventListener = self;
    [self.demos initMazeWar];
    [[self.demos getMazeWarGame] joinMulti:self.netSession];
    self.demos.current = DemoTypeMazeWar;
    [self.netSession discover];
    [self setNetStatus:@"🔍 SEARCHING for host..."];
    [self showChatPanel:YES];
    [self addChat:@"SYS: searching..."];
    [self showToast:@"Searching for host..."];
}

- (void)onDisc {
    [self.netSession stop];
    self.netSession = nil;
    [[self.demos getMazeWarGame] stopNet];
    [self setNetStatus:@"● OFFLINE"];
    [self showChatPanel:NO];
    [self addChat:@"SYS: disconnected"];
}

#pragma mark - Chat

- (void)sendChat {
    NSString *text = [self.etChat.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (text.length == 0) return;
    if (self.netSession && [self.netSession isConnected]) { [self.netSession sendChat:text]; }
    else { [self addChat:@"SYS: not connected"]; }
    self.etChat.text = @"";
}

- (void)addChat:(NSString *)line {
    [_chatLines addObject:line];
    if (_chatLines.count > 6) { [_chatLines removeObjectAtIndex:0]; }
    self.tvChatLog.text = [_chatLines componentsJoinedByString:@"\n"];
}

- (void)setNetStatus:(NSString *)s { self.tvNetStatus.text = s; }

- (void)showChatPanel:(BOOL)show { self.panelChat.hidden = !show; }

#pragma mark - Helpers

- (CGFloat)addButtonRow:(UIView *)parent y:(CGFloat)y panelW:(CGFloat)panelW
                  titles:(NSArray<NSString *> *)titles colors:(NSArray<UIColor *> *)colors
                 actions:(NSArray<NSString *> *)actions {
    CGFloat btnH = 24;
    CGFloat btnW = (panelW - 8) / (CGFloat)titles.count;
    for (NSInteger i = 0; i < (NSInteger)titles.count; i++) {
        UIButton *btn = [self makeButton:titles[i] textColor:colors[i] bgColor:[UIColor colorWithWhite:0.05 alpha:1]];
        btn.frame = CGRectMake(4 + (CGFloat)i*btnW, y, btnW-1, btnH);
        [btn addTarget:self action:NSSelectorFromString(actions[i]) forControlEvents:UIControlEventTouchUpInside];
        [parent addSubview:btn];
    }
    return y + btnH + 3;
}

- (UIButton *)makeButton:(NSString *)title textColor:(UIColor *)textColor bgColor:(UIColor *)bgColor {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitle:title forState:UIControlStateNormal];
    [btn setTitleColor:textColor forState:UIControlStateNormal];
    btn.backgroundColor = bgColor;
    btn.titleLabel.font = MonoFont(8);
    btn.layer.cornerRadius = 3;
    return btn;
}

- (UILabel *)monoLabel:(NSString *)text size:(CGFloat)size color:(UIColor *)color {
    UILabel *lbl = [[UILabel alloc] init];
    lbl.text = text;
    lbl.textColor = color;
    lbl.font = MonoFont(size);
    lbl.adjustsFontSizeToFitWidth = YES;
    return lbl;
}

- (void)showToast:(NSString *)msg {
    UILabel *toast = [[UILabel alloc] init];
    toast.text = msg;
    toast.textColor = [UIColor whiteColor];
    toast.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.9];
    toast.font = MonoFont(12);
    toast.textAlignment = NSTextAlignmentCenter;
    toast.layer.cornerRadius = 8;
    toast.clipsToBounds = YES;
    toast.frame = CGRectMake(20, self.view.bounds.size.height-80, self.view.bounds.size.width-40, 36);
    [self.view addSubview:toast];
    [UIView animateWithDuration:0.3 delay:2 options:0 animations:^{
        toast.alpha = 0;
    } completion:^(BOOL finished) {
        [toast removeFromSuperview];
    }];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self sendChat];
    return YES;
}

#pragma mark - NetSessionEventListener / NetSessionChatListener

- (void)onConnectedAsHost:(BOOL)asHost seed:(NSInteger)seed {
    [self setNetStatus:asHost ? @"✓ HOST connected" : @"✓ GUEST connected"];
    [self addChat:[NSString stringWithFormat:@"SYS: connected! %@", asHost ? @"you=HOST" : @"you=GUEST"]];
}

- (void)onPeerSyncDemoIdx:(NSInteger)demoIdx keyboard:(NSInteger)keyboard {
    if (demoIdx != _lastPeerDemo) {
        _lastPeerDemo = demoIdx;
        [self addChat:[NSString stringWithFormat:@"OPP demo: %ld", (long)demoIdx]];
    }
}

- (void)onPeerMazeStateX:(NSInteger)x y:(NSInteger)y dir:(NSInteger)dir hp:(NSInteger)hp score:(NSInteger)score {}
- (void)onPeerBulletDir:(NSInteger)dir {}
- (void)onPeerKilled {}

- (void)onDisconnected {
    [self setNetStatus:@"✕ DISCONNECTED"];
    [self addChat:@"SYS: peer disconnected"];
    [self showToast:@"Peer disconnected"];
}

- (void)onChatMessageFrom:(NSString *)from msg:(NSString *)msg {
    [self addChat:[NSString stringWithFormat:@"%@: %@", from, msg]];
}

@end
