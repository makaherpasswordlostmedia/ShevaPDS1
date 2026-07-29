// ui_widgets.c
//
// Immediate-mode UI drawn with raw GLES2 quads/lines + a tiny embedded
// 5x7 bitmap font (no external UI library — keeps the native build
// dependency-free besides SDL2 itself). Replaces activity_emulator.xml's
// Android Views:
//
//   Top-left:    PWR / RESET / RUN / HALT / STEP buttons + register readout
//   Bottom-left: dpad (Up/Down/Left/Right) + A/B/C/D action buttons
//   Right side:  demo/game picker list, "Load file" button
//   Bottom-right (toggle): multiplayer panel — Host/Join/Stop, chat log,
//                on-screen keyboard for chat text entry
//
// Layout uses simple fixed pixel regions scaled to the current drawable
// size, good enough for a landscape-locked tablet/phone screen (matches
// the original app's android:screenOrientation="landscape" lock).
//
// All widget actions call straight into EmulatorBridge via JNI (same
// pattern as input_bridge.c) — this file owns its own small set of
// method IDs for the calls it needs that input_bridge.c doesn't already
// expose (selectDemo, runGameByName, power/reset/run/halt/step,
// netHost/netJoin/netStop/netSendChat, requestOpenFile, register reads).

#include "ui_widgets.h"

#include <SDL.h>
#if defined(__ANDROID__)
#include <GLES2/gl2.h>
#else
#include <SDL_opengles2.h>
#endif
#include <jni.h>

#include <stdlib.h>
#include <string.h>
#include <stdio.h>

// ── Tiny embedded font (3x5, monospace, digits+uppercase+punct subset) ──
// Stored as a bit-packed 15-bit glyph per char (3 cols x 5 rows), enough
// for labels/readouts. Not meant to be pretty — functional HUD text.
#include "ui_font.h"

#define MAX_BUTTONS 32
#define MAX_CHAT_LINES 64
#define CHAT_LINE_LEN 96

typedef struct {
    SDL_FRect rect;      // in window pixel coords
    const char *label;
    int id;              // widget id, dispatched in ui_dispatch_action()
    bool visible;
    bool held;            // for momentary buttons (dpad) that need press+release
} UiButton;

enum {
    ACT_NONE = 0,
    ACT_PWR, ACT_RESET, ACT_RUN, ACT_HALT, ACT_STEP,
    ACT_UP, ACT_DOWN, ACT_LEFT, ACT_RIGHT, ACT_A, ACT_B, ACT_C, ACT_D,
    ACT_LOAD_FILE,
    ACT_DEMO_BASE = 1000,   // + demo index
    ACT_GAME_BASE = 2000,   // + game index (into last-fetched list)
    ACT_NET_HOST = 3000, ACT_NET_JOIN, ACT_NET_STOP, ACT_NET_TOGGLE,
    ACT_CHAT_SEND, ACT_CHAT_BACKSPACE,
    ACT_KEY_BASE = 4000,    // + ascii code, on-screen keyboard keys
};

struct UiContext {
    int winW, winH;

    UiButton buttons[MAX_BUTTONS];
    int nButtons;

    bool netPanelOpen;
    bool keyboardOpen;
    char chatInput[CHAT_LINE_LEN];
    int  chatInputLen;

    // JNI method IDs for actions this file drives directly (beyond what
    // input_bridge.c already exposes for pumpFrame/setLightPen/key*).
    jclass    bridgeClass;
    jmethodID midPowerOn, midReset, midRun, midHalt, midStep, midIsHalted;
    jmethodID midSelectDemo, midDemoNames;
    jmethodID midGameNames, midRunGameByName, midRequestOpenFile;
    jmethodID midNetHost, midNetJoin, midNetStop, midNetSendChat, midNetStatusText, midNetIsConnected;
    jmethodID midRegPC, midRegAC, midRegIR, midRegLink, midRegDPX, midRegDPY;
    jmethodID midSetControllerState;

