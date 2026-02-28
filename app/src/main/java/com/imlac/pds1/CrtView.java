package com.imlac.pds1;

import android.content.Context;
import android.opengl.GLES20;
import android.opengl.GLSurfaceView;
import android.util.AttributeSet;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.FloatBuffer;

import javax.microedition.khronos.egl.EGLConfig;
import javax.microedition.khronos.opengles.GL10;

/**
 * OpenGL ES 2.0 vector CRT renderer.
 * All vectors drawn in 2 batched draw calls per frame (lines + points).
 * ~10x faster than Canvas.drawLine() on Snapdragon 4xx.
 */
public class CrtView extends GLSurfaceView implements GLSurfaceView.Renderer {

    private static final int PDS = 1024;

    // Vertex shader — passes brightness as alpha
    private static final String VERT_SRC =
        "attribute vec2 aPos;\n" +
        "attribute vec4 aColor;\n" +
        "varying vec4 vColor;\n" +
        "void main() {\n" +
        "  gl_Position = vec4(aPos, 0.0, 1.0);\n" +
        "  gl_PointSize = 3.0;\n" +
        "  vColor = aColor;\n" +
        "}\n";

    // Fragment shader — simple phosphor green tint
    private static final String FRAG_SRC =
        "precision mediump float;\n" +
        "varying vec4 vColor;\n" +
        "void main() {\n" +
        "  gl_FragColor = vColor;\n" +
        "}\n";

    private int prog, aPos, aColor;

    // Per-frame buffers — pre-allocated, zero GC
    private static final int MAX_VERTS = 65536;
    private final float[]  lineBuf  = new float[MAX_VERTS];
    private final float[]  lineCol  = new float[MAX_VERTS * 2];
    private final float[]  ptBuf    = new float[MAX_VERTS / 4];
    private final float[]  ptCol    = new float[MAX_VERTS / 2];
    private int nLine = 0, nPt = 0;

    private FloatBuffer vbLine, cbLine, vbPt, cbPt;

    private volatile Machine machine;
    private volatile Demos   demos;
    private volatile int     maxFps   = 30;
    private volatile float   fpsActual = 0f;
    private long fpsTime = 0; private int fpsCnt = 0;

    private int surfW = 1, surfH = 1;

    public CrtView(Context ctx)                    { super(ctx); init(); }
    public CrtView(Context ctx, AttributeSet attrs) { super(ctx, attrs); init(); }

    private void init() {
        setEGLContextClientVersion(2);
        setRenderer(this);
        setRenderMode(RENDERMODE_CONTINUOUSLY);
    }

    public void setMachine(Machine m, Demos d) { machine = m; demos = d; }
    public void setMaxFps(int fps) { maxFps = Math.max(1, Math.min(60, fps)); }
    public float getActualFps() { return fpsActual; }

    public int[] screenToPDS(float tx, float ty) {
        return new int[]{
            (int)(tx / getWidth()  * PDS),
            (int)((1f - ty / getHeight()) * PDS)
        };
    }

    // ── GLSurfaceView.Renderer ────────────────────────────────

    @Override
    public void onSurfaceCreated(GL10 unused, EGLConfig config) {
        prog = buildProg(VERT_SRC, FRAG_SRC);
        aPos   = GLES20.glGetAttribLocation(prog, "aPos");
        aColor = GLES20.glGetAttribLocation(prog, "aColor");

        // Allocate NIO buffers (stay in native heap, zero GC)
        vbLine = allocFB(MAX_VERTS);
        cbLine = allocFB(MAX_VERTS * 2);
        vbPt   = allocFB(MAX_VERTS / 4);
        cbPt   = allocFB(MAX_VERTS / 2);

        GLES20.glClearColor(0f, 0f, 0f, 1f);
        GLES20.glEnable(GLES20.GL_BLEND);
        GLES20.glBlendFunc(GLES20.GL_SRC_ALPHA, GLES20.GL_ONE_MINUS_SRC_ALPHA);
    }

    @Override
    public void onSurfaceChanged(GL10 unused, int w, int h) {
        GLES20.glViewport(0, 0, w, h);
        surfW = w; surfH = h;
    }

    @Override
    public void onDrawFrame(GL10 unused) {
        long t0 = System.nanoTime();
        Machine m = machine; Demos d = demos;
        if (m == null || d == null) { GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT); return; }

