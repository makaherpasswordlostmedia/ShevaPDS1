// ui_widgets.h
//
// Minimal immediate-mode UI, rendered with plain SDL2 primitives
// (SDL_RenderFillRect/SDL_RenderDrawLine + a tiny bitmap font) directly
// into the same GL surface the CRT vectors are drawn into. Replaces every
// Android View that used to live in activity_emulator.xml:
//   - control panel: PWR / RESET / RUN / HALT / STEP buttons
//   - register readout: PC, AC, IR, LINK, DPX, DPY
//   - demo/game picker (dropdown-ish list)
//   - virtual dpad + A/B/C/D buttons (MazeWar/Pong controls)
//   - "Load file" button (triggers EmulatorBridge.requestOpenFile())
//   - multiplayer panel: Host / Join / Stop + chat log + text entry
//   - on-screen keyboard (for text entry: chat, program name, etc.)
//
// Deliberately NOT using SDL_Renderer (which can't share a GL context
// cleanly with our GLES2 CRT renderer) — instead uses raw immediate-mode
// GLES2 quads via the same shader program style as crt_renderer.c, so
// everything draws in one GL context with one set of state changes.

#ifndef UI_WIDGETS_H
#define UI_WIDGETS_H

#include <SDL.h>
#include <stdbool.h>
#include "crt_renderer.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct UiContext UiContext;

UiContext *ui_create(int width_px, int height_px);
void ui_destroy(UiContext *ui);
void ui_resize(UiContext *ui, int width_px, int height_px);

// Returns true if the event was consumed by a widget (button tap, text
// entry, dpad, etc.) and should NOT be forwarded to the CRT/light-pen
// input path.
bool ui_handle_event(UiContext *ui, const SDL_Event *ev);

// Draws every visible widget. Called once per frame, after the CRT
// vectors have already been drawn (so UI overlays on top).
void ui_draw(UiContext *ui, CrtRenderer *crt);

#ifdef __cplusplus
}
#endif

#endif // UI_WIDGETS_H