    // GL immediate-mode drawing state (shared tiny shader for solid quads
    // and font glyphs alike — glyphs are just many small quads).
    GLuint prog;
    GLint  aPos, uColor;
};

// ── GL solid-color quad shader (separate from crt_renderer's, since UI
//    quads don't need per-vertex color — one uniform color per draw call
//    keeps this dead simple) ────────────────────────────────────────────

static const char *UI_VERT_SRC =
    "attribute vec2 aPos;\n"
    "void main() { gl_Position = vec4(aPos, 0.0, 1.0); }\n";

static const char *UI_FRAG_SRC =
    "precision mediump float;\n"
    "uniform vec4 uColor;\n"
    "void main() { gl_FragColor = uColor; }\n";

static GLuint ui_compile(GLenum type, const char *src) {
    GLuint s = glCreateShader(type);
    glShaderSource(s, 1, &src, NULL);
    glCompileShader(s);
    return s;
}

static void px_to_ndc(int winW, int winH, float px, float py, float *nx, float *ny) {
    *nx = (px / (float)winW) * 2.0f - 1.0f;
    *ny = 1.0f - (py / (float)winH) * 2.0f;
}

static void ui_draw_rect(UiContext *ui, SDL_FRect r, float cr, float cg, float cb, float ca) {
    float x0, y0, x1, y1;
    px_to_ndc(ui->winW, ui->winH, r.x, r.y, &x0, &y0);
    px_to_ndc(ui->winW, ui->winH, r.x + r.w, r.y + r.h, &x1, &y1);
    float verts[8] = { x0, y0, x1, y0, x0, y1, x1, y1 };

    glUseProgram(ui->prog);
    glUniform4f(ui->uColor, cr, cg, cb, ca);
    glEnableVertexAttribArray((GLuint)ui->aPos);
    glVertexAttribPointer((GLuint)ui->aPos, 2, GL_FLOAT, GL_FALSE, 0, verts);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    glDisableVertexAttribArray((GLuint)ui->aPos);
}

static void ui_draw_rect_outline(UiContext *ui, SDL_FRect r, float cr, float cg, float cb, float ca) {
    float x0, y0, x1, y1;
    px_to_ndc(ui->winW, ui->winH, r.x, r.y, &x0, &y0);
    px_to_ndc(ui->winW, ui->winH, r.x + r.w, r.y + r.h, &x1, &y1);
    float verts[10] = { x0,y0, x1,y0, x1,y1, x0,y1, x0,y0 };

    glUseProgram(ui->prog);
    glUniform4f(ui->uColor, cr, cg, cb, ca);
    glEnableVertexAttribArray((GLuint)ui->aPos);
    glVertexAttribPointer((GLuint)ui->aPos, 2, GL_FLOAT, GL_FALSE, 0, verts);
    glDrawArrays(GL_LINE_STRIP, 0, 5);
    glDisableVertexAttribArray((GLuint)ui->aPos);
}

static void ui_draw_text(UiContext *ui, float x, float y, float scale,
                          const char *text, float cr, float cg, float cb) {
    float cursorX = x;
    for (const char *p = text; *p; p++) {
        const uint8_t *glyph = ui_font_glyph(*p);
        if (glyph) {
            for (int row = 0; row < UI_GLYPH_H; row++) {
                for (int col = 0; col < UI_GLYPH_W; col++) {
                    if (glyph[row] & (1 << (UI_GLYPH_W - 1 - col))) {
                        SDL_FRect px = {
                            cursorX + col * scale, y + row * scale, scale, scale
                        };
                        ui_draw_rect(ui, px, cr, cg, cb, 1.0f);
                    }
                }
            }
        }
        cursorX += (UI_GLYPH_W + 1) * scale;
    }
}

