// Machine.m — Imlac PDS-1 emulator core
// Ported from Machine.swift (originally Machine.java)
#import "Machine.h"

@interface Machine () {
    NSInteger _memBuf[MACHINE_MEM_SIZE];
    MachineVec _vecsBuf[MACHINE_MAX_VEC];
    NSInteger _dp_ret_stack[16];
    NSInteger _dp_ret_top;
    NSMutableDictionary<NSString *, NSNumber *> *_asmLabels;
}
@end

@implementation Machine

- (instancetype)init {
    self = [super init];
    if (self) {
        _dp_pc = 0x100;
        _dp_x = 512;
        _dp_y = 512;
        _dp_enabled = YES;
        _dp_intensity = 7;
        _dp_scale = 1.0f;
        _mp_halt = YES;
        _console = [NSMutableString string];
        memset(_memBuf, 0, sizeof(_memBuf));
        memset(_vecsBuf, 0, sizeof(_vecsBuf));
    }
    return self;
}

- (NSInteger *)mem { return _memBuf; }
- (MachineVec *)vecs { return _vecsBuf; }

#pragma mark - Reset

- (void)reset {
    _mp_pc = 0; _mp_ac = 0; _mp_ir = 0; _mp_link = 0;
    _mp_halt = YES; _mp_run = NO;
    _dp_pc = 0x100; _dp_ac = 0; _dp_x = 512; _dp_y = 512;
    _dp_halt = NO; _dp_enabled = YES; _dp_intensity = 7; _dp_scale = 1;
    _dp_ret_top = 0; _keyboard = 0; _cycles = 0; _nvec = 0;
}

- (void)powerOn {
    [self reset];
    _mp_halt = NO;
    _mp_run = YES;
}

#pragma mark - Display list

- (void)dlLine:(NSInteger)x1 y1:(NSInteger)y1 x2:(NSInteger)x2 y2:(NSInteger)y2 bright:(float)bright {
    if (_nvec >= MACHINE_MAX_VEC) return;
    _vecsBuf[_nvec] = (MachineVec){ .x1=x1, .y1=y1, .x2=x2, .y2=y2, .isPoint=NO, .bright=bright };
    _nvec += 1;
}

- (void)dlPoint:(NSInteger)x y:(NSInteger)y bright:(float)bright {
    if (_nvec >= MACHINE_MAX_VEC) return;
    _vecsBuf[_nvec] = (MachineVec){ .x1=x, .y1=y, .x2=0, .y2=0, .isPoint=YES, .bright=bright };
    _nvec += 1;
}

- (void)dlClear { _nvec = 0; }

#pragma mark - Main processor

- (void)mpStep {
    if (_mp_halt) return;
    NSInteger word = _memBuf[_mp_pc & MACHINE_ADDR_MASK] & MACHINE_WORD_MASK;
    _mp_ir = word;
    _mp_pc = (_mp_pc + 1) & MACHINE_ADDR_MASK;
    _cycles += 1;

    NSInteger op  = (word >> 12) & 0xF;
    NSInteger ind = (word >> 11) & 0x1;
    NSInteger ea  =  word & MACHINE_ADDR_MASK;
    if (ind != 0) { ea = _memBuf[ea] & MACHINE_ADDR_MASK; }

    switch (op) {
        case 0x0: break;
        case 0x1:
            if (ind != 0) { _mp_ac = (-(word & 0x7FF)) & MACHINE_WORD_MASK; }
            else          { _mp_ac =  (word & 0x7FF); }
            break;
        case 0x2: _mp_pc = ea; break;
        case 0x3: _memBuf[ea] = _mp_ac; break;
        case 0x4: {
            NSInteger t = _memBuf[ea]; _memBuf[ea] = _mp_ac; _mp_ac = t;
            break;
        }
        case 0x5:
            _memBuf[ea] = (_memBuf[ea] + 1) & MACHINE_WORD_MASK;
            if ((_memBuf[ea] & 0x8000) == 0) { _mp_pc = (_mp_pc + 1) & MACHINE_ADDR_MASK; }
            break;
        case 0x6: {
            NSInteger s = _mp_ac + _memBuf[ea];
            _mp_link = (s >> 16) & 1; _mp_ac = s & MACHINE_WORD_MASK;
            break;
        }
        case 0x7: _mp_ac &= _memBuf[ea]; break;
        case 0x8: _mp_ac = _memBuf[ea] & MACHINE_WORD_MASK; break;
        case 0x9: _memBuf[ea] = _mp_pc; _mp_pc = (ea + 1) & MACHINE_ADDR_MASK; break;
        case 0xA: [self mpSkip:word]; break;
        case 0xB: _mp_ac |= _memBuf[ea]; _mp_ac &= MACHINE_WORD_MASK; break;
        case 0xC: {
            NSInteger n = word & 0xFF; if (n == 0) n = 1;
            for (NSInteger i = 0; i < n; i++) {
                NSInteger b = (_mp_ac >> 15) & 1;
                _mp_ac = ((_mp_ac << 1) | _mp_link) & MACHINE_WORD_MASK; _mp_link = b;
            }
            break;
        }
        case 0xD: {
            NSInteger n = word & 0xFF; if (n == 0) n = 1;
            for (NSInteger i = 0; i < n; i++) {
                NSInteger b = _mp_ac & 1;
                _mp_ac = ((_mp_ac >> 1) | (_mp_link << 15)) & MACHINE_WORD_MASK; _mp_link = b;
            }
            break;
        }
        case 0xE: [self mpIOT:word]; break;
        case 0xF: [self mpOPR:word]; break;
        default: break;
    }
}

