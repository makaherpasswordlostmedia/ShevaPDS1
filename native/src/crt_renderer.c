// crt_renderer.c
//
// SDL2 + OpenGL ES2 implementation of the PDS-1 vector CRT renderer.
// Direct port of CrtView.java's GLES20 renderer:
//   - same vertex/fragment shaders (brightness carried as vertex alpha)
//   - same two-batched-draw-calls-per-frame approach (lines, then points)
//   - same phosphor-green tint (r=0.1*br, g=1.0*br, b=0.3*br)
//   - same NDC mapping: PDS (0..1023) -> (-1..1), Y not flipped here
//     (CrtView did the same: y1 = vy1*scaleY - 1, no flip — the emulator's
//     Y already increases upward in device space, consistent with GL NDC).
//
// Uses GLES2 entry points so the same source builds against desktop GL
// (via SDL2's GL loader / any GLES-compatible profile) and against
// Android's built-in GLES2 library.

#include "crt_renderer.h"

#include <SDL.h>
#if defined(__ANDROID__) || defined(SDL_VIDEO_DRIVER_ANDROID)
#include <GLES2/gl2.h>
#else
#include <SDL_opengles2.h>
#endif

#include <stdlib.h>
#include <string.h>
#include <math.h>

#define PDS 1024
#define MAX_VERTS 65536

// Vertex shader — passes brightness as alpha (identical to CrtView.VERT_SRC)
static const char *VERT_SRC =
    "attribute vec2 aPos;\n"
    "attribute vec4 aColor;\n"
    "varying vec4 vColor;\n"
    "void main() {\n"
    "  gl_Position = vec4(aPos, 0.0, 1.0);\n"
    "  gl_PointSize = 3.0;\n"
    "  vColor = aColor;\n"
    "}\n";

// Fragment shader — simple phosphor green tint (identical to CrtView.FRAG_SRC)
static const char *FRAG_SRC =
    "precision mediump float;\n"
    "varying vec4 vColor;\n"
    "void main() {\n"
    "  gl_FragColor = vColor;\n"
    "}\n";

struct CrtRenderer {
    GLuint prog;
    GLint  aPos, aColor;

    // Per-frame CPU-side buffers, pre-allocated (mirrors CrtView's
    // lineBuf/lineCol/ptBuf/ptCol — zero per-frame heap allocation).
    float lineBuf[MAX_VERTS];
    float lineCol[MAX_VERTS * 2];
    float ptBuf[MAX_VERTS / 4];
    float ptCol[MAX_VERTS / 2];
    int nLine, nPt;

    int surfW, surfH;

    int   maxFps;
    float fpsActual;
    Uint64 fpsTime;   // in SDL_GetPerformanceCounter() ticks
    int    fpsCnt;
    Uint64 frameStart; // ticks at crt_renderer_frame_begin()
};

// ── GL utilities ────────────────────────────────────────────────────────

static GLuint compile_shader(GLenum type, const char *src) {
    GLuint s = glCreateShader(type);
    glShaderSource(s, 1, &src, NULL);
    glCompileShader(s);
#ifndef NDEBUG
    GLint ok = 0;
    glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char log[512];
        glGetShaderInfoLog(s, sizeof(log), NULL, log);
        SDL_LogError(SDL_LOG_CATEGORY_RENDER, "CRT shader compile error: %s", log);
    }
#endif
    return s;
}

static GLuint build_program(const char *vs_src, const char *fs_src) {
    GLuint vs = compile_shader(GL_VERTEX_SHADER, vs_src);
    GLuint fs = compile_shader(GL_FRAGMENT_SHADER, fs_src);
    GLuint p = glCreateProgram();
    glAttachShader(p, vs);
    glAttachShader(p, fs);
    glLinkProgram(p);
#ifndef NDEBUG
    GLint ok = 0;
    glGetProgramiv(p, GL_LINK_STATUS, &ok);
    if (!ok) {
        char log[512];
        glGetProgramInfoLog(p, sizeof(log), NULL, log);
        SDL_LogError(SDL_LOG_CATEGORY_RENDER, "CRT program link error: %s", log);
    }
#endif
    // Shaders are refcounted by the program once linked; safe to delete here.
    glDeleteShader(vs);
    glDeleteShader(fs);
    return p;
}

// ── Lifecycle ───────────────────────────────────────────────────────────

CrtRenderer *crt_renderer_create(void) {
    CrtRenderer *r = (CrtRenderer *)calloc(1, sizeof(CrtRenderer));
    if (!r) return NULL;

    r->prog = build_program(VERT_SRC, FRAG_SRC);
    r->aPos   = glGetAttribLocation(r->prog, "aPos");
    r->aColor = glGetAttribLocation(r->prog, "aColor");

    r->surfW = 1;
    r->surfH = 1;
    r->maxFps = 30;
    r->fpsActual = 0.0f;
    r->fpsTime = SDL_GetPerformanceCounter();
    r->fpsCnt = 0;

    glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    return r;
}

void crt_renderer_destroy(CrtRenderer *r) {
    if (!r) return;
    if (r->prog) glDeleteProgram(r->prog);
    free(r);
}

void crt_renderer_resize(CrtRenderer *r, int width_px, int height_px) {
    if (!r) return;
    if (width_px  < 1) width_px  = 1;
    if (height_px < 1) height_px = 1;
    r->surfW = width_px;
    r->surfH = height_px;
    glViewport(0, 0, width_px, height_px);
}

// ── Vector submission (mirrors CrtView.buildBuffers()) ────────────────────