static void ui_draw_button(UiContext *ui, const UiButton *b, bool active) {
    if (!b->visible) return;
    float bg = active ? 0.25f : 0.12f;
    ui_draw_rect(ui, b->rect, bg, bg * 1.3f, bg, 0.85f);
    ui_draw_rect_outline(ui, b->rect, 0.2f, 0.9f, 0.3f, 0.9f);
    ui_draw_text(ui, b->rect.x + 6, b->rect.y + b->rect.h / 2 - 3, 2.0f,
                 b->label, 0.2f, 1.0f, 0.3f);
}

// ── JNI setup ────────────────────────────────────────────────────────────

static JNIEnv *ui_env(void) { return (JNIEnv *)SDL_AndroidGetJNIEnv(); }

static void ui_jni_init(UiContext *ui) {
    JNIEnv *env = ui_env();
    if (!env) return;

    jclass local = (*env)->FindClass(env, "com/imlac/pds1/EmulatorBridge");
    if (!local) return;
    ui->bridgeClass = (jclass)(*env)->NewGlobalRef(env, local);
    (*env)->DeleteLocalRef(env, local);

    jclass c = ui->bridgeClass;
    ui->midPowerOn      = (*env)->GetStaticMethodID(env, c, "powerOn", "()V");
    ui->midReset        = (*env)->GetStaticMethodID(env, c, "reset", "()V");
    ui->midRun          = (*env)->GetStaticMethodID(env, c, "run", "()V");
    ui->midHalt         = (*env)->GetStaticMethodID(env, c, "halt", "()V");
    ui->midStep         = (*env)->GetStaticMethodID(env, c, "step", "()V");
    ui->midIsHalted     = (*env)->GetStaticMethodID(env, c, "isHalted", "()Z");
    ui->midSelectDemo   = (*env)->GetStaticMethodID(env, c, "selectDemo", "(I)V");
    ui->midDemoNames    = (*env)->GetStaticMethodID(env, c, "demoNames", "()[Ljava/lang/String;");
    ui->midGameNames    = (*env)->GetStaticMethodID(env, c, "gameNames", "()[Ljava/lang/String;");
    ui->midRunGameByName= (*env)->GetStaticMethodID(env, c, "runGameByName", "(Ljava/lang/String;)V");
    ui->midRequestOpenFile = (*env)->GetStaticMethodID(env, c, "requestOpenFile", "()V");
    ui->midNetHost      = (*env)->GetStaticMethodID(env, c, "netHost", "()V");
    ui->midNetJoin      = (*env)->GetStaticMethodID(env, c, "netJoin", "()V");
    ui->midNetStop      = (*env)->GetStaticMethodID(env, c, "netStop", "()V");
    ui->midNetSendChat  = (*env)->GetStaticMethodID(env, c, "netSendChat", "(Ljava/lang/String;)V");
    ui->midNetStatusText= (*env)->GetStaticMethodID(env, c, "netStatusText", "()Ljava/lang/String;");
    ui->midNetIsConnected = (*env)->GetStaticMethodID(env, c, "netIsConnected", "()Z");
    ui->midRegPC   = (*env)->GetStaticMethodID(env, c, "regPC", "()I");
    ui->midRegAC   = (*env)->GetStaticMethodID(env, c, "regAC", "()I");
    ui->midRegIR   = (*env)->GetStaticMethodID(env, c, "regIR", "()I");
    ui->midRegLink = (*env)->GetStaticMethodID(env, c, "regLink", "()I");
    ui->midRegDPX  = (*env)->GetStaticMethodID(env, c, "regDPX", "()I");
    ui->midRegDPY  = (*env)->GetStaticMethodID(env, c, "regDPY", "()I");
    ui->midSetControllerState = (*env)->GetStaticMethodID(env, c, "setControllerState", "(ZZZZZZZZ)V");
}

// ── Layout construction ──────────────────────────────────────────────────