- (void)mpSkip:(NSInteger)word {
    NSInteger inv  = (word >> 5) & 1;
    NSInteger cond =  word & 0x1F;
    BOOL skip = NO;
    if (cond & 0x01) { skip = skip || (_mp_ac == 0); }
    if (cond & 0x02) { skip = skip || ((_mp_ac & 0x8000) == 0); }
    if (cond & 0x04) { skip = skip || (_mp_link == 0); }
    if (cond & 0x08) { skip = skip || (_keyboard != 0); }
    if (cond & 0x10) { skip = skip || _dp_halt; }
    if (inv) { skip = !skip; }
    if (skip) { _mp_pc = (_mp_pc + 1) & MACHINE_ADDR_MASK; }
}

- (void)mpOPR:(NSInteger)word {
    if (word & 0x800) {
        _mp_halt = YES; _mp_run = NO;
        [_console appendFormat:@"[HALT PC=%lX AC=%lX]\n", (long)_mp_pc, (long)_mp_ac];
        return;
    }
    if (word & 0x400) { _mp_ac = 0; }
    if (word & 0x200) { _mp_link = 0; }
    if (word & 0x100) { _mp_ac = (~_mp_ac) & MACHINE_WORD_MASK; }
    if (word & 0x080) { _mp_link ^= 1; }
    if (word & 0x040) { NSInteger s = _mp_ac + 1; _mp_link = (s >> 16) & 1; _mp_ac = s & MACHINE_WORD_MASK; }
    if (word & 0x020) { _mp_link = 1; }
    if (word & 0x010) { NSInteger t = _mp_ac; _mp_ac = _dp_ac; _dp_ac = t; }
    if (word & 0x008) { NSInteger b = (_mp_ac >> 15) & 1; _mp_ac = ((_mp_ac << 1) | _mp_link) & MACHINE_WORD_MASK; _mp_link = b; }
    if (word & 0x004) { NSInteger b = _mp_ac & 1; _mp_ac = ((_mp_ac >> 1) | (_mp_link << 15)) & MACHINE_WORD_MASK; _mp_link = b; }
}

- (void)mpIOT:(NSInteger)word {
    NSInteger dev = (word >> 6) & 0x3F;
    NSInteger fn  =  word       & 0x3F;
    switch (dev) {
        case 0x01:
            if (fn & 1) { _mp_ac = _keyboard & MACHINE_WORD_MASK; }
            if (fn & 2) { _keyboard = 0; }
            if ((fn & 4) && _keyboard != 0) { _mp_pc = (_mp_pc + 1) & MACHINE_ADDR_MASK; }
            break;
        case 0x02:
            if (fn & 1) { _dp_enabled = !_dp_enabled; }
            if (fn & 2) { _dp_halt = NO; _dp_pc = _mp_ac & MACHINE_ADDR_MASK; }
            if (fn & 4) { _dp_halt = YES; }
            break;
        case 0x04: {
            unichar c = (unichar)(_mp_ac & 0x7F);
            if (c >= 32 || c == '\n') { [_console appendFormat:@"%C", c]; }
            break;
        }
        case 0x10:
            if (fn & 1) { _mp_ac = _lpen_x; }
            if (fn & 2) { _mp_ac = _lpen_y; }
            if ((fn & 4) && _lpen_hit) { _mp_pc = (_mp_pc + 1) & MACHINE_ADDR_MASK; }
            break;
        case 0x20: _mp_ac = _cycles & MACHINE_WORD_MASK; break;
        default: break;
    }
}

#pragma mark - Display processor

