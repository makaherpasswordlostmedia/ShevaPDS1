// input_bridge.c
//
// See input_bridge.h. This is the native-to-Java direction of the JNI
// bridge: SDL2 events come in here, get translated into calls on
// com.imlac.pds1.EmulatorBridge's static methods (pumpFrame, setLightPen,
// keyDown/keyUp, setControllerState, ...), mirroring what
// EmulatorActivity's touch/key listeners used to do directly.

#include "input_bridge.h"

#include <SDL.h>
#include <jni.h>
#include <string.h>

#define MAX_VEC 32768

static jclass    g_bridgeClass       = NULL;
static jmethodID g_midPumpFrame      = NULL;
static jmethodID g_midCurrentMachine = NULL;
static jmethodID g_midSetLightPen    = NULL;
static jmethodID g_midKeyDown        = NULL;
static jmethodID g_midKeyUp          = NULL;

static jclass    g_machineClass = NULL;
static jfieldID  g_fidNvec = NULL;
static jfieldID  g_fidVx1 = NULL, g_fidVy1 = NULL, g_fidVx2 = NULL, g_fidVy2 = NULL;
static jfieldID  g_fidVpt = NULL, g_fidVbr = NULL;

static CrtVector g_vecbuf[MAX_VEC];

static JNIEnv *env_for_current_thread(void) {
    return (JNIEnv *)SDL_AndroidGetJNIEnv();
}

void input_bridge_init(void) {
    JNIEnv *env = env_for_current_thread();
    if (!env) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION, "input_bridge_init: no JNIEnv");
        return;
    }

    jclass local = (*env)->FindClass(env, "com/imlac/pds1/EmulatorBridge");
    if (!local) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION, "input_bridge_init: EmulatorBridge not found");
        return;
    }
    g_bridgeClass = (jclass)(*env)->NewGlobalRef(env, local);
    (*env)->DeleteLocalRef(env, local);

    g_midPumpFrame      = (*env)->GetStaticMethodID(env, g_bridgeClass, "pumpFrame", "()V");
    g_midCurrentMachine = (*env)->GetStaticMethodID(env, g_bridgeClass, "currentMachine", "()Lcom/imlac/pds1/Machine;");
    g_midSetLightPen    = (*env)->GetStaticMethodID(env, g_bridgeClass, "setLightPen", "(IIZ)V");
    g_midKeyDown        = (*env)->GetStaticMethodID(env, g_bridgeClass, "keyDown", "(I)V");
    g_midKeyUp          = (*env)->GetStaticMethodID(env, g_bridgeClass, "keyUp", "()V");

    jclass mLocal = (*env)->FindClass(env, "com/imlac/pds1/Machine");
    if (mLocal) {
        g_machineClass = (jclass)(*env)->NewGlobalRef(env, mLocal);
        (*env)->DeleteLocalRef(env, mLocal);
        g_fidNvec = (*env)->GetFieldID(env, g_machineClass, "nvec", "I");
        g_fidVx1  = (*env)->GetFieldID(env, g_machineClass, "vx1", "[I");
        g_fidVy1  = (*env)->GetFieldID(env, g_machineClass, "vy1", "[I");
        g_fidVx2  = (*env)->GetFieldID(env, g_machineClass, "vx2", "[I");
        g_fidVy2  = (*env)->GetFieldID(env, g_machineClass, "vy2", "[I");
        g_fidVpt  = (*env)->GetFieldID(env, g_machineClass, "vpt", "[Z");
        g_fidVbr  = (*env)->GetFieldID(env, g_machineClass, "vbr", "[I");
    }
}

