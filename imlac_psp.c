/* Imlac PDS-1 for PSP - single-file build. psp-gcc -O2 -G0 ... see bottom for Makefile */

#include <stdint.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <ctype.h>
#include <math.h>
#include <time.h>

/* machine.h - Imlac PDS-1 emulator core (portable C, ported from Machine.m) */

#include <stdint.h>

#define MACHINE_MEM_SIZE  4096
#define MACHINE_WORD_MASK 0xFFFF
#define MACHINE_ADDR_MASK 0x0FFF
#define MACHINE_MAX_VEC   32768

typedef struct {
    int x1, y1, x2, y2;
    int isPoint;
    float bright; /* 0..1 */
} MachineVec;

typedef struct Machine {
    /* MP registers */
    int mp_pc, mp_ac, mp_ir, mp_link;
    int mp_halt, mp_run;
    /* DP registers */
    int dp_pc, dp_ac, dp_x, dp_y;
    int dp_halt, dp_enabled, dp_intensity;
    float dp_scale;
    /* memory */
    int mem[MACHINE_MEM_SIZE];
    /* I/O */
    int keyboard;
    int lpen_x, lpen_y, lpen_hit;
    /* display list */
    MachineVec vecs[MACHINE_MAX_VEC];
    int nvec;
    /* console (last bytes written by the MP) */
    char console[512];
    int console_len;
    int cycles;
    /* internals */
    int dp_ret_stack[16];
    int dp_ret_top;
} Machine;

void machine_init(Machine *m);
void machine_reset(Machine *m);
void machine_power_on(Machine *m);

void machine_dl_line(Machine *m, int x1, int y1, int x2, int y2, float bright);
void machine_dl_point(Machine *m, int x, int y, float bright);
void machine_dl_clear(Machine *m);

void machine_mp_step(Machine *m);
void machine_dp_step(Machine *m);

/* Returns number of words emitted. */
int machine_assemble(Machine *m, const char *src);

/* Tiny PRNG shared by the demos / game (replaces arc4random). */
void     pds_srand(uint32_t seed);
uint32_t pds_rand(void);
uint32_t pds_rand_uniform(uint32_t n);


/* font.h - 5x5 vector font drawn into the Machine display list */

void font_char(Machine *m, int c, int ox, int oy, float sc, float b);
void font_text(Machine *m, const char *s, int ox, int oy, float sc, float b);

/* mazewar.h - Maze War (1974), single-player port of MazeWarGame.m */

#define MZ 16
#define MW_MAX_ENEMIES 16
#define MW_MAX_BULLETS 64

typedef struct { int x, y, dir, think, fireCd, alive; } MwEnemy;
typedef struct { double x, y; int dir, life, fromPlayer, alive; } MwBullet;

typedef enum { MW_TITLE, MW_PLAY, MW_DEAD } MwState;

typedef struct MazeWar {
    Machine *M;
    int maze[MZ * MZ];
    int px, py, pdir, hp, score, level;
    int moveCd, turnCd, fireCd, hitFlash, killFlash;
    MwEnemy enemies[MW_MAX_ENEMIES];
    int nEnemies;
    MwBullet bullets[MW_MAX_BULLETS];
    int nBullets;
    MwState state;
    int frame;
    char msg[48];
    int msgT;
    /* input flags - set true by the UI layer before calling tick */
    int iUp, iDown, iLeft, iRight, iFire;
    int pUp, pDown, pLeft, pRight, pFire;
} MazeWar;

void mazewar_init(MazeWar *g, Machine *m);
void mazewar_tick(MazeWar *g);
void mazewar_draw(MazeWar *g);
void mazewar_start_single(MazeWar *g);


/* demos.h - built-in demo programs (ported from Demos.m) */

typedef enum {
    DEMO_LINES = 0, DEMO_STAR, DEMO_LISSAJOUS, DEMO_TEXT, DEMO_BOUNCE,
    DEMO_MAZE, DEMO_SPACEWAR, DEMO_SCOPE, DEMO_USERASM, DEMO_MAZEWAR,
    DEMO_COUNT
} DemoType;

#define DEMO_MW 18
#define DEMO_MH 14

typedef struct Demos {
    Machine *M;
    DemoType current;
    int frame;
    double angle, t;

    double ballX, ballY, ballVx, ballVy;
    double trailX[16], trailY[16];
    int trailN;

    int mazeGrid[DEMO_MH][DEMO_MW];
    int mazeReady;

    double sw1x, sw1y, sw1a, sw1vx, sw1vy;
    double sw2x, sw2y, sw2a, sw2vx, sw2vy;
    double bx[4], by[4], bvx[4], bvy[4];
    int blife[4];
    int swInit;
    double textScroll;

    MazeWar mazeWar;
} Demos;

void demos_init(Demos *d, Machine *m);
void demos_set(Demos *d, DemoType t);   /* switches demo, (re)starts Maze War if needed */
void demos_run(Demos *d);               /* run one frame of the current demo */
const char *demos_name(DemoType t);


/* machine.c - Imlac PDS-1 emulator core (ported from Machine.m) */
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <ctype.h>
#include <math.h>

/* ---- PRNG (xorshift32) ---- */
static uint32_t g_rng = 0x2545F491u;
void pds_srand(uint32_t seed) { g_rng = seed ? seed : 0x2545F491u; }
uint32_t pds_rand(void) {
    uint32_t x = g_rng;
    x ^= x << 13; x ^= x >> 17; x ^= x << 5;
    return g_rng = x;
}
uint32_t pds_rand_uniform(uint32_t n) { return n ? pds_rand() % n : 0; }

/* ---- lifecycle ---- */
void machine_init(Machine *m) {
    memset(m, 0, sizeof(*m));
    m->dp_pc = 0x100;
    m->dp_x = 512;
    m->dp_y = 512;
    m->dp_enabled = 1;
    m->dp_intensity = 7;
    m->dp_scale = 1.0f;
    m->mp_halt = 1;
}

void machine_reset(Machine *m) {
    m->mp_pc = 0; m->mp_ac = 0; m->mp_ir = 0; m->mp_link = 0;
    m->mp_halt = 1; m->mp_run = 0;
    m->dp_pc = 0x100; m->dp_ac = 0; m->dp_x = 512; m->dp_y = 512;
    m->dp_halt = 0; m->dp_enabled = 1; m->dp_intensity = 7; m->dp_scale = 1;
    m->dp_ret_top = 0; m->keyboard = 0; m->cycles = 0; m->nvec = 0;
}

void machine_power_on(Machine *m) {
    machine_reset(m);
    m->mp_halt = 0;
    m->mp_run = 1;
}

/* ---- display list ---- */
void machine_dl_line(Machine *m, int x1, int y1, int x2, int y2, float bright) {
    if (m->nvec >= MACHINE_MAX_VEC) return;
    MachineVec *v = &m->vecs[m->nvec++];
    v->x1 = x1; v->y1 = y1; v->x2 = x2; v->y2 = y2; v->isPoint = 0; v->bright = bright;
}

void machine_dl_point(Machine *m, int x, int y, float bright) {
    if (m->nvec >= MACHINE_MAX_VEC) return;
    MachineVec *v = &m->vecs[m->nvec++];
    v->x1 = x; v->y1 = y; v->x2 = 0; v->y2 = 0; v->isPoint = 1; v->bright = bright;
}

void machine_dl_clear(Machine *m) { m->nvec = 0; }

static void console_putc(Machine *m, char c) {
    if (m->console_len >= (int)sizeof(m->console) - 1) {
        memmove(m->console, m->console + 256, m->console_len - 256);
        m->console_len -= 256;
    }
    m->console[m->console_len++] = c;
    m->console[m->console_len] = 0;
}

/* ---- main processor ---- */
static void mp_skip(Machine *m, int word) {
    int inv  = (word >> 5) & 1;
    int cond = word & 0x1F;
    int skip = 0;
    if (cond & 0x01) skip = skip || (m->mp_ac == 0);
    if (cond & 0x02) skip = skip || ((m->mp_ac & 0x8000) == 0);
    if (cond & 0x04) skip = skip || (m->mp_link == 0);
    if (cond & 0x08) skip = skip || (m->keyboard != 0);
    if (cond & 0x10) skip = skip || m->dp_halt;
    if (inv) skip = !skip;
    if (skip) m->mp_pc = (m->mp_pc + 1) & MACHINE_ADDR_MASK;
}

static void mp_opr(Machine *m, int word) {
    if (word & 0x800) {
        char buf[48];
        m->mp_halt = 1; m->mp_run = 0;
        snprintf(buf, sizeof buf, "[HALT PC=%X AC=%X]\n", m->mp_pc, m->mp_ac);
        for (char *p = buf; *p; p++) console_putc(m, *p);
        return;
    }
    if (word & 0x400) m->mp_ac = 0;
    if (word & 0x200) m->mp_link = 0;
    if (word & 0x100) m->mp_ac = (~m->mp_ac) & MACHINE_WORD_MASK;
    if (word & 0x080) m->mp_link ^= 1;
    if (word & 0x040) { int s = m->mp_ac + 1; m->mp_link = (s >> 16) & 1; m->mp_ac = s & MACHINE_WORD_MASK; }
    if (word & 0x020) m->mp_link = 1;
    if (word & 0x010) { int t = m->mp_ac; m->mp_ac = m->dp_ac; m->dp_ac = t; }
    if (word & 0x008) { int b = (m->mp_ac >> 15) & 1; m->mp_ac = ((m->mp_ac << 1) | m->mp_link) & MACHINE_WORD_MASK; m->mp_link = b; }
    if (word & 0x004) { int b = m->mp_ac & 1; m->mp_ac = ((m->mp_ac >> 1) | (m->mp_link << 15)) & MACHINE_WORD_MASK; m->mp_link = b; }
}