void crt_renderer_submit_vectors(CrtRenderer *r, const CrtVector *vectors, int count) {
    if (!r) return;

    r->nLine = 0;
    r->nPt   = 0;

    const float scaleX = 2.0f / PDS;
    const float scaleY = 2.0f / PDS;

    for (int i = 0; i < count; i++) {
        const CrtVector *v = &vectors[i];
        if (v->brightness < 10) continue;

        float brf = v->brightness / 255.0f;
        // Phosphor green core: bright green (same weights as CrtView.java)
        float rr = 0.1f * brf, gg = 1.0f * brf, bb = 0.3f * brf, aa = brf;

        float x1 = v->x1 * scaleX - 1.0f;
        float y1 = v->y1 * scaleY - 1.0f;

        if (v->is_point) {
            if (r->nPt + 2 < (int)(sizeof(r->ptBuf) / sizeof(r->ptBuf[0]))) {
                r->ptBuf[r->nPt]     = x1;
                r->ptBuf[r->nPt + 1] = y1;
                r->ptCol[r->nPt * 2]     = rr;
                r->ptCol[r->nPt * 2 + 1] = gg;
                r->ptCol[r->nPt * 2 + 2] = bb;
                r->ptCol[r->nPt * 2 + 3] = aa;
                r->nPt += 2;
            }
        } else {
            float x2 = v->x2 * scaleX - 1.0f;
            float y2 = v->y2 * scaleY - 1.0f;
            if (r->nLine + 4 < (int)(sizeof(r->lineBuf) / sizeof(r->lineBuf[0]))) {
                r->lineBuf[r->nLine]     = x1;
                r->lineBuf[r->nLine + 1] = y1;
                r->lineBuf[r->nLine + 2] = x2;
                r->lineBuf[r->nLine + 3] = y2;
                int c = r->nLine * 2;
                r->lineCol[c]     = rr; r->lineCol[c + 1] = gg;
                r->lineCol[c + 2] = bb; r->lineCol[c + 3] = aa;
                r->lineCol[c + 4] = rr; r->lineCol[c + 5] = gg;
                r->lineCol[c + 6] = bb; r->lineCol[c + 7] = aa;
                r->nLine += 4;
            }
        }
    }
}

// ── Drawing ────────────────────────────────────────────────────────────

static void draw_batch(CrtRenderer *r, bool points, float line_width) {
    glUseProgram(r->prog);
    glLineWidth(line_width);

    const float *vb = points ? r->ptBuf  : r->lineBuf;
    const float *cb = points ? r->ptCol  : r->lineCol;
    int count       = points ? r->nPt / 2 : r->nLine / 2;
    if (count <= 0) return;

    glEnableVertexAttribArray((GLuint)r->aPos);
    glEnableVertexAttribArray((GLuint)r->aColor);
    glVertexAttribPointer((GLuint)r->aPos,   2, GL_FLOAT, GL_FALSE, 0, vb);
    glVertexAttribPointer((GLuint)r->aColor, 4, GL_FLOAT, GL_FALSE, 0, cb);

    glDrawArrays(points ? GL_POINTS : GL_LINES, 0, count);

    glDisableVertexAttribArray((GLuint)r->aPos);
    glDisableVertexAttribArray((GLuint)r->aColor);
}

void crt_renderer_draw_frame(CrtRenderer *r) {
    if (!r) return;

    // Clear every frame — no accumulation artifacts (same as CrtView).
    glClear(GL_COLOR_BUFFER_BIT);

    if (r->nLine > 0) draw_batch(r, false, 1.5f);
    if (r->nPt   > 0) draw_batch(r, true,  3.0f);

    // FPS accounting
    r->fpsCnt++;
    Uint64 now = SDL_GetPerformanceCounter();
    Uint64 freq = SDL_GetPerformanceFrequency();
    if (now - r->fpsTime >= freq) {
        r->fpsActual = (float)r->fpsCnt;
        r->fpsCnt = 0;
        r->fpsTime = now;
    }
}

void crt_renderer_screen_to_pds(int window_w, int window_h,
                                 float screen_x, float screen_y,
                                 int *out_pds_x, int *out_pds_y) {
    if (window_w < 1) window_w = 1;
    if (window_h < 1) window_h = 1;
    if (out_pds_x) *out_pds_x = (int)(screen_x / (float)window_w * PDS);
    if (out_pds_y) *out_pds_y = (int)((1.0f - screen_y / (float)window_h) * PDS);
}

// ── FPS cap (mirrors CrtView's manual sleep-based cap) ─────────────────

void crt_renderer_set_max_fps(CrtRenderer *r, int max_fps) {
    if (!r) return;
    if (max_fps < 1)  max_fps = 1;
    if (max_fps > 60) max_fps = 60;
    r->maxFps = max_fps;
}

float crt_renderer_get_actual_fps(const CrtRenderer *r) {
    return r ? r->fpsActual : 0.0f;
}

void crt_renderer_frame_begin(CrtRenderer *r) {
    if (!r) return;
    r->frameStart = SDL_GetPerformanceCounter();
}

void crt_renderer_frame_end(CrtRenderer *r) {
    if (!r) return;
    Uint64 freq = SDL_GetPerformanceFrequency();
    Uint64 now = SDL_GetPerformanceCounter();
    double elapsed_ms = (double)(now - r->frameStart) * 1000.0 / (double)freq;
    double budget_ms = 1000.0 / (double)r->maxFps;
    double sleep_ms = budget_ms - elapsed_ms;
    if (sleep_ms > 1.0) {
        SDL_Delay((Uint32)sleep_ms);
    }
}
