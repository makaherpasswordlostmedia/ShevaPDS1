// main.c
//
// Standalone SDL2 desktop entry point — used to develop/test crt_renderer.c
// in isolation before wiring it into Android via JNI.
//
// It draws a simple animated Lissajous pattern using the same CrtVector
// struct the real Machine/Demos emulation core will fill in, so the vector
// pipeline (submit -> draw_frame) is exercised end-to-end.
//
// On Android this file is NOT used — SDLActivity there talks to the app's
// native lib via SDL_main or via explicit JNI calls that populate the same
// CrtVector buffer from Machine's vx1/vy1/vx2/vy2/vpt/vbr arrays each frame
// (see native/src/jni_bridge.c, added in a later step).

#include <SDL.h>
#include "crt_renderer.h"

#include <math.h>
#include <stdio.h>

#define WIN_W 800
#define WIN_H 800
#define PDS 1024

static int build_demo_vectors(CrtVector *out, int max, double t) {
    int n = 0;
    // Lissajous curve, PDS-1 device space (0..1023), like Demos' LISSAJOUS demo.
    const int steps = 360;
    int prevX = -1, prevY = -1;
    for (int i = 0; i <= steps && n < max; i++) {
        double a = (double)i / steps * 2.0 * M_PI;
        double x = 512 + 400 * sin(3.0 * a + t);
        double y = 512 + 400 * sin(4.0 * a);
        int px = (int)x, py = (int)y;
        if (prevX >= 0) {
            CrtVector *v = &out[n++];
            v->x1 = (int16_t)prevX; v->y1 = (int16_t)prevY;
            v->x2 = (int16_t)px;    v->y2 = (int16_t)py;
            v->brightness = 220;
            v->is_point = 0;
        }
        prevX = px; prevY = py;
    }
    // A bright point marker at the center, like a light-pen cursor.
    if (n < max) {
        CrtVector *v = &out[n++];
        v->x1 = PDS / 2; v->y1 = PDS / 2;
        v->brightness = 255;
        v->is_point = 1;
    }
    return n;
}

int main(int argc, char *argv[]) {
    (void)argc; (void)argv;

    if (SDL_Init(SDL_INIT_VIDEO) != 0) {
        fprintf(stderr, "SDL_Init failed: %s\n", SDL_GetError());
        return 1;
    }

    SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_ES);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 2);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 0);
    SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);

    SDL_Window *win = SDL_CreateWindow(
        "PDS-1 CRT (SDL2)",
        SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
        WIN_W, WIN_H,
        SDL_WINDOW_OPENGL | SDL_WINDOW_RESIZABLE);
    if (!win) {
        fprintf(stderr, "SDL_CreateWindow failed: %s\n", SDL_GetError());
        SDL_Quit();
        return 1;
    }

    SDL_GLContext gl = SDL_GL_CreateContext(win);
    if (!gl) {
        fprintf(stderr, "SDL_GL_CreateContext failed: %s\n", SDL_GetError());
        SDL_DestroyWindow(win);
        SDL_Quit();
        return 1;
    }
    SDL_GL_SetSwapInterval(1); // vsync

    CrtRenderer *renderer = crt_renderer_create();
    if (!renderer) {
        fprintf(stderr, "crt_renderer_create failed\n");
        SDL_GL_DeleteContext(gl);
        SDL_DestroyWindow(win);
        SDL_Quit();
        return 1;
    }
    crt_renderer_set_max_fps(renderer, 30);

    int w, h;
    SDL_GL_GetDrawableSize(win, &w, &h);
    crt_renderer_resize(renderer, w, h);

    static CrtVector vecbuf[65536 / 4];

    bool running = true;
    Uint64 t0 = SDL_GetPerformanceCounter();
    while (running) {
        crt_renderer_frame_begin(renderer);

        SDL_Event ev;
        while (SDL_PollEvent(&ev)) {
            if (ev.type == SDL_QUIT) running = false;
            if (ev.type == SDL_KEYDOWN && ev.key.keysym.sym == SDLK_ESCAPE) running = false;
            if (ev.type == SDL_WINDOWEVENT && ev.window.event == SDL_WINDOWEVENT_SIZE_CHANGED) {
                SDL_GL_GetDrawableSize(win, &w, &h);
                crt_renderer_resize(renderer, w, h);
            }
            if (ev.type == SDL_MOUSEBUTTONDOWN) {
                int px, py;
                crt_renderer_screen_to_pds(w, h, (float)ev.button.x, (float)ev.button.y, &px, &py);
                printf("click -> PDS (%d, %d)\n", px, py);
            }
        }

        double t = (double)(SDL_GetPerformanceCounter() - t0) / SDL_GetPerformanceFrequency();
        int n = build_demo_vectors(vecbuf, (int)(sizeof(vecbuf) / sizeof(vecbuf[0])), t);

        crt_renderer_submit_vectors(renderer, vecbuf, n);
        crt_renderer_draw_frame(renderer);

        SDL_GL_SwapWindow(win);
        crt_renderer_frame_end(renderer);
    }

    crt_renderer_destroy(renderer);
    SDL_GL_DeleteContext(gl);
    SDL_DestroyWindow(win);
    SDL_Quit();
    return 0;
}