static void mp_iot(Machine *m, int word) {
    int dev = (word >> 6) & 0x3F;
    int fn  =  word       & 0x3F;
    switch (dev) {
        case 0x01:
            if (fn & 1) m->mp_ac = m->keyboard & MACHINE_WORD_MASK;
            if (fn & 2) m->keyboard = 0;
            if ((fn & 4) && m->keyboard != 0) m->mp_pc = (m->mp_pc + 1) & MACHINE_ADDR_MASK;
            break;
        case 0x02:
            if (fn & 1) m->dp_enabled = !m->dp_enabled;
            if (fn & 2) { m->dp_halt = 0; m->dp_pc = m->mp_ac & MACHINE_ADDR_MASK; }
            if (fn & 4) m->dp_halt = 1;
            break;
        case 0x04: {
            int c = m->mp_ac & 0x7F;
            if (c >= 32 || c == '\n') console_putc(m, (char)c);
            break;
        }
        case 0x10:
            if (fn & 1) m->mp_ac = m->lpen_x;
            if (fn & 2) m->mp_ac = m->lpen_y;
            if ((fn & 4) && m->lpen_hit) m->mp_pc = (m->mp_pc + 1) & MACHINE_ADDR_MASK;
            break;
        case 0x20: m->mp_ac = m->cycles & MACHINE_WORD_MASK; break;
        default: break;
    }
}

void machine_mp_step(Machine *m) {
    if (m->mp_halt) return;
    int *mem = m->mem;
    int word = mem[m->mp_pc & MACHINE_ADDR_MASK] & MACHINE_WORD_MASK;
    m->mp_ir = word;
    m->mp_pc = (m->mp_pc + 1) & MACHINE_ADDR_MASK;
    m->cycles += 1;

    int op  = (word >> 12) & 0xF;
    int ind = (word >> 11) & 0x1;
    int ea  =  word & MACHINE_ADDR_MASK;
    if (ind) ea = mem[ea] & MACHINE_ADDR_MASK;

    switch (op) {
        case 0x0: break;
        case 0x1:
            if (ind) m->mp_ac = (-(word & 0x7FF)) & MACHINE_WORD_MASK;
            else     m->mp_ac =  (word & 0x7FF);
            break;
        case 0x2: m->mp_pc = ea; break;
        case 0x3: mem[ea] = m->mp_ac; break;
        case 0x4: { int t = mem[ea]; mem[ea] = m->mp_ac; m->mp_ac = t; break; }
        case 0x5:
            mem[ea] = (mem[ea] + 1) & MACHINE_WORD_MASK;
            if ((mem[ea] & 0x8000) == 0) m->mp_pc = (m->mp_pc + 1) & MACHINE_ADDR_MASK;
            break;
        case 0x6: { int s = m->mp_ac + mem[ea]; m->mp_link = (s >> 16) & 1; m->mp_ac = s & MACHINE_WORD_MASK; break; }
        case 0x7: m->mp_ac &= mem[ea]; break;
        case 0x8: m->mp_ac = mem[ea] & MACHINE_WORD_MASK; break;
        case 0x9: mem[ea] = m->mp_pc; m->mp_pc = (ea + 1) & MACHINE_ADDR_MASK; break;
        case 0xA: mp_skip(m, word); break;
        case 0xB: m->mp_ac |= mem[ea]; m->mp_ac &= MACHINE_WORD_MASK; break;
        case 0xC: {
            int n = word & 0xFF; if (n == 0) n = 1;
            for (int i = 0; i < n; i++) {
                int b = (m->mp_ac >> 15) & 1;
                m->mp_ac = ((m->mp_ac << 1) | m->mp_link) & MACHINE_WORD_MASK; m->mp_link = b;
            }
            break;
        }
        case 0xD: {
            int n = word & 0xFF; if (n == 0) n = 1;
            for (int i = 0; i < n; i++) {
                int b = m->mp_ac & 1;
                m->mp_ac = ((m->mp_ac >> 1) | (m->mp_link << 15)) & MACHINE_WORD_MASK; m->mp_link = b;
            }
            break;
        }
        case 0xE: mp_iot(m, word); break;
        case 0xF: mp_opr(m, word); break;
        default: break;
    }
}

/* ---- display processor ---- */
void machine_dp_step(Machine *m) {
    if (!(m->dp_enabled && !m->dp_halt)) return;
    int word = m->mem[m->dp_pc & MACHINE_ADDR_MASK] & MACHINE_WORD_MASK;
    m->dp_pc = (m->dp_pc + 1) & MACHINE_ADDR_MASK;
    int op   = (word >> 12) & 0xF;
    int addr =  word & MACHINE_ADDR_MASK;
    float bright = (float)m->dp_intensity / 7.0f;
    if (bright < 0.05f) bright = 0.05f;

    switch (op) {
        case 0x0:
            if ((word & 0x0E00) == 0x0E00) m->dp_intensity = word & 0x7;
            break;
        case 0x1: m->dp_x = addr; break;
        case 0x2: m->dp_y = addr; break;
        case 0x3: {
            int dx = (word >> 6) & 0x1F, dy = word & 0x1F;
            if (word & 0x0800) dx = -dx;
            if (word & 0x0020) dy = -dy;
            int nx = (m->dp_x + dx) & 1023, ny = (m->dp_y + dy) & 1023;
            machine_dl_line(m, m->dp_x, m->dp_y, nx, ny, bright);
            m->dp_x = nx; m->dp_y = ny;
            break;
        }
        case 0x4: {
            int dx = ((word >> 6) & 0x3F) * 8, dy = (word & 0x3F) * 8;
            if (word & 0x0800) dx = -dx;
            if (word & 0x0020) dy = -dy;
            int nx = (m->dp_x + dx) & 1023, ny = (m->dp_y + dy) & 1023;
            machine_dl_line(m, m->dp_x, m->dp_y, nx, ny, bright);
            m->dp_x = nx; m->dp_y = ny;
            break;
        }
        case 0x5: m->dp_pc = addr; break;
        case 0x6:
            if (m->dp_ret_top < 15) { m->dp_ret_stack[m->dp_ret_top++] = m->dp_pc; }
            m->dp_pc = addr;
            break;
        case 0x7:
            if (word & 0x0800) machine_dl_point(m, m->dp_x, m->dp_y, bright);
            else if (word & 0x0010) m->dp_intensity = word & 0x7;
            break;
        case 0x8:
            if ((word & 0x0800) && m->dp_ret_top > 0) { m->dp_pc = m->dp_ret_stack[--m->dp_ret_top]; }
            else m->dp_halt = 1;
            break;
        case 0x9: m->dp_intensity = word & 0x7; break;
        case 0xA: {
            static const float sc[4] = {0.25f, 0.5f, 1.0f, 2.0f};
            m->dp_scale = sc[word & 0x3];
            break;
        }
        case 0xB:
            if (m->dp_ret_top > 0) { m->dp_pc = m->dp_ret_stack[--m->dp_ret_top]; }
            else m->dp_halt = 1;
            break;
        case 0xC: m->dp_x = addr; break;
        case 0xD: m->dp_y = addr; break;
        case 0xE: m->dp_x = (word >> 6) & 0x1F; m->dp_y = word & 0x1F; break;
        case 0xF: m->dp_halt = 1; break;
        default: break;
    }
}

/* ---- assembler ---- */
#define N_MNEM 40
static const char *const kMnem[N_MNEM] = {
    "LAW","JMP","DAC","XAM","ISP","ADD","AND","LDA","JMS","IOR",
    "RAL","RAR","IOT","HLT","CLA","CLL","CMA","CML","IAC","STL","SAM","NOP",
    "SKZ","SKP","SKL","SKK","SKD","DLXA","DLYA","DSVH","DLVH","DJMP","DJMS",
    "DPTS","DHLT","DRJM","DEIM","DVSF","RAL1","RAR1"};
static const int kOpc[N_MNEM] = {
    0x1000,0x2000,0x3000,0x4000,0x5000,0x6000,0x7000,0x8000,0x9000,0xB000,
    0xC000,0xD000,0xE000,0xF800,0xF400,0xF200,0xF100,0xF080,0xF040,0xF020,0xF010,0xF000,
    0xA001,0xA002,0xA004,0xA008,0xA010,0x1000,0x2000,0x3000,0x4000,0x5000,0x6000,
    0x7800,0x8000,0xB000,0x9000,0xA000,0xC001,0xD001};
