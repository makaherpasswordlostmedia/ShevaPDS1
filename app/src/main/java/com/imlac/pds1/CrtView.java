package com.imlac.pds1;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.PorterDuff;
import android.graphics.PorterDuffXfermode;
import android.graphics.RadialGradient;
import android.graphics.Shader;
import android.util.AttributeSet;
import android.view.SurfaceHolder;
import android.view.SurfaceView;

/**
 * CRT Surface View — renders the Imlac PDS-1 vector display.
 *
 * Simulates phosphor green CRT with:
 *   - Phosphor decay (frame blending)
 *   - Glow on each vector line
 *   - Scanline overlay
 *   - Vignette
 */
public class CrtView extends SurfaceView implements SurfaceHolder.Callback {

    // Coordinate space: PDS-1 uses 1024x1024
    private static final int PDSX = 1024;
    private static final int PDSY = 1024;

    // Phosphor colours
    private static final int COL_CORE  = Color.argb(255,  20, 255,  65);
    private static final int COL_GLOW1 = Color.argb(120,   0, 200,  50);
    private static final int COL_GLOW2 = Color.argb( 40,   0, 150,  35);

    private final Paint paintCore  = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint paintGlow1 = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint paintGlow2 = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint paintDecay = new Paint();
    private final Paint paintFill  = new Paint();
    private final Paint paintScan  = new Paint();

    private android.graphics.Bitmap offBmp;
    private Canvas  offCanvas;

    private volatile Machine machine;
    private volatile Demos   demos;
    private volatile boolean running = false;
    private Thread renderThread;

    public CrtView(Context ctx) { super(ctx); init(); }
    public CrtView(Context ctx, AttributeSet a) { super(ctx, a); init(); }

    private void init() {
        getHolder().addCallback(this);
        setZOrderOnTop(false);

        paintCore.setStrokeWidth(1.5f);
        paintCore.setColor(COL_CORE);
        paintCore.setShadowLayer(6f, 0, 0, COL_GLOW1);

        paintGlow1.setStrokeWidth(4f);
        paintGlow1.setColor(COL_GLOW1);

        paintGlow2.setStrokeWidth(8f);
        paintGlow2.setColor(COL_GLOW2);

        // Decay: fill with semi-transparent black each frame
        paintDecay.setColor(Color.argb(38, 0, 0, 0)); // ~15% decay
        paintDecay.setXfermode(new PorterDuffXfermode(PorterDuff.Mode.SRC_OVER));

        paintFill.setColor(Color.BLACK);

        // Scanline paint
        paintScan.setColor(Color.argb(22, 0, 0, 0));
        paintScan.setStrokeWidth(1f);
    }

    public void setMachine(Machine m, Demos d) {
        this.machine = m;
        this.demos   = d;
    }

    @Override public void surfaceCreated(SurfaceHolder h) {
        int w = getWidth(), hh = getHeight();
        offBmp    = android.graphics.Bitmap.createBitmap(w, hh,
                       android.graphics.Bitmap.Config.ARGB_8888);
        offCanvas = new Canvas(offBmp);
        offCanvas.drawColor(Color.BLACK);
        startRender();
    }

    @Override public void surfaceChanged(SurfaceHolder h, int fmt, int w, int hh) {
        stopRender();
        offBmp    = android.graphics.Bitmap.createBitmap(w, hh,
                       android.graphics.Bitmap.Config.ARGB_8888);
        offCanvas = new Canvas(offBmp);
        offCanvas.drawColor(Color.BLACK);
        startRender();
    }

    @Override public void surfaceDestroyed(SurfaceHolder h) { stopRender(); }

    private void startRender() {
        running = true;
        renderThread = new Thread(this::renderLoop, "imlac-render");
        renderThread.setDaemon(true);
        renderThread.start();
    }

    private void stopRender() {
        running = false;
        if (renderThread != null) {
            try { renderThread.join(500); } catch (InterruptedException ignored) {}
        }
    }