static UiButton *ui_add_button(UiContext *ui, SDL_FRect r, const char *label, int id) {
    if (ui->nButtons >= MAX_BUTTONS) return NULL;
    UiButton *b = &ui->buttons[ui->nButtons++];
    b->rect = r; b->label = label; b->id = id; b->visible = true; b->held = false;
    return b;
}

static void ui_build_layout(UiContext *ui) {
    ui->nButtons = 0;

    // Control panel, top-left.
    float x = 8, y = 8, w = 64, h = 28, gap = 4;
    ui_add_button(ui, (SDL_FRect){x, y, w, h}, "PWR",   ACT_PWR);
    ui_add_button(ui, (SDL_FRect){x + (w+gap)*1, y, w, h}, "RESET", ACT_RESET);
    ui_add_button(ui, (SDL_FRect){x + (w+gap)*2, y, w, h}, "RUN",   ACT_RUN);
    ui_add_button(ui, (SDL_FRect){x + (w+gap)*3, y, w, h}, "HALT",  ACT_HALT);
    ui_add_button(ui, (SDL_FRect){x + (w+gap)*4, y, w, h}, "STEP",  ACT_STEP);
    ui_add_button(ui, (SDL_FRect){x + (w+gap)*5, y, w, h}, "LOAD",  ACT_LOAD_FILE);
    ui_add_button(ui, (SDL_FRect){x + (w+gap)*6, y, w+20, h}, "NET",   ACT_NET_TOGGLE);

    // Dpad, bottom-left.
    float dx = 20, dy = ui->winH - 140, dw = 44, dh = 40;
    ui_add_button(ui, (SDL_FRect){dx + dw, dy,          dw, dh}, "^", ACT_UP);
    ui_add_button(ui, (SDL_FRect){dx + dw, dy + dh * 2,  dw, dh}, "v", ACT_DOWN);
    ui_add_button(ui, (SDL_FRect){dx,      dy + dh,      dw, dh}, "<", ACT_LEFT);
    ui_add_button(ui, (SDL_FRect){dx + dw*2, dy + dh,    dw, dh}, ">", ACT_RIGHT);

    // Action buttons, bottom-right of dpad.
    float ax = dx + dw * 3 + 20, ay = dy + dh;
    ui_add_button(ui, (SDL_FRect){ax,      ay,      44, 40}, "A", ACT_A);
    ui_add_button(ui, (SDL_FRect){ax + 50, ay,      44, 40}, "B", ACT_B);
    ui_add_button(ui, (SDL_FRect){ax,      ay + 46, 44, 40}, "C", ACT_C);
    ui_add_button(ui, (SDL_FRect){ax + 50, ay + 46, 44, 40}, "D", ACT_D);

    // Net panel controls (visibility toggled by netPanelOpen).
    float nx = ui->winW - 220, ny = 46;
    UiButton *host = ui_add_button(ui, (SDL_FRect){nx, ny, 66, 26}, "HOST", ACT_NET_HOST);
    UiButton *join = ui_add_button(ui, (SDL_FRect){nx + 72, ny, 66, 26}, "JOIN", ACT_NET_JOIN);
    UiButton *stop = ui_add_button(ui, (SDL_FRect){nx + 144, ny, 66, 26}, "STOP", ACT_NET_STOP);
    host->visible = join->visible = stop->visible = ui->netPanelOpen;
}

// ── Public API ─────────────────────────────────────────────────────────

UiContext *ui_create(int width_px, int height_px) {
    UiContext *ui = (UiContext *)calloc(1, sizeof(UiContext));
    if (!ui) return NULL;
    ui->winW = width_px > 0 ? width_px : 1;
    ui->winH = height_px > 0 ? height_px : 1;

    GLuint vs = ui_compile(GL_VERTEX_SHADER, UI_VERT_SRC);
    GLuint fs = ui_compile(GL_FRAGMENT_SHADER, UI_FRAG_SRC);
    ui->prog = glCreateProgram();
    glAttachShader(ui->prog, vs);
    glAttachShader(ui->prog, fs);
    glLinkProgram(ui->prog);
    glDeleteShader(vs);
    glDeleteShader(fs);
    ui->aPos = glGetAttribLocation(ui->prog, "aPos");
    ui->uColor = glGetUniformLocation(ui->prog, "uColor");

    ui_jni_init(ui);
    ui_build_layout(ui);
    return ui;
}