static const int kHasAddr[N_MNEM] = {
    1,1,1,1,1,1,1,1,1,1,
    1,1,1,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,1,1,1,1,1,1,
    0,0,0,1,1,0,0};

#define ASM_MAX_LABELS 256
#define ASM_MAX_TOK    16
typedef struct { char name[32]; int val; } AsmLabel;
static AsmLabel g_labels[ASM_MAX_LABELS];
static int g_nlabels;

static int asm_parse_val(const char *t) {
    if (t[0] == '0' && (t[1] == 'x' || t[1] == 'X')) return (int)strtoul(t + 2, NULL, 16);
    char up[32]; int i = 0;
    for (; t[i] && i < 31; i++) up[i] = (char)toupper((unsigned char)t[i]);
    up[i] = 0;
    for (int k = 0; k < g_nlabels; k++) if (!strcmp(g_labels[k].name, up)) return g_labels[k].val;
    return (int)strtol(t, NULL, 10);
}

/* Split a line (comment already cut) into tokens separated by space/tab/comma. */
static int asm_tokenize(char *line, char **tok) {
    int n = 0;
    char *p = line;
    while (*p && n < ASM_MAX_TOK) {
        while (*p == ' ' || *p == '\t' || *p == ',' || *p == '\r') p++;
        if (!*p) break;
        tok[n++] = p;
        while (*p && *p != ' ' && *p != '\t' && *p != ',' && *p != '\r') p++;
        if (*p) *p++ = 0;
    }
    return n;
}

static int streq_ci(const char *a, const char *b) {
    for (; *a && *b; a++, b++) if (toupper((unsigned char)*a) != toupper((unsigned char)*b)) return 0;
    return *a == *b;
}

int machine_assemble(Machine *m, const char *src) {
    const int baseAddr = 0x050;
    g_nlabels = 0;

    for (int pass = 1; pass <= 2; pass++) {
        int addr = baseAddr;
        const char *p = src;
        while (*p) {
            char line[256];
            int len = 0;
            while (*p && *p != '\n') { if (len < 255 && *p != ';' ) line[len++] = *p; else if (*p == ';') { while (*p && *p != '\n') p++; break; } p++; }
            line[len] = 0;
            if (*p == '\n') p++;

            char *tok[ASM_MAX_TOK];
            int nt = asm_tokenize(line, tok);
            if (nt == 0) continue;
            int ti = 0;

            if (streq_ci(tok[0], ".ORG") || streq_ci(tok[0], "ORG")) {
                if (nt > 1) addr = asm_parse_val(tok[1]);
                continue;
            }
            if (streq_ci(tok[0], ".DP") || streq_ci(tok[0], ".MP")) continue;

            size_t l0 = strlen(tok[0]);
            if (l0 > 0 && tok[0][l0 - 1] == ':') {
                if (pass == 1 && g_nlabels < ASM_MAX_LABELS) {
                    AsmLabel *lb = &g_labels[g_nlabels++];
                    size_t k = 0;
                    for (; k < l0 - 1 && k < 31; k++) lb->name[k] = (char)toupper((unsigned char)tok[0][k]);
                    lb->name[k] = 0;
                    lb->val = addr;
                }
                ti = 1;
                if (nt == 1) continue;
            }

            const char *mn = tok[ti];
            if (streq_ci(mn, ".WORD") || streq_ci(mn, "DATA")) {
                for (int i = ti + 1; i < nt; i++) {
                    if (pass == 2 && addr < MACHINE_MEM_SIZE) m->mem[addr] = asm_parse_val(tok[i]);
                    addr++;
                }
                continue;
            }
            if (pass == 1) { addr++; continue; }

            int mi = -1;
            for (int k = 0; k < N_MNEM; k++) if (streq_ci(mn, kMnem[k])) { mi = k; break; }
            if (mi < 0) continue;
            int word = kOpc[mi];
            if (kHasAddr[mi] && nt > ti + 1) {
                int val = asm_parse_val(tok[ti + 1]);
                if ((word & 0xF000) == 0x1000) word |= (val & 0x7FF);
                else word |= (val & MACHINE_ADDR_MASK);
            }
            if (addr < MACHINE_MEM_SIZE) { m->mem[addr] = word; addr++; }
        }
        if (pass == 2) return addr - baseAddr;
    }
    return 0;
}

/* font.c - vector font (data copied verbatim from Demos.m / MazeWarGame.m) */
#include <ctype.h>
#include <string.h>

