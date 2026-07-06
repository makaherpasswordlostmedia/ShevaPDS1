// Machine.h — Imlac PDS-1 emulator core
#import <Foundation/Foundation.h>

#define MACHINE_MEM_SIZE  4096
#define MACHINE_WORD_MASK 0xFFFF
#define MACHINE_ADDR_MASK 0x0FFF
#define MACHINE_MAX_VEC   32768

typedef struct {
    NSInteger x1, y1, x2, y2;
    BOOL isPoint;
    float bright; // 0..1
} MachineVec;

@interface Machine : NSObject

// ── MP registers ──────────────────────────────────────────
@property (nonatomic) NSInteger mp_pc;
@property (nonatomic) NSInteger mp_ac;
@property (nonatomic) NSInteger mp_ir;
@property (nonatomic) NSInteger mp_link;
@property (nonatomic) BOOL mp_halt;
@property (nonatomic) BOOL mp_run;

// ── DP registers ──────────────────────────────────────────
@property (nonatomic) NSInteger dp_pc;
@property (nonatomic) NSInteger dp_ac;
@property (nonatomic) NSInteger dp_x;
@property (nonatomic) NSInteger dp_y;
@property (nonatomic) BOOL dp_halt;
@property (nonatomic) BOOL dp_enabled;
@property (nonatomic) NSInteger dp_intensity;
@property (nonatomic) float dp_scale;

// ── Memory ────────────────────────────────────────────────
// mem[MACHINE_MEM_SIZE], exposed as a raw pointer for fast access.
@property (nonatomic, readonly) NSInteger *mem;

// ── I/O ───────────────────────────────────────────────────
@property (nonatomic) NSInteger keyboard;
@property (nonatomic) NSInteger lpen_x;
@property (nonatomic) NSInteger lpen_y;
@property (nonatomic) BOOL lpen_hit;

// ── Display list ──────────────────────────────────────────
// vecs[MACHINE_MAX_VEC]
@property (nonatomic, readonly) MachineVec *vecs;
@property (nonatomic) NSInteger nvec;

// ── Console ───────────────────────────────────────────────
@property (nonatomic, strong) NSMutableString *console;
@property (nonatomic) NSInteger cycles;

- (void)reset;
- (void)powerOn;

- (void)dlLine:(NSInteger)x1 y1:(NSInteger)y1 x2:(NSInteger)x2 y2:(NSInteger)y2 bright:(float)bright;
- (void)dlPoint:(NSInteger)x y:(NSInteger)y bright:(float)bright;
- (void)dlClear;

- (void)mpStep;
- (void)dpStep;

// Returns number of words emitted.
- (NSInteger)assemble:(NSString *)src;

@end
