// android_main.c
//
// SDL2 entry point for Android. This is what actually owns the window, the
// GL context, and the frame loop on-device — replacing GLSurfaceView +
// EmulatorActivity's UI thread. SDL2's Android glue (SDL2/android-project's
// SDLActivity.java + SDL_android_main.c, pulled in by the vendored SDL2/
// tree) calls SDL_main() below via a background thread once the app's
// native activity/surface is ready.
//
// Responsibilities of this file:
//   - create the SDL window + GLES2 context (SDL_CreateWindow/SDL_GL_CreateContext)
//   - own the render loop: poll events -> update UI/input -> pump one
//     Machine/Demos frame via CrtView.pumpFrame() (called through JNI,
//     see jni_bridge.c's Java_..._nativeDrawFrame which this loop drives
//     indirectly) -> draw CRT vectors -> draw SDL2-rendered UI widgets
//     (control panel, dpad, chat, keyboard — see ui_widgets.c) -> swap
//   - forward SDL events (touch/mouse/keyboard) into input_bridge.c, which
//     translates them into calls on the same Java objects EmulatorActivity
//     used to drive directly (Machine.keyboard, Machine.lpen_*, ctrl[])
//
// NOTE: Since the emulation core (Machine/Demos/NetSession/GameLoader)
// intentionally stays in Java (see the "Only rendering moves to native"
// decision from stage 1), this file talks to Java via JNI for anything
// that isn't pure rendering — see input_bridge.c and jni_glue_helpers
// below. SDL2's SDLActivity gives us a valid JNIEnv*/jobject for the
// current thread via SDL_AndroidGetJNIEnv()/SDL_AndroidGetActivity().

#include <SDL.h>
#if defined(__ANDROID__)
#include <GLES2/gl2.h>
#include <jni.h>
#include <android/log.h>
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "pds1native", __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "pds1native", __VA_ARGS__)
#else
#include <SDL_opengles2.h>
#define LOGI(...) SDL_Log(__VA_ARGS__)
#define LOGE(...) SDL_LogError(SDL_LOG_CATEGORY_APPLICATION, __VA_ARGS__)
#endif

#include "crt_renderer.h"
#include "ui_widgets.h"
#include "input_bridge.h"

static SDL_Window   *g_window   = NULL;
static SDL_GLContext g_glctx    = NULL;
static CrtRenderer   *g_crt     = NULL;
static UiContext      *g_ui     = NULL;

static int init_video(void) {
    if (SDL_Init(SDL_INIT_VIDEO) != 0) {
        LOGE("SDL_Init failed: %s", SDL_GetError());
        return -1;
    }

    SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_ES);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 2);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 0);
    SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
    SDL_GL_SetAttribute(SDL_GL_RETAINED_BACKING, 0);

    // On Android, SDL2 ignores width/height/flags for the actual window
    // geometry (it always fills the native window) but still wants a
    // window handle to attach the GL context to. SDL_WINDOW_FULLSCREEN
    // matches EmulatorActivity's old FLAG_FULLSCREEN + hideSystemUI().
    Uint32 flags = SDL_WINDOW_OPENGL | SDL_WINDOW_FULLSCREEN | SDL_WINDOW_ALLOW_HIGHDPI;
    g_window = SDL_CreateWindow("Imlac PDS-1", 0, 0, 1280, 720, flags);
    if (!g_window) {
        LOGE("SDL_CreateWindow failed: %s", SDL_GetError());
        return -1;
    }

    g_glctx = SDL_GL_CreateContext(g_window);
    if (!g_glctx) {
        LOGE("SDL_GL_CreateContext failed: %s", SDL_GetError());
        return -1;
    }
    SDL_GL_SetSwapInterval(1);

    // Keep the screen on, matching FLAG_KEEP_SCREEN_ON from EmulatorActivity.
    SDL_SetHint(SDL_HINT_IDLE_TIMER_DISABLED, "1");
    // Landscape lock, matching android:screenOrientation="landscape".
    SDL_SetHint(SDL_HINT_ORIENTATIONS, "LandscapeLeft LandscapeRight");

    return 0;
}

static void shutdown_video(void) {
    if (g_ui)     { ui_destroy(g_ui); g_ui = NULL; }
    if (g_crt)    { jni_bridge_set_renderer(NULL); crt_renderer_destroy(g_crt); g_crt = NULL; }
    if (g_glctx)  { SDL_GL_DeleteContext(g_glctx); g_glctx = NULL; }
    if (g_window) { SDL_DestroyWindow(g_window); g_window = NULL; }
    SDL_Quit();
}

int SDL_main(int argc, char *argv[]) {
    (void)argc; (void)argv;

    if (init_video() != 0) {
        shutdown_video();
        return 1;
    }

    g_crt = crt_renderer_create();
    if (!g_crt) {
        LOGE("crt_renderer_create failed");
        shutdown_video();
        return 1;
    }
    crt_renderer_set_max_fps(g_crt, 30);

    // Register with jni_bridge.c so CrtRendererBridge.native* (if ever
    // called from Java, e.g. future non-SDL UI or tests) operates on this
    // same renderer instance instead of creating a second one.
    jni_bridge_set_renderer(g_crt);

    int w, h;
    SDL_GL_GetDrawableSize(g_window, &w, &h);
    crt_renderer_resize(g_crt, w, h);

    g_ui = ui_create(w, h);
    input_bridge_init();

    bool running = true;
    while (running) {
        crt_renderer_frame_begin(g_crt);

        SDL_Event ev;
        while (SDL_PollEvent(&ev)) {
            switch (ev.type) {
                case SDL_QUIT:
                    running = false;
                    break;
                case SDL_APP_TERMINATING:
                    running = false;
                    break;
                case SDL_WINDOWEVENT:
                    if (ev.window.event == SDL_WINDOWEVENT_SIZE_CHANGED ||
                        ev.window.event == SDL_WINDOWEVENT_RESIZED) {
                        SDL_GL_GetDrawableSize(g_window, &w, &h);
                        crt_renderer_resize(g_crt, w, h);
                        ui_resize(g_ui, w, h);
                    }
                    break;
                default:
                    // Everything else (touch, mouse, key) goes through
                    // the UI layer first (buttons/dpad/keyboard consume
                    // it), then whatever's left goes to the CRT/light-pen
                    // input path. See input_bridge.c.
                    if (!ui_handle_event(g_ui, &ev)) {
                        input_bridge_handle_event(&ev, w, h);
                    }
                    break;
            }
        }

        // 1. Emulation + CRT vector rendering (delegates into Java via
        //    JNI for Machine.dlClear()/Demos.runCurrentDemo(), then draws
        //    the resulting vector list natively). See input_bridge.c for
        //    the JNI call that does this (pump_emulator_frame()).
        input_bridge_pump_emulator_frame(g_crt);

        // 2. SDL2-rendered UI overlay: control panel, dpad, keyboard,
        //    chat, register readouts (see ui_widgets.c).
        ui_draw(g_ui, g_crt);

        SDL_GL_SwapWindow(g_window);
        crt_renderer_frame_end(g_crt);
    }

    shutdown_video();
    return 0;
}