void input_bridge_pump_emulator_frame(CrtRenderer *crt) {
    JNIEnv *env = env_for_current_thread();
    if (!env || !g_bridgeClass || !crt) return;

    // 1. Advance emulation (Machine.dlClear() + Demos.runCurrentDemo()).
    (*env)->CallStaticVoidMethod(env, g_bridgeClass, g_midPumpFrame);

    // 2. Pull the resulting vector list straight out of Machine's public
    //    fields (same arrays jni_bridge.c's nativeSubmitVectors expects,
    //    just read from this side instead of passed as JNI call args).
    jobject machine = (*env)->CallStaticObjectMethod(env, g_bridgeClass, g_midCurrentMachine);
    if (!machine || !g_fidNvec) {
        crt_renderer_submit_vectors(crt, g_vecbuf, 0);
        return;
    }

    jint nvec = (*env)->GetIntField(env, machine, g_fidNvec);
    if (nvec > MAX_VEC) nvec = MAX_VEC;
    if (nvec <= 0) {
        crt_renderer_submit_vectors(crt, g_vecbuf, 0);
        (*env)->DeleteLocalRef(env, machine);
        return;
    }

    jintArray vx1 = (jintArray)(*env)->GetObjectField(env, machine, g_fidVx1);
    jintArray vy1 = (jintArray)(*env)->GetObjectField(env, machine, g_fidVy1);
    jintArray vx2 = (jintArray)(*env)->GetObjectField(env, machine, g_fidVx2);
    jintArray vy2 = (jintArray)(*env)->GetObjectField(env, machine, g_fidVy2);
    jbooleanArray vpt = (jbooleanArray)(*env)->GetObjectField(env, machine, g_fidVpt);
    jintArray vbr = (jintArray)(*env)->GetObjectField(env, machine, g_fidVbr);

    jint *x1 = (*env)->GetIntArrayElements(env, vx1, NULL);
    jint *y1 = (*env)->GetIntArrayElements(env, vy1, NULL);
    jint *x2 = (*env)->GetIntArrayElements(env, vx2, NULL);
    jint *y2 = (*env)->GetIntArrayElements(env, vy2, NULL);
    jboolean *pt = (*env)->GetBooleanArrayElements(env, vpt, NULL);
    jint *br = (*env)->GetIntArrayElements(env, vbr, NULL);

    for (int i = 0; i < nvec; i++) {
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

    (*env)->DeleteLocalRef(env, vx1);
    (*env)->DeleteLocalRef(env, vy1);
    (*env)->DeleteLocalRef(env, vx2);
    (*env)->DeleteLocalRef(env, vy2);
    (*env)->DeleteLocalRef(env, vpt);
    (*env)->DeleteLocalRef(env, vbr);
    (*env)->DeleteLocalRef(env, machine);

    crt_renderer_submit_vectors(crt, g_vecbuf, nvec);
}

// ── Event translation ───────────────────────────────────────────────────

// Maps an SDL keycode to the ASCII/control code Machine.keyboard expects
// (Machine.java historically consumed raw ASCII from Android's KeyEvent
// via getUnicodeChar(); we approximate the same mapping here for the
// common keys the PDS-1 keyboard/teletype cares about).
static int sdl_keycode_to_pds1(SDL_Keycode kc) {
    if (kc >= SDLK_a && kc <= SDLK_z) return 'A' + (kc - SDLK_a);
    if (kc >= SDLK_0 && kc <= SDLK_9) return '0' + (kc - SDLK_0);
    switch (kc) {
        case SDLK_SPACE:     return ' ';
        case SDLK_RETURN:    return '\r';
        case SDLK_BACKSPACE: return 0x08;
        case SDLK_ESCAPE:    return 0x1B;
        case SDLK_PERIOD:    return '.';
        case SDLK_COMMA:     return ',';
        case SDLK_MINUS:     return '-';
        default:             return 0;
    }
}

void input_bridge_handle_event(const SDL_Event *ev, int window_w, int window_h) {
    JNIEnv *env = env_for_current_thread();
    if (!env || !g_bridgeClass) return;

    switch (ev->type) {
        case SDL_FINGERDOWN:
        case SDL_FINGERMOTION:
        case SDL_MOUSEBUTTONDOWN:
        case SDL_MOUSEMOTION: {
            float sx, sy;
            bool down;
            if (ev->type == SDL_FINGERDOWN || ev->type == SDL_FINGERMOTION) {
                sx = ev->tfinger.x * (float)window_w;
                sy = ev->tfinger.y * (float)window_h;
                down = true;
            } else {
                sx = (float)ev->button.x;
                sy = (float)ev->button.y;
                down = (ev->type == SDL_MOUSEBUTTONDOWN) ||
                       ((ev->motion.state & SDL_BUTTON_LMASK) != 0);
            }
            int px, py;
            crt_renderer_screen_to_pds(window_w, window_h, sx, sy, &px, &py);
            (*env)->CallStaticVoidMethod(env, g_bridgeClass, g_midSetLightPen,
                                          (jint)px, (jint)py, (jboolean)down);
            break;
        }
        case SDL_FINGERUP:
        case SDL_MOUSEBUTTONUP: {
            (*env)->CallStaticVoidMethod(env, g_bridgeClass, g_midSetLightPen,
                                          (jint)0, (jint)0, (jboolean)JNI_FALSE);
            break;
        }
        case SDL_KEYDOWN: {
            int code = sdl_keycode_to_pds1(ev->key.keysym.sym);
            if (code != 0) {
                (*env)->CallStaticVoidMethod(env, g_bridgeClass, g_midKeyDown, (jint)code);
            }
            break;
        }
        case SDL_KEYUP: {
            (*env)->CallStaticVoidMethod(env, g_bridgeClass, g_midKeyUp);
            break;
        }
        default:
            break;
    }
}