- (void)dpStep {
    if (!(_dp_enabled && !_dp_halt)) return;
    NSInteger word = _memBuf[_dp_pc & MACHINE_ADDR_MASK] & MACHINE_WORD_MASK;
    _dp_pc = (_dp_pc + 1) & MACHINE_ADDR_MASK;
    NSInteger op   = (word >> 12) & 0xF;
    NSInteger addr =  word & MACHINE_ADDR_MASK;
    float bright = MAX((float)_dp_intensity / 7.0f, 0.05f);

    switch (op) {
        case 0x0:
            if ((word & 0x0E00) == 0x0E00) { _dp_intensity = word & 0x7; }
            break;
        case 0x1: _dp_x = addr; break;
        case 0x2: _dp_y = addr; break;
        case 0x3: {
            NSInteger dx = (word >> 6) & 0x1F; NSInteger dy = word & 0x1F;
            if (word & 0x0800) { dx = -dx; }
            if (word & 0x0020) { dy = -dy; }
            NSInteger nx = (_dp_x + dx) & 1023; NSInteger ny = (_dp_y + dy) & 1023;
            [self dlLine:_dp_x y1:_dp_y x2:nx y2:ny bright:bright];
            _dp_x = nx; _dp_y = ny;
            break;
        }
        case 0x4: {
            NSInteger dx = ((word >> 6) & 0x3F) * 8; NSInteger dy = (word & 0x3F) * 8;
            if (word & 0x0800) { dx = -dx; }
            if (word & 0x0020) { dy = -dy; }
            NSInteger nx = (_dp_x + dx) & 1023; NSInteger ny = (_dp_y + dy) & 1023;
            [self dlLine:_dp_x y1:_dp_y x2:nx y2:ny bright:bright];
            _dp_x = nx; _dp_y = ny;
            break;
        }
        case 0x5: _dp_pc = addr; break;
        case 0x6:
            if (_dp_ret_top < 15) { _dp_ret_stack[_dp_ret_top] = _dp_pc; _dp_ret_top += 1; }
            _dp_pc = addr;
            break;
        case 0x7:
            if (word & 0x0800) { [self dlPoint:_dp_x y:_dp_y bright:bright]; }
            else if (word & 0x0010) { _dp_intensity = word & 0x7; }
            break;
        case 0x8:
            if ((word & 0x0800) && _dp_ret_top > 0) { _dp_ret_top -= 1; _dp_pc = _dp_ret_stack[_dp_ret_top]; }
            else { _dp_halt = YES; }
            break;
        case 0x9: _dp_intensity = word & 0x7; break;
        case 0xA: {
            NSInteger sf = word & 0x3;
            static const float sc[4] = {0.25f, 0.5f, 1.0f, 2.0f};
            _dp_scale = sc[sf];
            break;
        }
        case 0xB:
            if (_dp_ret_top > 0) { _dp_ret_top -= 1; _dp_pc = _dp_ret_stack[_dp_ret_top]; }
            else { _dp_halt = YES; }
            break;
        case 0xC: _dp_x = addr; break;
        case 0xD: _dp_y = addr; break;
        case 0xE: _dp_x = (word >> 6) & 0x1F; _dp_y = word & 0x1F; break;
        case 0xF: _dp_halt = YES; break;
        default: break;
    }
}

#pragma mark - Assembler

- (NSArray<NSString *> *)mnemNames {
    return @[@"LAW",@"JMP",@"DAC",@"XAM",@"ISP",@"ADD",@"AND",@"LDA",@"JMS",@"IOR",
        @"RAL",@"RAR",@"IOT",@"HLT",@"CLA",@"CLL",@"CMA",@"CML",@"IAC",@"STL",@"SAM",@"NOP",
        @"SKZ",@"SKP",@"SKL",@"SKK",@"SKD",@"DLXA",@"DLYA",@"DSVH",@"DLVH",@"DJMP",@"DJMS",
        @"DPTS",@"DHLT",@"DRJM",@"DEIM",@"DVSF",@"RAL1",@"RAR1"];
}

- (NSArray<NSNumber *> *)mnemOpc {
    return @[@0x1000,@0x2000,@0x3000,@0x4000,@0x5000,@0x6000,@0x7000,@0x8000,@0x9000,@0xB000,
        @0xC000,@0xD000,@0xE000,@0xF800,@0xF400,@0xF200,@0xF100,@0xF080,@0xF040,@0xF020,@0xF010,@0xF000,
        @0xA001,@0xA002,@0xA004,@0xA008,@0xA010,@0x1000,@0x2000,@0x3000,@0x4000,@0x5000,@0x6000,
        @0x7800,@0x8000,@0xB000,@0x9000,@0xA000,@0xC001,@0xD001];
}

- (NSArray<NSNumber *> *)mnemHasAddr {
    return @[@YES,@YES,@YES,@YES,@YES,@YES,@YES,@YES,@YES,@YES,
        @YES,@YES,@YES,@NO,@NO,@NO,@NO,@NO,@NO,@NO,@NO,@NO,
        @NO,@NO,@NO,@NO,@NO,@YES,@YES,@YES,@YES,@YES,@YES,
        @NO,@NO,@NO,@YES,@YES,@NO,@NO];
}