/* FONT[charIndex] = array of segments [x1,y1,x2,y2]; authored in screen space (Y down). */
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
    {{0}}, /* space */
};
static const int kFontSegCount[37] = {3,8,3,5,4,3,5,3,3,3,3,2,4,3,4,5,5,6,5,2,3,2,4,2,3,3,5,3,5,4,3,5,5,2,5,4,0};
static const char kChars[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ";

void font_char(Machine *m, int c, int ox, int oy, float sc, float b) {
    int up = toupper(c & 0xFF);
    const char *p = up ? strchr(kChars, up) : NULL;
    if (!p) return;
    int idx = (int)(p - kChars);
    if (idx >= 37) return;
    int n = kFontSegCount[idx];
    for (int s = 0; s < n; s++) {
        const float *seg = kFontData[idx][s];
        machine_dl_line(m, ox + (int)(seg[0] * sc), oy + (int)(seg[1] * sc),
                           ox + (int)(seg[2] * sc), oy + (int)(seg[3] * sc), b);
    }
}

void font_text(Machine *m, const char *s, int ox, int oy, float sc, float b) {
    int x = ox;
    for (; *s; s++) {
        font_char(m, (unsigned char)*s, x, oy, sc, b);
        x += (int)(sc * 5.5f);
    }
}

/* mazewar.c - Maze War (1974) single player, ported from MazeWarGame.m
 * LAN multiplayer (NetSession, UDP) is not ported: the PSP has no BSD-style
 * LAN stack in the homebrew SDK that matches the iOS code path. */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#define VX0 40
#define VX1 780
#define VY0 80
#define VY1 940
#define VCX ((VX0 + VX1) / 2)
#define VCY ((VY0 + VY1) / 2)
#define VW  (VX1 - VX0)
#define VH  (VY1 - VY0)

static const int DX[4]  = {0, 1, 0, -1};
static const int DY[4]  = {1, 0, -1, 0};
static const int OPP[4] = {2, 3, 0, 1};

#define MAXI(a,b) ((a)>(b)?(a):(b))
#define MINI(a,b) ((a)<(b)?(a):(b))

static void mw_set_msg(MazeWar *g, const char *s, int t) {
    snprintf(g->msg, sizeof g->msg, "%s", s);
    g->msgT = t;
}

static void mw_vl(MazeWar *g, int x1, int y1, int x2, int y2, float b) { machine_dl_line(g->M, x1, y1, x2, y2, b); }
static void mw_txt(MazeWar *g, const char *s, int ox, int oy, float sc, float b) { font_text(g->M, s, ox, oy, sc, b); }
static int mw_clampx(int x) { return MAXI(VX0, MINI(VX1, x)); }
static int mw_clampy(int y) { return MAXI(VY0, MINI(VY1, y)); }

static void mw_ellipse(MazeWar *g, int cx, int cy, int rx, int ry, int segs, float b) {
    int ppx = cx + rx, ppy = cy;
    for (int i = 1; i <= segs; i++) {
        double a = (double)i / (double)segs * 2 * M_PI;
        int nx = cx + (int)(cos(a) * rx), ny = cy + (int)(sin(a) * ry);
        mw_vl(g, ppx, ppy, nx, ny, b);
        ppx = nx; ppy = ny;
    }
}

void mazewar_init(MazeWar *g, Machine *m) {
    memset(g, 0, sizeof(*g));
    g->M = m;
    for (int i = 0; i < MZ * MZ; i++) g->maze[i] = 0xF;
    g->px = 1; g->py = 1; g->hp = 3; g->level = 1;
    g->state = MW_TITLE;
}

/* ---- maze ---- */
static int mw_wall(const MazeWar *g, int x, int y, int dir) {
    if (x < 0 || x >= MZ || y < 0 || y >= MZ) return 1;
    return (g->maze[y * MZ + x] & (1 << dir)) != 0;
}
static int mw_solid(const MazeWar *g, int x, int y) {
    if (x < 0 || x >= MZ || y < 0 || y >= MZ) return 1;
    return g->maze[y * MZ + x] == 0xF;
}

static int next_rnd(uint32_t *rng) {
    *rng = *rng * 1664525u + 1013904223u;
    return (int)((*rng >> 16) & 0x7FFF);
}

static void mw_carve(MazeWar *g, int x, int y, unsigned char *vis, uint32_t *rng) {
    vis[y * MZ + x] = 1;
    int d[4] = {0, 1, 2, 3};
    for (int i = 3; i >= 1; i--) {
        int j = next_rnd(rng) % (i + 1);
        int t = d[i]; d[i] = d[j]; d[j] = t;
    }
    for (int k = 0; k < 4; k++) {
        int dd = d[k];
        int nx = x + DX[dd], ny = y + DY[dd];
        if (nx < 1 || nx >= MZ - 1 || ny < 1 || ny >= MZ - 1 || vis[ny * MZ + nx]) continue;
        g->maze[y * MZ + x]   &= ~(1 << dd);
        g->maze[ny * MZ + nx] &= ~(1 << OPP[dd]);
        mw_carve(g, nx, ny, vis, rng);
    }
}

static void gen_maze(MazeWar *g, uint32_t seed) {
    for (int i = 0; i < MZ * MZ; i++) g->maze[i] = 0xF;
    unsigned char vis[MZ * MZ];
    memset(vis, 0, sizeof(vis));
    uint32_t rng = seed;
    mw_carve(g, 1, 1, vis, &rng);
}

static void spawn_ai(MazeWar *g, int n) {
    for (int i = 0; i < n && g->nEnemies < MW_MAX_ENEMIES; i++) {
        int ex = 0, ey = 0;
        for (int tries = 0; tries < 200; tries++) {
            ex = 2 + (int)pds_rand_uniform(MZ - 4);
            ey = 2 + (int)pds_rand_uniform(MZ - 4);
            if (!mw_solid(g, ex, ey) && (abs(ex - g->px) + abs(ey - g->py) > 3)) break;
        }
        MwEnemy *e = &g->enemies[g->nEnemies++];
        e->x = ex; e->y = ey; e->dir = (int)pds_rand_uniform(4);
        e->think = 30; e->fireCd = 80; e->alive = 1;
    }
}

static void add_bullet(MazeWar *g, double x, double y, int dir, int fromPlayer) {
    if (g->nBullets >= MW_MAX_BULLETS) return;
    MwBullet *b = &g->bullets[g->nBullets++];
    b->x = x; b->y = y; b->dir = dir; b->life = 55; b->fromPlayer = fromPlayer; b->alive = 1;
}

static void start_game(MazeWar *g, uint32_t seed) {
    gen_maze(g, seed & 0x7FFFFFFF);
    g->px = 1; g->py = 1; g->pdir = 0; g->hp = 3; g->score = 0; g->level = 1;
    g->moveCd = g->turnCd = g->fireCd = g->hitFlash = g->killFlash = 0;
    g->nBullets = 0; g->nEnemies = 0;
    spawn_ai(g, g->level + 1);
    g->state = MW_PLAY;
}

void mazewar_start_single(MazeWar *g) { start_game(g, pds_rand()); }

/* ---- logic ---- */
static void tick_bullets(MazeWar *g) {
    for (int i = 0; i < g->nBullets; i++) {
        MwBullet *b = &g->bullets[i];
        if (!b->alive) continue;
        if (--b->life <= 0) { b->alive = 0; continue; }
        b->x += (double)DX[b->dir] * 0.2; b->y += (double)DY[b->dir] * 0.2;
        if (mw_solid(g, (int)b->x, (int)b->y)) { b->alive = 0; continue; }
        if (b->fromPlayer) {
            for (int k = 0; k < g->nEnemies; k++) {
                MwEnemy *e = &g->enemies[k];
                if (!e->alive) continue;
                if (fabs(b->x - ((double)e->x + 0.5)) < 0.6 && fabs(b->y - ((double)e->y + 0.5)) < 0.6) {
                    e->alive = 0; b->alive = 0; g->score++; g->killFlash = 12;
                    mw_set_msg(g, "KILL", 30);
                    break;
                }
            }
        } else if (fabs(b->x - ((double)g->px + 0.5)) < 0.55 && fabs(b->y - ((double)g->py + 0.5)) < 0.55) {
            b->alive = 0; g->hp--; g->hitFlash = 18;
            if (g->hp > 0) { char buf[32]; snprintf(buf, sizeof buf, "HIT! HP:%d", g->hp); mw_set_msg(g, buf, 45); }
            else { mw_set_msg(g, "YOU DIED", 45); }
            if (g->hp <= 0) g->state = MW_DEAD;
        }
    }
    int n = 0;
    for (int i = 0; i < g->nBullets; i++) if (g->bullets[i].alive) g->bullets[n++] = g->bullets[i];
    g->nBullets = n;
}

static int los(const MazeWar *g, int x1, int y1, int x2, int y2) {
    if (x1 == x2) { for (int y = y1; y < y2; y++) if (mw_wall(g, x1, y, 0)) return 0; }
    else          { for (int x = x1; x < x2; x++) if (mw_wall(g, x, y1, 1)) return 0; }
    return 1;
}

static void tick_ai(MazeWar *g) {
    for (int k = 0; k < g->nEnemies; k++) {
        MwEnemy *e = &g->enemies[k];
        if (!e->alive) continue;
        e->think--; e->fireCd--;
        if (e->think <= 0) {
            e->think = 15 + (int)pds_rand_uniform(25);
            int dx = g->px - e->x, dy = g->py - e->y;
            int want = -1;
            if (abs(dx) > abs(dy)) want = dx > 0 ? 1 : 3;
            else if (dy != 0)      want = dy > 0 ? 0 : 2;
            double r = (double)pds_rand() / 4294967295.0;
            if (r < 0.6 && want >= 0 && !mw_wall(g, e->x, e->y, want)) {
                e->dir = want; e->x += DX[want]; e->y += DY[want];
            } else {
                int ds[4] = {0, 1, 2, 3};
                for (int i = 3; i >= 1; i--) {
                    int j = (int)pds_rand_uniform((uint32_t)(i + 1));
                    int t = ds[i]; ds[i] = ds[j]; ds[j] = t;
                }
                for (int i = 0; i < 4; i++) {
                    int dd = ds[i];
                    if (!mw_wall(g, e->x, e->y, dd)) { e->dir = dd; e->x += DX[dd]; e->y += DY[dd]; break; }
                }
            }
        }
        if (e->fireCd <= 0) {
            int sh = 0;
            if (e->dir == 0 && e->x == g->px && g->py > e->y) sh = los(g, e->x, e->y, g->px, g->py);
            if (e->dir == 2 && e->x == g->px && g->py < e->y) sh = los(g, g->px, g->py, e->x, e->y);
            if (e->dir == 1 && e->y == g->py && g->px > e->x) sh = los(g, e->x, e->y, g->px, g->py);
            if (e->dir == 3 && e->y == g->py && g->px < e->x) sh = los(g, g->px, g->py, e->x, e->y);
            if (sh) {
                add_bullet(g, (double)e->x + 0.5, (double)e->y + 0.5, e->dir, 0);
                e->fireCd = 60 + (int)pds_rand_uniform(60);
            }
        }
    }
}

static void check_win(MazeWar *g) {
    int allDead = 1;
    for (int k = 0; k < g->nEnemies; k++) if (g->enemies[k].alive) { allDead = 0; break; }
    if (allDead) {
        char buf[32];
        g->level++;
        snprintf(buf, sizeof buf, "LEVEL %d!", g->level);
        mw_set_msg(g, buf, 60);
        gen_maze(g, pds_rand() & 0x7FFFFFFF);
        g->px = 1; g->py = 1; g->pdir = 0;
        g->nBullets = 0; g->nEnemies = 0;
        spawn_ai(g, MINI(g->level + 1, 7));
    }
}

static void tick_play(MazeWar *g) {
    if (g->moveCd > 0) g->moveCd--;
    if (g->turnCd > 0) g->turnCd--;
    if (g->fireCd > 0) g->fireCd--;
    if (g->hitFlash > 0) g->hitFlash--;
    if (g->killFlash > 0) g->killFlash--;
    if (g->msgT > 0) g->msgT--;

    if (g->turnCd == 0) {
        if (g->iLeft && !g->pLeft)   { g->pdir = (g->pdir + 3) % 4; g->turnCd = 8; }
        if (g->iRight && !g->pRight) { g->pdir = (g->pdir + 1) % 4; g->turnCd = 8; }
    }
    if (g->moveCd == 0) {
        if (g->iUp && !mw_wall(g, g->px, g->py, g->pdir)) { g->px += DX[g->pdir]; g->py += DY[g->pdir]; g->moveCd = 12; }
        else if (g->iDown && !mw_wall(g, g->px, g->py, (g->pdir + 2) % 4)) { g->px -= DX[g->pdir]; g->py -= DY[g->pdir]; g->moveCd = 12; }
    }
    if (g->iFire && !g->pFire && g->fireCd == 0) {
        add_bullet(g, (double)g->px + 0.5, (double)g->py + 0.5, g->pdir, 1);
        g->fireCd = 20;
    }
    tick_bullets(g);
    tick_ai(g);
    check_win(g);
}

static int any_input(const MazeWar *g) { return g->iUp || g->iDown || g->iLeft || g->iRight || g->iFire; }
static int any_prev(const MazeWar *g)  { return g->pUp || g->pDown || g->pLeft || g->pRight || g->pFire; }

void mazewar_tick(MazeWar *g) {
    int k = g->M->keyboard & 0x7F;
    g->iUp    = g->iUp    || (k == 'W');
    g->iDown  = g->iDown  || (k == 'S');
    g->iLeft  = g->iLeft  || (k == 'A');
    g->iRight = g->iRight || (k == 'D');
    g->iFire  = g->iFire  || (k == 32 || k == 'F');

    switch (g->state) {
        case MW_TITLE:
            if (any_input(g) && !any_prev(g)) start_game(g, pds_rand());
            break;
        case MW_PLAY: tick_play(g); break;
        case MW_DEAD:
            if (any_input(g) && !any_prev(g)) g->state = MW_TITLE;
            break;
    }
    g->pUp = g->iUp; g->pDown = g->iDown; g->pLeft = g->iLeft; g->pRight = g->iRight; g->pFire = g->iFire;
    g->iUp = g->iDown = g->iLeft = g->iRight = g->iFire = 0;
    g->frame++;
}

/* ---- drawing ---- */
static void draw_eye(MazeWar *g, int cx, int cy, int sz, float b) {
    int rx = sz, ry = (int)((float)sz * 0.55f);
    mw_ellipse(g, cx, cy, rx, ry, 16, b);
    mw_ellipse(g, cx, cy, rx / 3, (int)((float)ry * 0.7f), 10, b * 1.1f);
    mw_vl(g, cx - rx, cy, cx + rx, cy, b * 0.3f);
    if (sz > 25) {
        for (int i = -2; i <= 2; i++) {
            if (i == 0) continue;
            mw_vl(g, cx + i * (rx / 3), cy + ry + 2, cx + i * (rx / 3) + i * 4, cy + ry + 20, b * 0.6f);
        }
    }
}

static void draw_entity_if_visible(MazeWar *g, int ex, int ey) {
    int relDir = -1;
    if (g->pdir == 0 && ex == g->px && ey > g->py) relDir = 0;
    if (g->pdir == 1 && ey == g->py && ex > g->px) relDir = 1;
    if (g->pdir == 2 && ex == g->px && ey < g->py) relDir = 2;
    if (g->pdir == 3 && ey == g->py && ex < g->px) relDir = 3;
    if (relDir != g->pdir) return;
    int dist = (g->pdir == 0 || g->pdir == 2) ? abs(ey - g->py) : abs(ex - g->px);
    if (!(dist >= 1 && dist <= 8)) return;
    for (int d = 0; d < dist; d++)
        if (mw_wall(g, g->px + DX[g->pdir] * d, g->py + DY[g->pdir] * d, g->pdir)) return;
    float sc = 1.4f / ((float)dist + 0.5f);
    int sz = MAXI(8, MINI((int)((float)VH * 0.25f * sc), 120));
    float b = fmaxf(0.3f, 0.9f - (float)dist * 0.08f);
    draw_eye(g, VCX, VCY, sz, b);
}

static void draw_3d(MazeWar *g) {
    const int MAXD = 10;
    int depth = 0, wx = g->px, wy = g->py;
    for (int d = 1; d <= MAXD; d++) {
        if (mw_wall(g, wx, wy, g->pdir)) { depth = d - 1; break; }
        wx += DX[g->pdir]; wy += DY[g->pdir];
        if (mw_solid(g, wx, wy)) { depth = d - 1; break; }
        depth = d;
    }
    if (depth < 0) depth = 0;
    int lt[MAXD + 2], rt[MAXD + 2], tp[MAXD + 2], bt[MAXD + 2];
    for (int d = 0; d <= depth + 1; d++) {
        float sc = 1.4f / (float)(d + 1);
        lt[d] = mw_clampx(VCX - (int)((float)VW / 2 * sc)); rt[d] = mw_clampx(VCX + (int)((float)VW / 2 * sc));
        tp[d] = mw_clampy(VCY - (int)((float)VH / 2 * sc)); bt[d] = mw_clampy(VCY + (int)((float)VH / 2 * sc));
    }
    int cx2 = g->px, cy2 = g->py;
    for (int d = 0; d <= depth; d++) {
        float bright = fmaxf(0.2f, 1.0f - (float)d * 0.1f);
        int hl = !mw_wall(g, cx2, cy2, (g->pdir + 3) % 4);
        int hr = !mw_wall(g, cx2, cy2, (g->pdir + 1) % 4);
        int hf = !mw_wall(g, cx2, cy2, g->pdir) && d < depth;
        if (!hl) {
            mw_vl(g, lt[d], tp[d], lt[d + 1], tp[d + 1], bright * 0.8f);
            mw_vl(g, lt[d], bt[d], lt[d + 1], bt[d + 1], bright * 0.8f);
            mw_vl(g, lt[d + 1], tp[d + 1], lt[d + 1], bt[d + 1], bright * 0.6f);
        } else {
            mw_vl(g, lt[d], tp[d], lt[d], bt[d], bright * 0.5f);
        }
        if (!hr) {
            mw_vl(g, rt[d], tp[d], rt[d + 1], tp[d + 1], bright * 0.8f);
            mw_vl(g, rt[d], bt[d], rt[d + 1], bt[d + 1], bright * 0.8f);
            mw_vl(g, rt[d + 1], tp[d + 1], rt[d + 1], bt[d + 1], bright * 0.6f);
        } else {
            mw_vl(g, rt[d], tp[d], rt[d], bt[d], bright * 0.5f);
        }
        if (!hf) {
            mw_vl(g, lt[d + 1], tp[d + 1], rt[d + 1], tp[d + 1], bright);
            mw_vl(g, lt[d + 1], bt[d + 1], rt[d + 1], bt[d + 1], bright);
            mw_vl(g, lt[d + 1], tp[d + 1], lt[d + 1], bt[d + 1], bright * 0.8f);
            mw_vl(g, rt[d + 1], tp[d + 1], rt[d + 1], bt[d + 1], bright * 0.8f);
            break;
        }
        cx2 += DX[g->pdir]; cy2 += DY[g->pdir];
    }
    mw_vl(g, VX0, VY0, lt[0], tp[0], 0.35f); mw_vl(g, VX1, VY0, rt[0], tp[0], 0.35f);
    mw_vl(g, VX0, VY1, lt[0], bt[0], 0.35f); mw_vl(g, VX1, VY1, rt[0], bt[0], 0.35f);
    mw_vl(g, VCX - 12, VCY, VCX - 4, VCY, 0.6f); mw_vl(g, VCX + 4, VCY, VCX + 12, VCY, 0.6f);
    mw_vl(g, VCX, VCY - 12, VCX, VCY - 4, 0.6f); mw_vl(g, VCX, VCY + 4, VCX, VCY + 12, 0.6f);
}

static void draw_hud(MazeWar *g) {
    char buf[32];
    for (int i = 0; i < 3; i++) {
        int hx = VX0 + 20 + i * 28;
        mw_ellipse(g, hx, VY1 + 25, 9, 9, 8, (i < g->hp ? 0.9f : 0.2f));
    }
    snprintf(buf, sizeof buf, "%04d", g->score);
    mw_txt(g, buf, VX1 - 120, VY1 + 18, 9, 0.7f);
    static const char *const dirNames[4] = {"N", "E", "S", "W"};
    mw_txt(g, dirNames[g->pdir], VX1 + 15, VY1 + 18, 10, 0.6f);
    snprintf(buf, sizeof buf, "LV%d", g->level);
    mw_txt(g, buf, VCX - 32, VY0 - 22, 9, 0.35f);
    if (g->fireCd > 0)
        mw_vl(g, VCX - 40, VY1 + 52, VCX - 40 + (int)((float)g->fireCd / 20 * 80), VY1 + 52, 0.4f);
}

static void draw_play(MazeWar *g) {
    mw_vl(g, VX0, VY0, VX1, VY0, 0.5f); mw_vl(g, VX1, VY0, VX1, VY1, 0.5f);
    mw_vl(g, VX1, VY1, VX0, VY1, 0.5f); mw_vl(g, VX0, VY1, VX0, VY0, 0.5f);
    if (g->hitFlash > 0) {
        float f = (float)g->hitFlash / 18;
        mw_vl(g, VX0, VY0, VX1, VY0, f); mw_vl(g, VX1, VY0, VX1, VY1, f);
        mw_vl(g, VX1, VY1, VX0, VY1, f); mw_vl(g, VX0, VY1, VX0, VY0, f);
    }
    draw_3d(g);
    for (int k = 0; k < g->nEnemies; k++) if (g->enemies[k].alive) draw_entity_if_visible(g, g->enemies[k].x, g->enemies[k].y);
    draw_hud(g);
    if (g->msgT > 0)
        mw_txt(g, g->msg, VCX - (int)strlen(g->msg) * 11, VCY - 60, 13, fminf(1.0f, (float)g->msgT / 20));
}

static void draw_title(MazeWar *g) {
    int ex = VCX + 100, ey = VCY, rx = 90, ry = 55;
    mw_ellipse(g, ex, ey, rx, ry, 20, 0.9f);
    mw_ellipse(g, ex, ey, rx / 3, (int)(ry * 0.8f), 12, 1.0f);
    for (int i = -3; i <= 3; i++) {
        if (i == 0) continue;
        mw_vl(g, ex + i * 28, ey + ry + 2, ex + i * 28 + i * 5, ey + ry + 28, 0.55f);
    }
    mw_txt(g, "MAZE WAR", VX0 + 10, VCY + 60, 18, 1.0f);
    mw_txt(g, "IMLAC PDS-1  1974", VX0 + 10, VCY + 10, 10, 0.5f);
    mw_txt(g, "SINGLE PLAYER", VX0 + 10, VCY - 40, 8, 0.4f);
    if ((g->frame / 20) % 2 == 0) mw_txt(g, "PRESS ANY BUTTON", VX0 + 10, VCY - 110, 9, 0.8f);
}

static void draw_dead(MazeWar *g) {
    char buf[32];
    mw_txt(g, "GAME OVER", VCX - 190, VCY + 80, 18, 0.9f);
    snprintf(buf, sizeof buf, "SCORE %d", g->score);
    mw_txt(g, buf, VCX - 160, VCY + 10, 13, 0.7f);
    if ((g->frame / 20) % 2 == 0) mw_txt(g, "PRESS ANY BUTTON", VCX - 215, VCY - 70, 11, 0.85f);
}

void mazewar_draw(MazeWar *g) {
    switch (g->state) {
        case MW_TITLE: draw_title(g); break;
        case MW_PLAY:  draw_play(g); break;
        case MW_DEAD:  draw_dead(g); break;
    }
}

/* demos.c - built-in demo programs (ported from Demos.m) */
#include <math.h>
#include <string.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#define MAXI(a,b) ((a)>(b)?(a):(b))
#define MINI(a,b) ((a)<(b)?(a):(b))

static const char *const kNames[DEMO_COUNT] = {
    "LINES","STAR","LISSAJOUS","TEXT","BOUNCE","MAZE","SPACEWAR","SCOPE","USER ASM","MAZE WAR"
};
const char *demos_name(DemoType t) { return (t >= 0 && t < DEMO_COUNT) ? kNames[t] : "?"; }

void demos_init(Demos *d, Machine *m) {
    memset(d, 0, sizeof(*d));
    d->M = m;
    d->current = DEMO_STAR;
    d->ballX = 512.0; d->ballY = 512.0; d->ballVx = 7.3; d->ballVy = 5.8;
    d->sw1x = 350.0; d->sw1y = 512.0; d->sw1a = 0.0;
    d->sw2x = 674.0; d->sw2y = 512.0; d->sw2a = M_PI;
    mazewar_init(&d->mazeWar, m);
}

void demos_set(Demos *d, DemoType t) {
    d->current = t;
    if (t == DEMO_MAZEWAR) mazewar_start_single(&d->mazeWar);
}

/* ---- helpers ---- */
static void d_vl(Demos *d, int x1, int y1, int x2, int y2, float b) { machine_dl_line(d->M, x1, y1, x2, y2, b); }
static void d_vp(Demos *d, int x, int y, float b) { machine_dl_point(d->M, x, y, b); }
static void d_rect(Demos *d, int x, int y, int w, int h, float b) {
    d_vl(d, x, y, x + w, y, b);
    d_vl(d, x + w, y, x + w, y + h, b);
    d_vl(d, x + w, y + h, x, y + h, b);
    d_vl(d, x, y + h, x, y, b);
}
static void d_circle(Demos *d, int cx, int cy, int r, int segs, float b) {
    int px = cx + r, py = cy;
    for (int i = 1; i <= segs; i++) {
        double a = (double)i / (double)segs * 2 * M_PI;
        int nx = cx + (int)(cos(a) * r), ny = cy + (int)(sin(a) * r);
        d_vl(d, px, py, nx, ny, b);
        px = nx; py = ny;
    }
}
static void d_border(Demos *d, float b) { d_rect(d, 20, 20, 984, 984, b); }
static void d_vtext(Demos *d, const char *s, int ox, int oy, float sc, float b) { font_text(d->M, s, ox, oy, sc, b); }

/* ---- LINES ---- */
static void demo_lines(Demos *d) {
    int cx = 512, cy = 512; double r = 450.0;
    for (int i = 0; i < 20; i++) {
        double a1 = (double)i / 20 * 2 * M_PI + d->angle;
        double a2 = (double)(i + 7) / 20 * 2 * M_PI + d->angle * 0.7;
        d_vl(d, cx + (int)(cos(a1) * r), cy + (int)(sin(a1) * r),
              cx + (int)(cos(a2) * r / 2), cy + (int)(sin(a2) * r / 2), 0.85f);
    }
    for (int i = 0; i < 8; i++) {
        double a = (double)i / 8 * 2 * M_PI - d->angle * 0.3;
        d_vl(d, cx, cy, cx + (int)(cos(a) * r), cy + (int)(sin(a) * r), 0.3f);
    }
    d_border(d, 0.5f);
    d_vtext(d, "IMLAC PDS-1", 280, 80, 16, 0.7f);
    d_vtext(d, "ROTATING LINES", 200, 30, 10, 0.4f);
}

/* ---- STAR ---- */
static void draw_star(Demos *d, int cx, int cy, int pts, int r1, int r2, double a0, float b) {
    int n = pts * 2;
    for (int i = 0; i < n; i++) {
        double a1 = (double)i / (double)n * 2 * M_PI + a0;
        double a2 = (double)(i + 1) / (double)n * 2 * M_PI + a0;
        int ra = (i % 2 == 0) ? r1 : r2;
        int rb = ((i + 1) % 2 == 0) ? r1 : r2;
        d_vl(d, cx + (int)(cos(a1) * ra), cy + (int)(sin(a1) * ra),
              cx + (int)(cos(a2) * rb), cy + (int)(sin(a2) * rb), b);
    }
}
static void demo_star(Demos *d) {
    draw_star(d, 512, 512, 7, 400, 160, d->angle, 1.0f);
    draw_star(d, 512, 512, 5, 120, 50, -d->angle * 2.5, 0.7f);
    d_border(d, 0.4f);
    d_vtext(d, "STAR", 380, 60, 20, 0.6f);
}

/* ---- LISSAJOUS ---- */
static void demo_lissajous(Demos *d) {
    int px = -1, py = -1;
    for (int i = 0; i <= 600; i++) {
        double tt = (double)i / 600 * 2 * M_PI;
        int x = 512 + (int)(460 * sin(3 * tt + d->angle));
        int y = 512 + (int)(460 * sin(2 * tt));
        if (px >= 0) d_vl(d, px, py, x, y, 0.85f);
        px = x; py = y;
    }
    d_border(d, 0.4f);
    d_vtext(d, "LISSAJOUS", 300, 60, 16, 0.5f);
}

/* ---- TEXT ---- */
static const char *const kTextLines[12] = {
    "IMLAC PDS-1","1970 MIT AI LAB","PROGRAMMED","DISPLAY SYSTEM",
    "16-BIT CPU","4096 WORDS RAM","VECTOR CRT","1024 X 1024","LIGHT PEN","SPACEWAR 1974",
    "ARPANET NODE","LOGO LANGUAGE"};
static void demo_text(Demos *d) {
    for (int i = 0; i < 12; i++) {
        double raw = 780.0 - (double)i * 140 + d->textScroll;
        double modv = fmod(raw, 1100.0);
        if (modv < 0) modv += 1100.0;
        int y = (int)modv - 100;
        if (y > -80 && y < 1050) d_vtext(d, kTextLines[i], 80, y, 20, 0.9f);
    }
    d->textScroll += 1.5;
    if (d->textScroll > 12.0 * 145) d->textScroll = 0;
    d_border(d, 0.3f);
}

/* ---- BOUNCE ---- */
static void demo_bounce(Demos *d) {
    d->ballX += d->ballVx; d->ballY += d->ballVy;
    if (d->ballX < 60 || d->ballX > 964) { d->ballVx *= -1; d->ballX = fmax(60.0, fmin(964.0, d->ballX)); }
    if (d->ballY < 60 || d->ballY > 964) { d->ballVy *= -1; d->ballY = fmax(60.0, fmin(964.0, d->ballY)); }
    if (d->trailN < 15) {
        d->trailX[d->trailN] = d->ballX; d->trailY[d->trailN] = d->ballY; d->trailN++;
    } else {
        for (int i = 0; i < 14; i++) { d->trailX[i] = d->trailX[i + 1]; d->trailY[i] = d->trailY[i + 1]; }
        d->trailX[14] = d->ballX; d->trailY[14] = d->ballY;
    }
    for (int i = 0; i < d->trailN - 1; i++)
        d_vp(d, (int)d->trailX[i], (int)d->trailY[i], (float)(i + 1) / (float)d->trailN * 0.4f);
    int bx = (int)d->ballX, by = (int)d->ballY;
    d_circle(d, bx, by, 35, 16, 1.0f);
    d_vl(d, bx - 50, by, bx + 50, by, 0.25f);
    d_vl(d, bx, by - 50, bx, by + 50, 0.25f);
    static const int corners[2] = {60, 964};
    for (int i = 0; i < 2; i++) for (int j = 0; j < 2; j++) d_circle(d, corners[i], corners[j], 20, 8, 0.4f);
    d_rect(d, 20, 20, 984, 984, 0.6f);
    d_vtext(d, "BOUNCE", 350, 40, 14, 0.6f);
}

/* ---- MAZE ---- */
static const int kCDX[4] = {0, 1, 0, -1};
static const int kCDY[4] = {1, 0, -1, 0};
static const int kCOPP[4] = {2, 3, 0, 1};

static void d_carve(Demos *d, int x, int y, unsigned char vis[DEMO_MH][DEMO_MW]) {
    vis[y][x] = 1;
    int dirs[4] = {0, 1, 2, 3};
    for (int i = 3; i > 0; i--) {
        int j = (int)pds_rand_uniform((uint32_t)(i + 1));
        int t = dirs[i]; dirs[i] = dirs[j]; dirs[j] = t;
    }
    for (int k = 0; k < 4; k++) {
        int dd = dirs[k];
        int nx = x + kCDX[dd], ny = y + kCDY[dd];
        if (nx < 0 || nx >= DEMO_MW || ny < 0 || ny >= DEMO_MH || vis[ny][nx]) continue;
        d->mazeGrid[y][x]   &= ~(1 << dd);
        d->mazeGrid[ny][nx] &= ~(1 << kCOPP[dd]);
        d_carve(d, nx, ny, vis);
    }
}

static void init_maze(Demos *d) {
    for (int y = 0; y < DEMO_MH; y++) for (int x = 0; x < DEMO_MW; x++) d->mazeGrid[y][x] = 0xF;
    unsigned char vis[DEMO_MH][DEMO_MW];
    memset(vis, 0, sizeof(vis));
    d_carve(d, 0, 0, vis);
    d->mazeReady = 1;
}

static void demo_maze(Demos *d) {
    if (!d->mazeReady) init_maze(d);
    int cw = (1024 - 60) / DEMO_MW, ch = (1024 - 60) / DEMO_MH, ox = 30, oy = 30;
    for (int y = 0; y < DEMO_MH; y++) {
        for (int x = 0; x < DEMO_MW; x++) {
            int cell = d->mazeGrid[y][x];
            int px = ox + x * cw, py = oy + y * ch;
            if (cell & 1) d_vl(d, px, py + ch, px + cw, py + ch, 0.85f);
            if (cell & 2) d_vl(d, px + cw, py, px + cw, py + ch, 0.85f);
            if (cell & 4) d_vl(d, px, py, px + cw, py, 0.85f);
            if (cell & 8) d_vl(d, px, py, px, py + ch, 0.85f);
        }
    }
    d_circle(d, ox + cw / 2, oy + ch / 2, 12, 8, 0.6f);
    d_circle(d, ox + (DEMO_MW - 1) * cw + cw / 2, oy + (DEMO_MH - 1) * ch + ch / 2, 12, 8, 1.0f);
    d_vtext(d, "MAZE", 370, 965, 14, 0.55f);
}

/* ---- SPACEWAR ---- */
static void fire_sw(Demos *d, double x, double y, double a, double vx, double vy) {
    for (int i = 0; i < 4; i++) {
        if (d->blife[i] > 0) continue;
        d->bx[i] = x; d->by[i] = y;
        d->bvx[i] = cos(a) * 9 + vx; d->bvy[i] = sin(a) * 9 + vy;
        d->blife[i] = 80;
        break;
    }
}

static void draw_ship(Demos *d, int cx, int cy, double a, float b) {
    double r1 = 30.0, r2 = 20.0, da = 2.5;
    int p1x = cx + (int)(cos(a) * r1),      p1y = cy + (int)(sin(a) * r1);
    int p2x = cx + (int)(cos(a + da) * r2), p2y = cy + (int)(sin(a + da) * r2);
    int p3x = cx + (int)(cos(a - da) * r2), p3y = cy + (int)(sin(a - da) * r2);
    d_vl(d, p1x, p1y, p2x, p2y, b);
    d_vl(d, p2x, p2y, p3x, p3y, b);
    d_vl(d, p3x, p3y, p1x, p1y, b);
}

static double wrap1024(double v) { v = fmod(v, 1024); if (v < 0) v += 1024; return v; }

static void demo_spacewar(Demos *d) {
    if (!d->swInit) { memset(d->blife, 0, sizeof(d->blife)); d->swInit = 1; }
    d->sw1a += 0.025; d->sw2a += 0.025;
    double dx1 = 512 - d->sw1x, dy1 = 512 - d->sw1y, d1 = sqrt(dx1 * dx1 + dy1 * dy1);
    if (d1 > 1) { d->sw1vx += dx1 / d1 * 0.15; d->sw1vy += dy1 / d1 * 0.15; }
    double dx2 = 512 - d->sw2x, dy2 = 512 - d->sw2y, d2 = sqrt(dx2 * dx2 + dy2 * dy2);
    if (d2 > 1) { d->sw2vx += dx2 / d2 * 0.15; d->sw2vy += dy2 / d2 * 0.15; }
    d->sw1x += d->sw1vx; d->sw1y += d->sw1vy; d->sw2x += d->sw2vx; d->sw2y += d->sw2vy;
    d->sw1x = wrap1024(d->sw1x); d->sw1y = wrap1024(d->sw1y);
    d->sw2x = wrap1024(d->sw2x); d->sw2y = wrap1024(d->sw2y);

    if (d->frame % 40 == 0) fire_sw(d, d->sw1x, d->sw1y, d->sw1a, d->sw1vx, d->sw1vy);
    if (d->frame % 53 == 0) fire_sw(d, d->sw2x, d->sw2y, d->sw2a, d->sw2vx, d->sw2vy);

    for (int i = 0; i < 4; i++) {
        if (d->blife[i] <= 0) continue;
        d->blife[i]--;
        d->bx[i] += d->bvx[i]; d->by[i] += d->bvy[i];
        d_vp(d, (int)d->bx[i], (int)d->by[i], 1.0f);
    }
    d_circle(d, 512, 512, 25, 12, 0.6f);
    d_circle(d, 512, 512, 8, 8, 1.0f);
    draw_ship(d, (int)d->sw1x, (int)d->sw1y, d->sw1a, 1.0f);
    draw_ship(d, (int)d->sw2x, (int)d->sw2y, d->sw2a + M_PI, 0.85f);
    d_vtext(d, "SPACEWAR", 310, 960, 14, 0.5f);
    d_rect(d, 20, 20, 984, 984, 0.3f);
}

/* ---- SCOPE ---- */
static void demo_scope(Demos *d) {
    static const double freqA[4] = {1.0, 2.0, 3.0, 5.0};
    static const double freqB[4] = {1.0, 3.0, 4.0, 4.0};
    static const float brs[4] = {0.9f, 0.7f, 0.55f, 0.4f};
    for (int f = 0; f < 4; f++) {
        double ph = d->angle * (double)(f + 1) * 0.3;
        int px = -1, py = -1;
        for (int i = 0; i <= 400; i++) {
            double tt = (double)i / 400 * 2 * M_PI;
            int x = 512 + (int)(440 * sin(freqA[f] * tt + ph));
            int y = 512 + (int)(440 * sin(freqB[f] * tt));
            if (px >= 0) d_vl(d, px, py, x, y, brs[f]);
            px = x; py = y;
        }
    }
    d_border(d, 0.4f);
    d_vtext(d, "SCOPE", 380, 60, 14, 0.5f);
}

/* ---- dispatcher ---- */
void demos_run(Demos *d) {
    switch (d->current) {
        case DEMO_LINES:     demo_lines(d); break;
        case DEMO_STAR:      demo_star(d); break;
        case DEMO_LISSAJOUS: demo_lissajous(d); break;
        case DEMO_TEXT:      demo_text(d); break;
        case DEMO_BOUNCE:    demo_bounce(d); break;
        case DEMO_MAZE:      demo_maze(d); break;
        case DEMO_SPACEWAR:  demo_spacewar(d); break;
        case DEMO_SCOPE:     demo_scope(d); break;
        case DEMO_USERASM:   break;
        case DEMO_MAZEWAR:   mazewar_tick(&d->mazeWar); mazewar_draw(&d->mazeWar); break;
        default: break;
    }
    d->angle += 0.018; d->t += 0.016; d->frame += 1;
}

/* main.c - Imlac PDS-1 for PSP (PSPSDK, sceGu)
 *
 * Original: iOS/ObjC emulator + demos + Maze War. This is a C port of the
 * portable parts (machine/demos/font/mazewar) plus a new PSP front-end:
 * vector CRT renderer on the GU, controls via sceCtrl.
 */
#include <pspkernel.h>
#include <pspdisplay.h>
#include <pspctrl.h>
#include <pspgu.h>
#include <pspgum.h>
#include <psppower.h>
#include <string.h>
#include <stdio.h>
#include <time.h>


PSP_MODULE_INFO("ImlacPDS1", PSP_MODULE_USER, 1, 0);
PSP_MAIN_THREAD_ATTR(PSP_THREAD_ATTR_USER);
PSP_HEAP_SIZE_KB(-1024);

#define BUF_W   512
#define SCR_W   480
#define SCR_H   272
#define PDS     1024.0f

static unsigned int __attribute__((aligned(16))) g_list[262144];

typedef struct { unsigned int color; float x, y, z; } Vtx;
#define VTX_MAX 4096
static Vtx __attribute__((aligned(16))) g_vtx[VTX_MAX];

static Machine g_machine;
static Demos   g_demos;

/* ---------- exit callback ---------- */
static int exit_callback(int arg1, int arg2, void *common) { sceKernelExitGame(); return 0; }
static int callback_thread(SceSize args, void *argp) {
    int cb = sceKernelCreateCallback("exit_cb", exit_callback, NULL);
    sceKernelRegisterExitCallback(cb);
    sceKernelSleepThreadCB();
    return 0;
}
static void setup_callbacks(void) {
    int thid = sceKernelCreateThread("cb_thread", callback_thread, 0x11, 0xFA0, PSP_THREAD_ATTR_USER, NULL);
    if (thid >= 0) sceKernelStartThread(thid, 0, NULL);
}

/* ---------- GU ---------- */
static void gu_setup(void) {
    sceGuInit();
    sceGuStart(GU_DIRECT, g_list);
    sceGuDrawBuffer(GU_PSM_8888, (void *)0, BUF_W);
    sceGuDispBuffer(SCR_W, SCR_H, (void *)0x88000, BUF_W);
    sceGuOffset(2048 - (SCR_W / 2), 2048 - (SCR_H / 2));
    sceGuViewport(2048, 2048, SCR_W, SCR_H);
    sceGuScissor(0, 0, SCR_W, SCR_H);
    sceGuEnable(GU_SCISSOR_TEST);
    sceGuDisable(GU_DEPTH_TEST);
    sceGuDisable(GU_TEXTURE_2D);
    sceGuShadeModel(GU_FLAT);
    sceGuFinish();
    sceGuSync(0, 0);
    sceDisplayWaitVblankStart();
    sceGuDisplay(GU_TRUE);
}

static inline unsigned int rgba(int r, int g, int b, int a) {
    if (a < 0) a = 0;
    if (a > 255) a = 255;
    return ((unsigned)a << 24) | ((unsigned)b << 16) | ((unsigned)g << 8) | (unsigned)r;
}

/* View mapping: PDS 1024x1024 -> screen. mode 0 = stretch (as on iOS), 1 = square. */
/* NOTE: PDS Y axis points UP (as in the iOS CGBitmapContext), so screen_y = g_oy - y*sy. */
static float g_sx, g_sy, g_ox, g_oy = (float)SCR_H;
static void set_view(int square) {
    if (square) { g_sx = g_sy = (float)SCR_H / PDS; g_ox = (SCR_W - SCR_H) * 0.5f; }
    else        { g_sx = (float)SCR_W / PDS; g_sy = (float)SCR_H / PDS; g_ox = 0.0f; }
}

static void flush_vtx(int n) {
    if (n <= 0) return;
    sceKernelDcacheWritebackRange(g_vtx, n * sizeof(Vtx));
    sceGuDrawArray(GU_LINES, GU_COLOR_8888 | GU_VERTEX_32BITF | GU_TRANSFORM_2D, n, NULL, g_vtx);
}

/* One pass over the display list with a pixel offset, colour and alpha scale. */
static void draw_pass(const Machine *m, float dx, float dy, int r, int g, int b, float alphaScale) {
    int n = 0;
    for (int i = 0; i < m->nvec; i++) {
        const MachineVec *v = &m->vecs[i];
        int a = (int)(v->bright * alphaScale * 255.0f + 0.5f);
        if (a < 3) continue;
        unsigned int col = rgba(r, g, b, a);
        float x1 = g_ox + v->x1 * g_sx + dx, y1 = g_oy - v->y1 * g_sy + dy;
        if (n + 4 > VTX_MAX) { flush_vtx(n); n = 0; }
        if (v->isPoint) {
            /* tiny cross */
            g_vtx[n++] = (Vtx){ col, x1 - 1.0f, y1, 0 }; g_vtx[n++] = (Vtx){ col, x1 + 1.0f, y1, 0 };
            g_vtx[n++] = (Vtx){ col, x1, y1 - 1.0f, 0 }; g_vtx[n++] = (Vtx){ col, x1, y1 + 1.0f, 0 };
        } else {
            float x2 = g_ox + v->x2 * g_sx + dx, y2 = g_oy - v->y2 * g_sy + dy;
            g_vtx[n++] = (Vtx){ col, x1, y1, 0 };
            g_vtx[n++] = (Vtx){ col, x2, y2, 0 };
        }
    }
    flush_vtx(n);
}

static void render(const Machine *m) {
    sceGuStart(GU_DIRECT, g_list);
    sceGuClearColor(0xFF000000);
    sceGuClear(GU_COLOR_BUFFER_BIT);

    sceGuEnable(GU_BLEND);
    sceGuBlendFunc(GU_ADD, GU_SRC_ALPHA, GU_FIX, 0, 0xFFFFFFFF); /* additive phosphor */

    if (m->nvec <= 2000) { /* glow only while the list is small enough to afford it */
        static const float o2[4][2] = {{-2,0},{2,0},{0,-2},{0,2}};
        static const float o1[4][2] = {{-1,0},{1,0},{0,-1},{0,1}};
        for (int k = 0; k < 4; k++) draw_pass(m, o2[k][0], o2[k][1], 0, 140, 35, 0.10f);
        for (int k = 0; k < 4; k++) draw_pass(m, o1[k][0], o1[k][1], 0, 200, 50, 0.22f);
    }
    draw_pass(m, 0, 0, 20, 255, 65, 1.0f); /* core */

    sceGuDisable(GU_BLEND);
    sceGuFinish();
    sceGuSync(0, 0);
}

/* ---------- main ---------- */
static const DemoType kOrder[] = {
    DEMO_STAR, DEMO_LISSAJOUS, DEMO_TEXT, DEMO_BOUNCE, DEMO_MAZE,
    DEMO_SPACEWAR, DEMO_SCOPE, DEMO_LINES, DEMO_MAZEWAR
};
#define N_ORDER ((int)(sizeof(kOrder) / sizeof(kOrder[0])))

int main(int argc, char *argv[]) {
    setup_callbacks();
    scePowerSetClockFrequency(333, 333, 166);

    machine_init(&g_machine);
    pds_srand((uint32_t)time(NULL) ^ 0x9E3779B9u);
    demos_init(&g_demos, &g_machine);

    gu_setup();
    set_view(0);

    sceCtrlSetSamplingCycle(0);
    sceCtrlSetSamplingMode(PSP_CTRL_MODE_ANALOG);

    int order = 0;           /* index into kOrder */
    int square = 0;
    int showHelp = 1;
    int hint = 180;          /* frames to show the demo title */
    SceCtrlData pad, old;
    memset(&old, 0, sizeof old);
    demos_set(&g_demos, kOrder[order]);

    for (;;) {
        sceCtrlPeekBufferPositive(&pad, 1);
        unsigned int pressed = pad.Buttons & ~old.Buttons;

        int change = 0;
        if (pressed & PSP_CTRL_RTRIGGER) { order = (order + 1) % N_ORDER; change = 1; }
        if (pressed & PSP_CTRL_LTRIGGER) { order = (order + N_ORDER - 1) % N_ORDER; change = 1; }
        if (change) { demos_set(&g_demos, kOrder[order]); hint = 180; }
        if (pressed & PSP_CTRL_SELECT) { square = !square; set_view(square); }
        if (pressed & PSP_CTRL_START)  { showHelp = !showHelp; hint = showHelp ? 180 : 0; }

        /* Maze War input (held states; the game does its own edge detection) */
        if (g_demos.current == DEMO_MAZEWAR) {
            MazeWar *mw = &g_demos.mazeWar;
            int lx = pad.Lx, ly = pad.Ly;
            if (pad.Buttons & PSP_CTRL_UP    || ly < 64)  mw->iUp = 1;
            if (pad.Buttons & PSP_CTRL_DOWN  || ly > 192) mw->iDown = 1;
            if (pad.Buttons & PSP_CTRL_LEFT  || lx < 64)  mw->iLeft = 1;
            if (pad.Buttons & PSP_CTRL_RIGHT || lx > 192) mw->iRight = 1;
            if (pad.Buttons & (PSP_CTRL_CROSS | PSP_CTRL_SQUARE | PSP_CTRL_CIRCLE)) mw->iFire = 1;
            if (pressed & PSP_CTRL_TRIANGLE) mazewar_start_single(mw);
        }

        /* machine: MP/DP only run when the MP is started (idle by default, as on iOS) */
        machine_dl_clear(&g_machine);
        if (g_machine.mp_run) {
            for (int i = 0; i < 6600; i++) machine_mp_step(&g_machine);
            for (int i = 0; i < 1650; i++) machine_dp_step(&g_machine);
        }
        demos_run(&g_demos);

        if (hint > 0) {
            hint--;
            float b = hint > 30 ? 0.7f : (float)hint / 30.0f * 0.7f;
            font_text(&g_machine, demos_name(g_demos.current), 10, 960, 8, b);
            if (showHelp)
                font_text(&g_machine, "L R DEMO  SELECT ASPECT  START HELP", 10, 12, 5, b * 0.7f);
        }

        render(&g_machine);

        old = pad;
        sceDisplayWaitVblankStart();   /* 30 fps: two vblanks per frame (demos are tuned for 30) */
        sceDisplayWaitVblankStart();
        sceGuSwapBuffers();
    }
    return 0;
}