void ui_destroy(UiContext *ui) {
    if (!ui) return;
    if (ui->prog) glDeleteProgram(ui->prog);
    if (ui->bridgeClass) {
        JNIEnv *env = ui_env();
        if (env) (*env)->DeleteGlobalRef(env, ui->bridgeClass);
    }
    free(ui);
}

void ui_resize(UiContext *ui, int width_px, int height_px) {
    if (!ui) return;
    ui->winW = width_px > 0 ? width_px : 1;
    ui->winH = height_px > 0 ? height_px : 1;
    ui_build_layout(ui);
}

// ── Action dispatch ───────────────────────────────────────────────────

static void ui_dispatch_action(UiContext *ui, int id) {
    JNIEnv *env = ui_env();
    if (!env || !ui->bridgeClass) return;
    jclass c = ui->bridgeClass;

    switch (id) {
        case ACT_PWR:   (*env)->CallStaticVoidMethod(env, c, ui->midPowerOn); break;
        case ACT_RESET: (*env)->CallStaticVoidMethod(env, c, ui->midReset); break;
        case ACT_RUN:   (*env)->CallStaticVoidMethod(env, c, ui->midRun); break;
        case ACT_HALT:  (*env)->CallStaticVoidMethod(env, c, ui->midHalt); break;
        case ACT_STEP:  (*env)->CallStaticVoidMethod(env, c, ui->midStep); break;
        case ACT_LOAD_FILE: (*env)->CallStaticVoidMethod(env, c, ui->midRequestOpenFile); break;
        case ACT_NET_TOGGLE:
            ui->netPanelOpen = !ui->netPanelOpen;
            ui_build_layout(ui);
            break;
        case ACT_NET_HOST: (*env)->CallStaticVoidMethod(env, c, ui->midNetHost); break;
        case ACT_NET_JOIN: (*env)->CallStaticVoidMethod(env, c, ui->midNetJoin); break;
        case ACT_NET_STOP: (*env)->CallStaticVoidMethod(env, c, ui->midNetStop); break;
        default: break;
    }
}

// dpad/action buttons are held-state, not one-shot; controller state is
// pushed to EmulatorBridge.setControllerState() every frame from ui_draw()
// based on ui->buttons[*].held, so no per-event dispatch needed for those.

bool ui_handle_event(UiContext *ui, const SDL_Event *ev) {
    if (!ui) return false;

    float ex = 0, ey = 0;
    bool isDown = false, isUp = false;

    if (ev->type == SDL_FINGERDOWN || ev->type == SDL_FINGERUP) {
        ex = ev->tfinger.x * ui->winW;
        ey = ev->tfinger.y * ui->winH;
        isDown = (ev->type == SDL_FINGERDOWN);
        isUp   = (ev->type == SDL_FINGERUP);
    } else if (ev->type == SDL_MOUSEBUTTONDOWN || ev->type == SDL_MOUSEBUTTONUP) {
        ex = (float)ev->button.x;
        ey = (float)ev->button.y;
        isDown = (ev->type == SDL_MOUSEBUTTONDOWN);
        isUp   = (ev->type == SDL_MOUSEBUTTONUP);
    } else {
        return false;
    }

    for (int i = 0; i < ui->nButtons; i++) {
        UiButton *b = &ui->buttons[i];
        if (!b->visible) continue;
        bool inside = ex >= b->rect.x && ex <= b->rect.x + b->rect.w &&
                      ey >= b->rect.y && ey <= b->rect.y + b->rect.h;
        if (inside && isDown) {
            b->held = true;
            if (b->id < ACT_UP || b->id > ACT_D) {
                // Momentary command buttons fire once on press.
                ui_dispatch_action(ui, b->id);
            }
            return true;
        }
        if (isUp && b->held) {
            b->held = false;
            return true;
        }
    }
    return false;
}