- (NSInteger)asmParseVal:(NSString *)tok {
    NSString *t = [tok stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([t hasPrefix:@"0x"] || [t hasPrefix:@"0X"]) {
        NSString *hex = [t substringFromIndex:2];
        unsigned int result = 0;
        [[NSScanner scannerWithString:hex] scanHexInt:&result];
        return (NSInteger)result;
    }
    NSNumber *lv = _asmLabels[[t uppercaseString]];
    if (lv != nil) { return [lv integerValue]; }
    return [t integerValue];
}

- (NSInteger)assemble:(NSString *)src {
    _asmLabels = [NSMutableDictionary dictionary];
    NSArray<NSString *> *lines = [src componentsSeparatedByString:@"\n"];
    NSInteger baseAddr = 0x050;

    NSArray<NSString *> *mnemNames = [self mnemNames];
    NSArray<NSNumber *> *mnemOpc = [self mnemOpc];
    NSArray<NSNumber *> *mnemHasAddr = [self mnemHasAddr];

    NSCharacterSet *ws = [NSCharacterSet whitespaceCharacterSet];

    // Pass 1: labels
    NSInteger addr = baseAddr;
    for (NSString *rawLine in lines) {
        NSString *line = [[rawLine componentsSeparatedByString:@";"] firstObject];
        line = [line stringByTrimmingCharactersInSet:ws];
        if (line.length == 0) continue;
        NSMutableArray<NSString *> *tok = [[line componentsSeparatedByCharactersInSet:ws] mutableCopy];
        [tok removeObject:@""];
        if (tok.count == 0) continue;
        NSString *up = [tok[0] uppercaseString];
        if ([up isEqualToString:@".ORG"] || [up isEqualToString:@"ORG"]) {
            if (tok.count > 1) { addr = [self asmParseVal:tok[1]]; }
            continue;
        }
        if ([up isEqualToString:@".DP"] || [up isEqualToString:@".MP"]) continue;
        if ([tok[0] hasSuffix:@":"]) {
            NSString *lbl = [[tok[0] substringToIndex:tok[0].length - 1] uppercaseString];
            _asmLabels[lbl] = @(addr);
            [tok removeObjectAtIndex:0];
            if (tok.count == 0) continue;
        }
        NSString *first = [tok[0] uppercaseString];
        if ([first isEqualToString:@".WORD"] || [first isEqualToString:@"DATA"]) {
            addr += tok.count - 1;
            continue;
        }
        addr += 1;
    }

    // Pass 2: emit
    NSCharacterSet *sepSet = [NSCharacterSet characterSetWithCharactersInString:@" \t,"];
    addr = baseAddr;
    for (NSString *rawLine in lines) {
        NSString *line = [[rawLine componentsSeparatedByString:@";"] firstObject];
        line = [line stringByTrimmingCharactersInSet:ws];
        if (line.length == 0) continue;
        NSMutableArray<NSString *> *tok = [[line componentsSeparatedByCharactersInSet:sepSet] mutableCopy];
        [tok removeObject:@""];
        if (tok.count == 0) continue;
        NSString *up0 = [tok[0] uppercaseString];
        if ([up0 isEqualToString:@".ORG"] || [up0 isEqualToString:@"ORG"]) {
            if (tok.count > 1) { addr = [self asmParseVal:tok[1]]; }
            continue;
        }
        if ([up0 isEqualToString:@".DP"] || [up0 isEqualToString:@".MP"]) continue;
        if ([tok[0] hasSuffix:@":"]) {
            [tok removeObjectAtIndex:0];
            if (tok.count == 0) continue;
        }
        NSString *mnUp = [tok[0] uppercaseString];
        if ([mnUp isEqualToString:@".WORD"] || [mnUp isEqualToString:@"DATA"]) {
            for (NSInteger i = 1; i < (NSInteger)tok.count; i++) {
                if (addr < MACHINE_MEM_SIZE) { _memBuf[addr] = [self asmParseVal:tok[i]]; addr += 1; }
            }
            continue;
        }
        NSInteger mi = [mnemNames indexOfObject:mnUp];
        if (mi == NSNotFound) continue;
        NSInteger word = [mnemOpc[mi] integerValue];
        if ([mnemHasAddr[mi] boolValue] && tok.count > 1) {
            NSInteger val = [self asmParseVal:tok[1]];
            if ((word & 0xF000) == 0x1000) { word |= (val & 0x7FF); }
            else { word |= (val & MACHINE_ADDR_MASK); }
        }
        if (addr < MACHINE_MEM_SIZE) { _memBuf[addr] = word; addr += 1; }
    }
    return addr - baseAddr;
}

@end