    // ── Render loop ~30fps ────────────────────────────────────
    private void renderLoop() {
        while (running) {
            long t0 = System.currentTimeMillis();

            Machine m = machine;
            Demos   d = demos;
            if (m != null && d != null) {
                // Generate display list from demo
                m.dlClear();
                d.runCurrentDemo();

                // Draw to off-screen bitmap
                renderFrame(m);

                // Blit to surface
                SurfaceHolder holder = getHolder();
                Canvas c = null;
                try {
                    c = holder.lockCanvas();
                    if (c != null) {
                        c.drawBitmap(offBmp, 0, 0, null);
                        drawOverlays(c);
                    }
                } finally {
                    if (c != null) holder.unlockCanvasAndPost(c);
                }
            }

            // Cap at 30fps
            long elapsed = System.currentTimeMillis() - t0;
            if (elapsed < 33) {
                try { Thread.sleep(33 - elapsed); }
                catch (InterruptedException ignored) {}
            }
        }
    }

    // ── Phosphor decay + draw vectors ────────────────────────
    private void renderFrame(Machine m) {
        int sw = offBmp.getWidth();
        int sh = offBmp.getHeight();

        // Phosphor decay
        offCanvas.drawRect(0, 0, sw, sh, paintDecay);

        // Map PDS-1 coords (0..1023) to screen
        float sx = (float) sw / PDSX;
        float sy = (float) sh / PDSY;

        int nv = m.nvec;
        for (int i = 0; i < nv; i++) {
            float bright = m.vbr[i] / 255f;
            if (bright < 0.05f) continue;

            float cx1 =  m.vx1[i] * sx;
            float cy1 = sh - m.vy1[i] * sy;  // flip Y

            if (m.vpt[i]) {
                // Point with glow
                paintGlow2.setColor(Color.argb((int)(bright*35), 0, 180, 40));
                offCanvas.drawCircle(cx1, cy1, 6f, paintGlow2);
                paintGlow1.setColor(Color.argb((int)(bright*100), 0, 220, 55));
                offCanvas.drawCircle(cx1, cy1, 3f, paintGlow1);
                paintCore.setColor(Color.argb((int)(bright*255), 20, 255, 65));
                offCanvas.drawCircle(cx1, cy1, 1.5f, paintCore);
            } else {
                float cx2 =  m.vx2[i] * sx;
                float cy2 = sh - m.vy2[i] * sy;

                // Outer glow
                paintGlow2.setColor(Color.argb((int)(bright*30), 0, 150, 35));
                paintGlow2.setStrokeWidth(7f);
                offCanvas.drawLine(cx1, cy1, cx2, cy2, paintGlow2);

                // Inner glow
                paintGlow1.setColor(Color.argb((int)(bright*80), 0, 200, 50));
                paintGlow1.setStrokeWidth(3.5f);
                offCanvas.drawLine(cx1, cy1, cx2, cy2, paintGlow1);

                // Core line
                paintCore.setColor(Color.argb((int)(bright*255), 20, 255, 65));
                paintCore.setStrokeWidth(1.3f);
                offCanvas.drawLine(cx1, cy1, cx2, cy2, paintCore);
            }
        }
    }

    // ── CRT overlays drawn directly on surface ───────────────
    private void drawOverlays(Canvas c) {
        int w = c.getWidth(), h = c.getHeight();

        // Scanlines
        for (int y = 0; y < h; y += 3) {
            c.drawLine(0, y, w, y, paintScan);
        }

        // Vignette
        RadialGradient vg = new RadialGradient(
            w/2f, h/2f, Math.max(w, h) * 0.65f,
            Color.TRANSPARENT, Color.argb(160, 0, 0, 0),
            Shader.TileMode.CLAMP);
        Paint vp = new Paint(Paint.ANTI_ALIAS_FLAG);
        vp.setShader(vg);
        c.drawRect(0, 0, w, h, vp);
    }

    // ── Public: map screen tap to PDS-1 coordinates ──────────
    public int[] screenToPDS(float tx, float ty) {
        int sw = getWidth(), sh = getHeight();
        int px = (int)(tx / sw * PDSX);
        int py = (int)((1f - ty / sh) * PDSY);
        return new int[]{px, py};
    }
}