static void ui_push_controller_state(UiContext *ui) {
    JNIEnv *env = ui_env();
    if (!env || !ui->bridgeClass) return;

    bool up=false, down=false, left=false, right=false, a=false, b=false, c=false, d=false;
    for (int i = 0; i < ui->nButtons; i++) {
        UiButton *btn = &ui->buttons[i];
        if (!btn->held) continue;
        switch (btn->id) {
            case ACT_UP: up = true; break;
            case ACT_DOWN: down = true; break;
            case ACT_LEFT: left = true; break;
            case ACT_RIGHT: right = true; break;
            case ACT_A: a = true; break;
            case ACT_B: b = true; break;
            case ACT_C: c = true; break;
            case ACT_D: d = true; break;
            default: break;
        }
    }
    (*env)->CallStaticVoidMethod(env, ui->bridgeClass, ui->midSetControllerState,
                                  (jboolean)up, (jboolean)down, (jboolean)left, (jboolean)right,
                                  (jboolean)a, (jboolean)b, (jboolean)c, (jboolean)d);
}

static void ui_draw_registers(UiContext *ui) {
    JNIEnv *env = ui_env();
    if (!env || !ui->bridgeClass) return;

    jint pc = (*env)->CallStaticIntMethod(env, ui->bridgeClass, ui->midRegPC);
    jint ac = (*env)->CallStaticIntMethod(env, ui->bridgeClass, ui->midRegAC);
    jint ir = (*env)->CallStaticIntMethod(env, ui->bridgeClass, ui->midRegIR);
    jint lk = (*env)->CallStaticIntMethod(env, ui->bridgeClass, ui->midRegLink);
    jint dx = (*env)->CallStaticIntMethod(env, ui->bridgeClass, ui->midRegDPX);
    jint dy = (*env)->CallStaticIntMethod(env, ui->bridgeClass, ui->midRegDPY);
    jboolean halted = (*env)->CallStaticBooleanMethod(env, ui->bridgeClass, ui->midIsHalted);

    char line[128];
    snprintf(line, sizeof(line), "PC:%04o AC:%06o IR:%04o LK:%d DPX:%d DPY:%d %s",
             pc & 07777, ac & 0177777, ir & 07777, lk, dx, dy,
             halted ? "HALT" : "RUN");
    ui_draw_text(ui, 8, 44, 2.0f, line, 0.9f, 0.9f, 0.2f);
}

static void ui_draw_net_panel(UiContext *ui) {
    if (!ui->netPanelOpen) return;
    JNIEnv *env = ui_env();
    if (!env || !ui->bridgeClass) return;

    jstring jstatus = (jstring)(*env)->CallStaticObjectMethod(env, ui->bridgeClass, ui->midNetStatusText);
    if (jstatus) {
        const char *status = (*env)->GetStringUTFChars(env, jstatus, NULL);
        ui_draw_text(ui, ui->winW - 220, 78, 1.6f, status, 0.6f, 0.8f, 1.0f);
        (*env)->ReleaseStringUTFChars(env, jstatus, status);
        (*env)->DeleteLocalRef(env, jstatus);
    }
}

void ui_draw(UiContext *ui, CrtRenderer *crt) {
    (void)crt;
    if (!ui) return;

    glDisable(GL_DEPTH_TEST);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    for (int i = 0; i < ui->nButtons; i++) {
        ui_draw_button(ui, &ui->buttons[i], ui->buttons[i].held);
    }

    ui_draw_registers(ui);
    ui_draw_net_panel(ui);
    ui_push_controller_state(ui);
}
