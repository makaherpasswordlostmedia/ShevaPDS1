// input_bridge.h
//
// Translates SDL2 input events (touch/mouse/keyboard) into calls on the
// Java-side EmulatorBridge (which forwards to Machine/Demos/NetSession),
// and drives the once-per-frame emulation step + vector upload that used
// to be CrtView.pumpFrame()'s job.
//
// All JNI calls go through SDL_AndroidGetJNIEnv()/SDL_AndroidGetActivity(),
// which SDL2 guarantees are valid on the thread that's running SDL_main()
// (the same thread android_main.c's event loop runs on).

#ifndef INPUT_BRIDGE_H
#define INPUT_BRIDGE_H

#include <SDL.h>
#include "crt_renderer.h"

#ifdef __cplusplus
extern "C" {
#endif

// Looks up EmulatorBridge's class + method IDs. Call once after SDL_Init.
void input_bridge_init(void);

// Runs one emulation frame (EmulatorBridge.pumpFrame()) and uploads the
// resulting vector list into `crt` (same data path as jni_bridge.c's
// nativeSubmitVectors, but driven from native instead of from Java).
void input_bridge_pump_emulator_frame(CrtRenderer *crt);

// Handles one SDL event that the UI layer (ui_widgets.c) did NOT consume
// — i.e. whatever falls through to the CRT surface itself (light pen
// taps, physical keyboard when no on-screen keyboard is focused).
// window_w/window_h are the current drawable size for touch->PDS mapping.
void input_bridge_handle_event(const SDL_Event *ev, int window_w, int window_h);

#ifdef __cplusplus
}
#endif

#endif // INPUT_BRIDGE_H
