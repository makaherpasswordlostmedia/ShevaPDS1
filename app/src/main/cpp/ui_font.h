// ui_font.h
//
// Tiny embedded 3x5 bitmap font, digits + uppercase + a handful of
// punctuation marks — just enough for HUD labels and register readouts.
// Each glyph is 5 rows, each row using the low 3 bits (col 0 = MSB of
// those 3 bits) to mark filled pixels. Intentionally blocky; this is a
// diagnostic HUD font, not a pretty one.

#ifndef UI_FONT_HEADER_GUARD_H
#define UI_FONT_HEADER_GUARD_H

#include <stdint.h>

#define UI_GLYPH_W 3
#define UI_GLYPH_H 5

// clang-format off
static const uint8_t UI_FONT_0[5] = {0b111,0b101,0b101,0b101,0b111};
static const uint8_t UI_FONT_1[5] = {0b010,0b110,0b010,0b010,0b111};
static const uint8_t UI_FONT_2[5] = {0b111,0b001,0b111,0b100,0b111};
static const uint8_t UI_FONT_3[5] = {0b111,0b001,0b111,0b001,0b111};
static const uint8_t UI_FONT_4[5] = {0b101,0b101,0b111,0b001,0b001};
static const uint8_t UI_FONT_5[5] = {0b111,0b100,0b111,0b001,0b111};
static const uint8_t UI_FONT_6[5] = {0b111,0b100,0b111,0b101,0b111};
static const uint8_t UI_FONT_7[5] = {0b111,0b001,0b010,0b010,0b010};
static const uint8_t UI_FONT_8[5] = {0b111,0b101,0b111,0b101,0b111};
static const uint8_t UI_FONT_9[5] = {0b111,0b101,0b111,0b001,0b111};

static const uint8_t UI_FONT_A[5] = {0b111,0b101,0b111,0b101,0b101};
static const uint8_t UI_FONT_B[5] = {0b110,0b101,0b110,0b101,0b110};
static const uint8_t UI_FONT_C[5] = {0b111,0b100,0b100,0b100,0b111};
static const uint8_t UI_FONT_D[5] = {0b110,0b101,0b101,0b101,0b110};
static const uint8_t UI_FONT_E[5] = {0b111,0b100,0b111,0b100,0b111};
static const uint8_t UI_FONT_F[5] = {0b111,0b100,0b111,0b100,0b100};
static const uint8_t UI_FONT_G[5] = {0b111,0b100,0b101,0b101,0b111};
static const uint8_t UI_FONT_H[5] = {0b101,0b101,0b111,0b101,0b101};
static const uint8_t UI_FONT_I[5] = {0b111,0b010,0b010,0b010,0b111};
static const uint8_t UI_FONT_J[5] = {0b001,0b001,0b001,0b101,0b111};
static const uint8_t UI_FONT_K[5] = {0b101,0b101,0b110,0b101,0b101};
static const uint8_t UI_FONT_L[5] = {0b100,0b100,0b100,0b100,0b111};
static const uint8_t UI_FONT_M[5] = {0b101,0b111,0b111,0b101,0b101};
static const uint8_t UI_FONT_N[5] = {0b101,0b111,0b111,0b111,0b101};
static const uint8_t UI_FONT_O[5] = {0b111,0b101,0b101,0b101,0b111};
static const uint8_t UI_FONT_P[5] = {0b111,0b101,0b111,0b100,0b100};
static const uint8_t UI_FONT_Q[5] = {0b111,0b101,0b101,0b111,0b001};
static const uint8_t UI_FONT_R[5] = {0b111,0b101,0b110,0b101,0b101};
static const uint8_t UI_FONT_S[5] = {0b111,0b100,0b111,0b001,0b111};
static const uint8_t UI_FONT_T[5] = {0b111,0b010,0b010,0b010,0b010};
static const uint8_t UI_FONT_U[5] = {0b101,0b101,0b101,0b101,0b111};
static const uint8_t UI_FONT_V[5] = {0b101,0b101,0b101,0b101,0b010};
static const uint8_t UI_FONT_W[5] = {0b101,0b101,0b111,0b111,0b101};
static const uint8_t UI_FONT_X[5] = {0b101,0b101,0b010,0b101,0b101};
static const uint8_t UI_FONT_Y[5] = {0b101,0b101,0b010,0b010,0b010};
static const uint8_t UI_FONT_Z[5] = {0b111,0b001,0b010,0b100,0b111};

static const uint8_t UI_FONT_COLON[5]  = {0b000,0b010,0b000,0b010,0b000};
static const uint8_t UI_FONT_DASH[5]   = {0b000,0b000,0b111,0b000,0b000};
static const uint8_t UI_FONT_DOT[5]    = {0b000,0b000,0b000,0b000,0b010};
static const uint8_t UI_FONT_SLASH[5]  = {0b001,0b001,0b010,0b100,0b100};
static const uint8_t UI_FONT_CARET[5]  = {0b010,0b101,0b000,0b000,0b000};
static const uint8_t UI_FONT_LT[5]     = {0b001,0b010,0b100,0b010,0b001};
static const uint8_t UI_FONT_GT[5]     = {0b100,0b010,0b001,0b010,0b100};
static const uint8_t UI_FONT_SPACE[5]  = {0,0,0,0,0};
// clang-format on

static inline const uint8_t *ui_font_glyph(char ch) {
    if (ch >= '0' && ch <= '9') {
        static const uint8_t *digits[10] = {
            UI_FONT_0, UI_FONT_1, UI_FONT_2, UI_FONT_3, UI_FONT_4,
            UI_FONT_5, UI_FONT_6, UI_FONT_7, UI_FONT_8, UI_FONT_9
        };
        return digits[ch - '0'];
    }
    if (ch >= 'a' && ch <= 'z') ch = (char)(ch - 'a' + 'A');
    if (ch >= 'A' && ch <= 'Z') {
        static const uint8_t *letters[26] = {
            UI_FONT_A, UI_FONT_B, UI_FONT_C, UI_FONT_D, UI_FONT_E, UI_FONT_F,
            UI_FONT_G, UI_FONT_H, UI_FONT_I, UI_FONT_J, UI_FONT_K, UI_FONT_L,
            UI_FONT_M, UI_FONT_N, UI_FONT_O, UI_FONT_P, UI_FONT_Q, UI_FONT_R,
            UI_FONT_S, UI_FONT_T, UI_FONT_U, UI_FONT_V, UI_FONT_W, UI_FONT_X,
            UI_FONT_Y, UI_FONT_Z
        };
        return letters[ch - 'A'];
    }
    switch (ch) {
        case ':': return UI_FONT_COLON;
        case '-': return UI_FONT_DASH;
        case '.': return UI_FONT_DOT;
        case '/': return UI_FONT_SLASH;
        case '^': return UI_FONT_CARET;
        case '<': return UI_FONT_LT;
        case '>': return UI_FONT_GT;
        case ' ': return UI_FONT_SPACE;
        default:  return UI_FONT_SPACE;
    }
}

#endif // UI_FONT_HEADER_GUARD_H
