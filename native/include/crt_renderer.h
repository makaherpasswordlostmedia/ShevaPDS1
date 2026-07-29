// crt_renderer.h
//
// SDL2 + OpenGL ES2 replacement for CrtView.java (GLSurfaceView renderer).
// Renders the PDS-1 vector display list (lines + points) with phosphor-green
// shading, batched into 2 draw calls per frame — same approach as the
// original Java/GLES20 renderer, just moved to native SDL2/GL.
//
// The emulation core (Machine, Demos, ...) is expected to stay on the Java
// side for now; this renderer only needs read access to the vector buffers
// that Machine already exposes (vx1/vy1/vx2/vy2/vpt/vbr/nvec), passed in
// each frame via crt_renderer_submit_vectors(). A JNI shim (added later)
// will copy those arrays from Java into this call.
//
// Coordinate space: PDS-1 device space is 0..1023 (PDS = 1024) on both
// axes, origin bottom-left. This matches Machine.java's vx/vy fields.

#ifndef CRT_RENDERER_H
#define CRT_RENDERER_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// One vector-display entry, mirroring Machine.java's parallel arrays
// (vx1[i], vy1[i], vx2[i], vy2[i], vpt[i], vbr[i]) but packed as a struct
// for a cleaner native API. vbr is brightness 0-255, same as Java.
typedef struct {
    int16_t x1, y1;   // PDS-1 device coords, 0..1023
    int16_t x2, y2;   // only meaningful when is_point == false
    uint8_t brightness; // 0-255
    uint8_t is_point;   // true => draw a point at (x1,y1); false => line (x1,y1)-(x2,y2)
} CrtVector;

// Opaque renderer handle. Create one per GL context (one per window).
typedef struct CrtRenderer CrtRenderer;

// Creates the renderer: compiles shaders, allocates GPU-side buffers.
// Must be called with a current GL (ES2+) context, e.g. right after
// SDL_GL_CreateContext(). Returns NULL on failure (check SDL_GetError()).
CrtRenderer *crt_renderer_create(void);

// Destroys the renderer and frees GL resources. Safe to call with NULL.
void crt_renderer_destroy(CrtRenderer *r);

// Call whenever the drawable size changes (window resize / orientation
// change). Sets the GL viewport.
void crt_renderer_resize(CrtRenderer *r, int width_px, int height_px);

// Replaces the vector buffer for the upcoming frame. `count` is the number
// of valid entries in `vectors`. The renderer copies what it needs
// internally (like Machine.dlClear()+dlLine()/dlPoint() populate vbr/vx1..
// on the Java side, then CrtView.buildBuffers() consumes them) — so the
// caller's array can be reused/overwritten right after this call returns.
void crt_renderer_submit_vectors(CrtRenderer *r, const CrtVector *vectors, int count);

// Clears the screen and draws the vectors submitted via
// crt_renderer_submit_vectors() since the last frame. Call once per frame,
// then SDL_GL_SwapWindow(). Equivalent to CrtView.onDrawFrame().
void crt_renderer_draw_frame(CrtRenderer *r);

// Converts a touch/mouse position in window pixel coordinates to PDS-1
// device space (0..1023, Y flipped so origin is bottom-left), matching
// CrtView.screenToPDS(). window_w/window_h are the current drawable size
// (same values passed to crt_renderer_resize()).
void crt_renderer_screen_to_pds(int window_w, int window_h,
                                 float screen_x, float screen_y,
                                 int *out_pds_x, int *out_pds_y);

// Frame-rate cap helper, mirrors CrtView's manual FPS cap (GLSurfaceView /
// a plain SDL loop doesn't vsync-limit for you on every platform).
// Call crt_renderer_frame_begin() at the top of the loop iteration and
// crt_renderer_frame_end() after SwapWindow(); it will sleep as needed to
// hit max_fps and updates the measured actual FPS.
void crt_renderer_set_max_fps(CrtRenderer *r, int max_fps);
float crt_renderer_get_actual_fps(const CrtRenderer *r);
void crt_renderer_frame_begin(CrtRenderer *r);
void crt_renderer_frame_end(CrtRenderer *r);

// ── JNI bridge accessors (defined in jni_bridge.c) ──────────────────────
// android_main.c owns the single CrtRenderer instance (it creates the GL
// context directly via SDL2, unlike the old GLSurfaceView flow). It
// registers that instance here so jni_bridge.c's Java-callable functions
// (CrtRendererBridge.native*) operate on the same renderer instead of
// each side keeping a separate one.
CrtRenderer *jni_bridge_get_renderer(void);
void jni_bridge_set_renderer(CrtRenderer *r);

#ifdef __cplusplus
}
#endif

#endif // CRT_RENDERER_H