        // Clear screen every frame — no accumulation artifacts
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT);

        m.dlClear();
        d.runCurrentDemo();

        // Build vertex arrays
        buildBuffers(m);

        // Draw glow pass (wide, semi-transparent) then core beam
        if (nLine > 0) {
            drawVectors(false, 6.0f);  // outer glow
            drawVectors(false, 1.5f);  // core beam
        }
        if (nPt > 0) {
            drawVectors(true, 3.0f);
        }

        // FPS
        fpsCnt++;
        long now = System.nanoTime();
        if (now - fpsTime >= 1_000_000_000L) {
            fpsActual = fpsCnt;
            fpsCnt = 0;
            fpsTime = now;
        }

        // FPS cap (GLSurfaceView doesn't cap automatically)
        long budget = 1_000_000_000L / maxFps;
        long sleep  = (budget - (System.nanoTime() - t0)) / 1_000_000L;
        if (sleep > 1) try { Thread.sleep(sleep); } catch (InterruptedException ignored) {}
    }

    // ── Rendering helpers ─────────────────────────────────────

    private void buildBuffers(Machine m) {
        nLine = 0; nPt = 0;
        int nv = m.nvec;
        float scaleX = 2f / PDS, scaleY = 2f / PDS;

        for (int i = 0; i < nv; i++) {
            int br = m.vbr[i];
            if (br < 10) continue;

            float brf = br / 255f;
            // Phosphor green: r=0.08, g=1.0, b=0.25
            float r = 0.08f * brf, g = brf, b = 0.25f * brf;

            float x1 = m.vx1[i] * scaleX - 1f;
            float y1 = m.vy1[i] * scaleY - 1f;

            if (m.vpt[i]) {
                if (nPt + 2 < ptBuf.length) {
                    ptBuf[nPt]   = x1; ptBuf[nPt+1] = y1;
                    ptCol[nPt*2]   = r; ptCol[nPt*2+1] = g;
                    ptCol[nPt*2+2] = b; ptCol[nPt*2+3] = 1f;
                    nPt += 2;
                }
            } else {
                float x2 = m.vx2[i] * scaleX - 1f;
                float y2 = m.vy2[i] * scaleY - 1f;
                if (nLine + 4 < lineBuf.length) {
                    lineBuf[nLine]   = x1; lineBuf[nLine+1] = y1;
                    lineBuf[nLine+2] = x2; lineBuf[nLine+3] = y2;
                    int c = nLine * 2;
                    lineCol[c]   = r; lineCol[c+1] = g; lineCol[c+2] = b; lineCol[c+3] = 1f;
                    lineCol[c+4] = r; lineCol[c+5] = g; lineCol[c+6] = b; lineCol[c+7] = 1f;
                    nLine += 4;
                }
            }
        }

        // Upload to NIO buffers
        vbLine.position(0); vbLine.put(lineBuf, 0, nLine).position(0);
        cbLine.position(0); cbLine.put(lineCol, 0, nLine*2).position(0);
        vbPt.position(0);   vbPt.put(ptBuf, 0, nPt).position(0);
        cbPt.position(0);   cbPt.put(ptCol, 0, nPt*2).position(0);
    }

    private void drawVectors(boolean points, float lineWidth) {
        GLES20.glUseProgram(prog);
        GLES20.glLineWidth(lineWidth);

        FloatBuffer vb = points ? vbPt   : vbLine;
        FloatBuffer cb = points ? cbPt   : cbLine;
        int count      = points ? nPt/2  : nLine/2;

        GLES20.glEnableVertexAttribArray(aPos);
        GLES20.glEnableVertexAttribArray(aColor);
        GLES20.glVertexAttribPointer(aPos,   2, GLES20.GL_FLOAT, false, 0, vb);
        GLES20.glVertexAttribPointer(aColor, 4, GLES20.GL_FLOAT, false, 0, cb);

        GLES20.glDrawArrays(points ? GLES20.GL_POINTS : GLES20.GL_LINES, 0, count);

        GLES20.glDisableVertexAttribArray(aPos);
        GLES20.glDisableVertexAttribArray(aColor);
    }

    // ── GL utilities ──────────────────────────────────────────

    private static int buildProg(String vs, String fs) {
        int v = compileShader(GLES20.GL_VERTEX_SHADER,   vs);
        int f = compileShader(GLES20.GL_FRAGMENT_SHADER, fs);
        int p = GLES20.glCreateProgram();
        GLES20.glAttachShader(p, v);
        GLES20.glAttachShader(p, f);
        GLES20.glLinkProgram(p);
        return p;
    }

    private static int compileShader(int type, String src) {
        int s = GLES20.glCreateShader(type);
        GLES20.glShaderSource(s, src);
        GLES20.glCompileShader(s);
        return s;
    }

    private static FloatBuffer allocFB(int floats) {
        return ByteBuffer.allocateDirect(floats * 4)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer();
    }
}
