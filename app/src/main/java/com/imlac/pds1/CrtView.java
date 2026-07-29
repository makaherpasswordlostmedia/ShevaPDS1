package com.imlac.pds1;

/**
 * PDS-1 vector CRT renderer facade — SDL2/GLES2 native backend.
 *
 * Superseded by direct native calls in most respects: the render loop
 * lives in android_main.c, and per-frame emulation stepping is driven by
 * EmulatorBridge.pumpFrame() called from input_bridge.c. This class is
 * kept only as a thin, testable wrapper around CrtRendererBridge's
 * geometry helpers (resize/screenToPDS/FPS), in case Java-side code
 * (tests, or any future non-native UI) needs them without going through
 * native/SDL2 at all.
 */
public class CrtView {

    private int windowW = 1, windowH = 1;

    public void setMaxFps(int fps) {
        CrtRendererBridge.nativeSetMaxFps(Math.max(1, Math.min(60, fps)));
    }

    public float getActualFps() {
        return CrtRendererBridge.nativeGetActualFps();
    }

    public void onSurfaceResized(int width, int height) {
        windowW = Math.max(1, width);
        windowH = Math.max(1, height);
        CrtRendererBridge.nativeResize(windowW, windowH);
    }

    public int[] screenToPDS(float tx, float ty) {
        int[] out = new int[2];
        CrtRendererBridge.nativeScreenToPds(windowW, windowH, tx, ty, out);
        return out;
    }
}
