// jni_bridge.c
//
// JNI glue between Java (Machine.java's vector arrays, CrtView-equivalent
// lifecycle calls) and the native SDL2/GLES2 crt_renderer.
//
// Design: the emulation core (Machine, Demos, MazeWarGame, ...) STAYS in
// Java, unchanged. Only the rendering moves to native/SDL2. Each frame,
// Java calls nativeSubmitVectors() with the same data it used to hand to
// CrtView.buildBuffers() (parallel arrays vx1/vy1/vx2/vy2/vpt/vbr, length
// nvec), then nativeDrawFrame(). The GL context itself is created/owned by
// SDL2's Android glue (SDLActivity), which calls nativeInit()/nativeResize()
// at the appropriate points in its lifecycle — mirroring what
// GLSurfaceView.Renderer.onSurfaceCreated()/onSurfaceChanged() used to do.
//
// Expected Java-side counterpart (added in a later step): a thin
// "CrtRendererBridge" class with native method declarations matching the
// JNI function names below, replacing CrtView.java's GLES20 calls with
// calls into this bridge. EmulatorActivity keeps calling
// setMaxFps()/getActualFps()/screenToPDS() the same way; those now forward
// here instead of into GLSurfaceView.

#include <jni.h>
#include <stdlib.h>

#include "crt_renderer.h"

// One renderer instance for the process — mirrors CrtView being a single
// GLSurfaceView per EmulatorActivity. If multiple emulator screens are ever
// needed at once, switch this to a handle-based API (return a jlong from
// nativeInit and pass it back into every other call).
//
// android_main.c creates/destroys this itself now (since it owns the GL
// context directly, unlike the old GLSurfaceView flow where Java drove
// onSurfaceCreated()), so it's exposed here for input_bridge.c to reuse
// rather than each side keeping a separate CrtRenderer instance.
static CrtRenderer *g_renderer = NULL;

CrtRenderer *jni_bridge_get_renderer(void) { return g_renderer; }
void jni_bridge_set_renderer(CrtRenderer *r) { g_renderer = r; }

// Scratch buffer reused across frames to avoid per-frame JNI allocations.
static CrtVector g_vecbuf[65536 / 4];

JNIEXPORT void JNICALL
Java_com_imlac_pds1_CrtRendererBridge_nativeInit(JNIEnv *env, jclass clazz) {
    (void)env; (void)clazz;
    if (g_renderer) {
        crt_renderer_destroy(g_renderer);
        g_renderer = NULL;
    }
    g_renderer = crt_renderer_create();
}

JNIEXPORT void JNICALL
Java_com_imlac_pds1_CrtRendererBridge_nativeDestroy(JNIEnv *env, jclass clazz) {
    (void)env; (void)clazz;
    crt_renderer_destroy(g_renderer);
    g_renderer = NULL;
}

JNIEXPORT void JNICALL
Java_com_imlac_pds1_CrtRendererBridge_nativeResize(JNIEnv *env, jclass clazz,
                                                    jint width, jint height) {
    (void)env; (void)clazz;
    crt_renderer_resize(g_renderer, width, height);
}

JNIEXPORT void JNICALL
Java_com_imlac_pds1_CrtRendererBridge_nativeSetMaxFps(JNIEnv *env, jclass clazz, jint fps) {
    (void)env; (void)clazz;
    crt_renderer_set_max_fps(g_renderer, fps);
}

JNIEXPORT jfloat JNICALL
Java_com_imlac_pds1_CrtRendererBridge_nativeGetActualFps(JNIEnv *env, jclass clazz) {
    (void)env; (void)clazz;
    return crt_renderer_get_actual_fps(g_renderer);
}

// Submits the current frame's vector list, mirroring Machine's parallel
// arrays (vx1, vy1, vx2, vy2, vpt, vbr) truncated to `count` == Machine.nvec.
// Called once per frame from Java right before nativeDrawFrame().
JNIEXPORT void JNICALL
Java_com_imlac_pds1_CrtRendererBridge_nativeSubmitVectors(
    JNIEnv *env, jclass clazz,
    jintArray vx1, jintArray vy1, jintArray vx2, jintArray vy2,
    jbooleanArray vpt, jintArray vbr, jint count) {
    (void)clazz;

    int max = (int)(sizeof(g_vecbuf) / sizeof(g_vecbuf[0]));
    if (count > max) count = max;
    if (count <= 0) {
        crt_renderer_submit_vectors(g_renderer, g_vecbuf, 0);
        return;
    }

    jint *x1 = (*env)->GetIntArrayElements(env, vx1, NULL);
    jint *y1 = (*env)->GetIntArrayElements(env, vy1, NULL);
    jint *x2 = (*env)->GetIntArrayElements(env, vx2, NULL);
    jint *y2 = (*env)->GetIntArrayElements(env, vy2, NULL);
    jboolean *pt = (*env)->GetBooleanArrayElements(env, vpt, NULL);
    jint *br = (*env)->GetIntArrayElements(env, vbr, NULL);

    for (int i = 0; i < count; i++) {
        g_vecbuf[i].x1 = (int16_t)x1[i];
        g_vecbuf[i].y1 = (int16_t)y1[i];
        g_vecbuf[i].x2 = (int16_t)x2[i];
        g_vecbuf[i].y2 = (int16_t)y2[i];
        g_vecbuf[i].is_point = pt[i] ? 1 : 0;
        g_vecbuf[i].brightness = (uint8_t)br[i];
    }

    (*env)->ReleaseIntArrayElements(env, vx1, x1, JNI_ABORT);
    (*env)->ReleaseIntArrayElements(env, vy1, y1, JNI_ABORT);
    (*env)->ReleaseIntArrayElements(env, vx2, x2, JNI_ABORT);
    (*env)->ReleaseIntArrayElements(env, vy2, y2, JNI_ABORT);
    (*env)->ReleaseBooleanArrayElements(env, vpt, pt, JNI_ABORT);
    (*env)->ReleaseIntArrayElements(env, vbr, br, JNI_ABORT);

    crt_renderer_submit_vectors(g_renderer, g_vecbuf, count);
}

JNIEXPORT void JNICALL
Java_com_imlac_pds1_CrtRendererBridge_nativeDrawFrame(JNIEnv *env, jclass clazz) {
    (void)env; (void)clazz;
    crt_renderer_frame_begin(g_renderer);
    crt_renderer_draw_frame(g_renderer);
    // NOTE: SDL_GL_SwapWindow() is called by SDL2's own Android render
    // loop (SDLActivity), not here — this function only issues GL draw
    // calls, matching what CrtView.onDrawFrame() used to do before the
    // GLSurfaceView machinery swapped buffers for it.
    crt_renderer_frame_end(g_renderer);
}

JNIEXPORT void JNICALL
Java_com_imlac_pds1_CrtRendererBridge_nativeScreenToPds(
    JNIEnv *env, jclass clazz,
    jint windowW, jint windowH, jfloat screenX, jfloat screenY,
    jintArray outXY) {
    (void)clazz;
    int px = 0, py = 0;
    crt_renderer_screen_to_pds(windowW, windowH, screenX, screenY, &px, &py);
    jint out[2] = { px, py };
    (*env)->SetIntArrayRegion(env, outXY, 0, 2, out);
}
