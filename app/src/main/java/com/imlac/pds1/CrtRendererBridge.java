package com.imlac.pds1;

/**
 * Thin JNI façade over native/src/jni_bridge.c + crt_renderer.c.
 *
 * This is the SDL2/GLES2 replacement for what CrtView.java used to do
 * directly via android.opengl.GLES20. The actual GL context is created and
 * owned by SDL2's Android glue (SDLActivity) — this class is only
 * responsible for forwarding per-frame vector data and lifecycle events
 * into native code; it does not create windows or GL contexts itself.
 *
 * Native method names must match Java_com_imlac_pds1_CrtRendererBridge_*
 * exactly (see jni_bridge.c).
 */
public final class CrtRendererBridge {

    static {
        // Loads libpds1native.so, which must statically link (or dlopen)
        // crt_renderer.c + jni_bridge.c. See native/CMakeLists.txt /
        // app/build.gradle's externalNativeBuild config.
        System.loadLibrary("pds1native");
    }

    private CrtRendererBridge() { }

    /** Call once the GL context is current (mirrors onSurfaceCreated()). */
    public static native void nativeInit();

    /** Call when the renderer/context is going away. */
    public static native void nativeDestroy();

    /** Call on surface size changes (mirrors onSurfaceChanged()). */
    public static native void nativeResize(int width, int height);

    public static native void nativeSetMaxFps(int fps);
    public static native float nativeGetActualFps();

    /**
     * Uploads this frame's vector list. Arrays are Machine's own
     * vx1/vy1/vx2/vy2/vpt/vbr, sliced to `count` == Machine.nvec — same
     * data CrtView.buildBuffers() used to consume directly.
     */
    public static native void nativeSubmitVectors(
        int[] vx1, int[] vy1, int[] vx2, int[] vy2,
        boolean[] vpt, int[] vbr, int count);

    /** Clears + draws everything submitted since the last call. */
    public static native void nativeDrawFrame();

    /**
     * Converts a touch position (window pixel coords) to PDS-1 device
     * space (0..1023, Y flipped), matching CrtView.screenToPDS(). Result
     * is written into out[0]=x, out[1]=y; out must be length 2.
     */
    public static native void nativeScreenToPds(
        int windowW, int windowH, float screenX, float screenY, int[] out);
}
