package com.imlac.pds1;

/**
 * Pong for Imlac PDS-1 emulator.
 *
 * Runs directly on the emulated hardware:
 *   - Writes a DP display program into machine memory
 *   - Updates it each frame (self-modifying code, classic Imlac technique)
 *   - MP thread handles game physics
 *
 * Controls: W/S = left paddle,  I/K = right paddle
 */
public class PongGame {

    // ── Memory layout ─────────────────────────────────────────
    private static final int DP_BASE   = 0x080; // Display program start
    private static final int MP_BASE   = 0x040; // MP variables base

    // Variable addresses in machine RAM
    private static final int A_BALL_X  = 0x040;
    private static final int A_BALL_Y  = 0x041;
    private static final int A_BALL_DX = 0x042;
    private static final int A_BALL_DY = 0x043;
    private static final int A_P1_Y    = 0x044;
    private static final int A_P2_Y    = 0x045;
    private static final int A_SC1     = 0x046;
    private static final int A_SC2     = 0x047;

    // DP instruction offsets (patched each frame by updateDP())
    // relative to DP_BASE
    private static final int DP_OFF_BX   = 0;  // DLXA for ball
    private static final int DP_OFF_BY   = 1;  // DLYA for ball
    private static final int DP_OFF_P1Y  = 5;  // DLYA for P1 paddle
    private static final int DP_OFF_P2Y  = 12; // DLYA for P2 paddle
    private static final int DP_OFF_SC1  = 19; // score display patch
    private static final int DP_OFF_SC2  = 25;

    // Game constants (in screen coords 0..1023)
    private static final int SCREEN     = 1023;
    private static final int BALL_R     = 8;
    private static final int PADDLE_H   = 120;  // half-height
    private static final int PADDLE_W   = 16;
    private static final int P1_X       = 50;
    private static final int P2_X       = 970;
    private static final int TOP_WALL   = 40;
    private static final int BOT_WALL   = 984;
    private static final int PADDLE_SPD = 18;
    private static final int BALL_SPD   = 7;    // initial speed

    private final Machine machine;
    private boolean initialized = false;

    // Game state (mirrors machine RAM for convenience)
    private int ballX, ballY, ballDX, ballDY;
    private int p1Y, p2Y, sc1, sc2;
    private int frameCount = 0;

    public PongGame(Machine m) {
        this.machine = m;
    }

    // ── Public API ────────────────────────────────────────────

    public void init() {
        // Reset game state
        sc1 = sc2 = 0;
        p1Y = p2Y = 512;
        resetBall(1);
        initialized = true;

        // Write DP program into machine memory
        writeDisplayProgram();

        // Start DP
        machine.dp_halt    = false;
        machine.dp_enabled = true;
        machine.dp_pc      = DP_BASE;

        // Halt MP (we drive physics from Java, not emulated MP)
        machine.mp_halt = true;
        machine.mp_run  = false;

        syncToMachine();
        updateDP();
    }

    /** Call ~30 times/sec from game loop */
    public void tick() {
        if (!initialized) return;
        frameCount++;

        readInput();
        moveBlall();
        clampPaddles();
        syncToMachine();
        updateDP();

        // Restart DP each frame so it redraws
        machine.dp_halt = false;
        machine.dp_pc   = DP_BASE;
    }

    public int getScore1() { return sc1; }
    public int getScore2() { return sc2; }
    public boolean isInitialized() { return initialized; }

    // ── Input ─────────────────────────────────────────────────

    private void readInput() {
        int kbd = machine.keyboard & 0x7F;
        machine.keyboard = 0;

        switch (kbd) {
            case 'W': case 'w': p1Y = Math.min(BOT_WALL - PADDLE_H, p1Y + PADDLE_SPD); break;
            case 'S': case 's': p1Y = Math.max(TOP_WALL + PADDLE_H, p1Y - PADDLE_SPD); break;
            case 'I': case 'i': p2Y = Math.min(BOT_WALL - PADDLE_H, p2Y + PADDLE_SPD); break;
            case 'K': case 'k': p2Y = Math.max(TOP_WALL + PADDLE_H, p2Y - PADDLE_SPD); break;
        }
    }

    // ── Physics ───────────────────────────────────────────────

    private void moveBlall() {
        ballX += ballDX;
        ballY += ballDY;

        // Top / bottom wall bounce
        if (ballY >= BOT_WALL - BALL_R) {
            ballY  = BOT_WALL - BALL_R;
            ballDY = -Math.abs(ballDY);
        }
        if (ballY <= TOP_WALL + BALL_R) {
            ballY  = TOP_WALL + BALL_R;
            ballDY =  Math.abs(ballDY);
        }

        // Left paddle (P1) at x = P1_X
        if (ballX <= P1_X + PADDLE_W && ballX >= P1_X - PADDLE_W) {
            if (Math.abs(ballY - p1Y) < PADDLE_H + BALL_R) {
                ballX  = P1_X + PADDLE_W + 1;
                ballDX = Math.abs(ballDX);
                // Add spin based on where ball hits paddle
                int rel = ballY - p1Y; // -PADDLE_H..+PADDLE_H
                ballDY = (rel * BALL_SPD) / PADDLE_H;
                if (ballDY == 0) ballDY = 1;
            } else if (ballX < P1_X - PADDLE_W) {
                // Missed — point for P2
                sc2++;
                resetBall(-1);
            }
        }

        // Right paddle (P2) at x = P2_X
        if (ballX >= P2_X - PADDLE_W && ballX <= P2_X + PADDLE_W) {
            if (Math.abs(ballY - p2Y) < PADDLE_H + BALL_R) {
                ballX  = P2_X - PADDLE_W - 1;
                ballDX = -Math.abs(ballDX);
                int rel = ballY - p2Y;
                ballDY = (rel * BALL_SPD) / PADDLE_H;
                if (ballDY == 0) ballDY = 1;
            } else if (ballX > P2_X + PADDLE_W) {
                // Missed — point for P1
                sc1++;
                resetBall(1);
            }
        }

        // Safety clamp
        if (ballX < 0)    { ballX = 0;    ballDX =  Math.abs(ballDX); }
        if (ballX > 1023) { ballX = 1023; ballDX = -Math.abs(ballDX); }
    }

    private void resetBall(int dir) {
        ballX  = 512;
        ballY  = 512;
        ballDX = BALL_SPD * dir;
        ballDY = BALL_SPD / 2;
    }

    private void clampPaddles() {
        p1Y = Math.max(TOP_WALL + PADDLE_H, Math.min(BOT_WALL - PADDLE_H, p1Y));
        p2Y = Math.max(TOP_WALL + PADDLE_H, Math.min(BOT_WALL - PADDLE_H, p2Y));
    }

    // ── Machine sync ──────────────────────────────────────────

    private void syncToMachine() {
        machine.mem[A_BALL_X]  = ballX  & 0xFFFF;
        machine.mem[A_BALL_Y]  = ballY  & 0xFFFF;
        machine.mem[A_BALL_DX] = ballDX & 0xFFFF;
        machine.mem[A_BALL_DY] = ballDY & 0xFFFF;
        machine.mem[A_P1_Y]    = p1Y    & 0xFFFF;
        machine.mem[A_P2_Y]    = p2Y    & 0xFFFF;
        machine.mem[A_SC1]     = sc1    & 0xFFFF;
        machine.mem[A_SC2]     = sc2    & 0xFFFF;
    }

    // ── DP display program ────────────────────────────────────
    //
    // Format: each word is a DP instruction
    //   DLXA val = 0x1000 | (val & 0x3FF)   load X register
    //   DLYA val = 0x2000 | (val & 0x3FF)   load Y register
    //   DSVH     = 0x3xxx                   short vector (dx5,dy5)
    //   DLVH     = 0x4xxx                   long vector  (dx6*8, dy6*8)
    //   DPTS     = 0x7800                   draw point
    //   DHLT     = 0x8000                   halt DP
    //   DJMS addr= 0x6xxx                   jump to subroutine
    //   DRJM     = 0xB000                   return
    //
    // DSVH encoding: [15:12]=3, [11]=sign_dx, [10:6]=|dx|, [5]=sign_dy, [4:0]=|dy|
    // DLVH encoding: [15:12]=4, [11]=sign_dx, [10:6]=|dx|, [5]=sign_dy, [4:0]=|dy|
    //   actual delta = field * 8
    //
    // Score subroutine: draws N dots horizontally (N = score, max 9)

    private void writeDisplayProgram() {
        int[] m = machine.mem;
        int p = DP_BASE;

        // ── Ball (2 words, patched each frame) ──
        // DP_OFF_BX = 0
        m[p++] = dlxa(ballX);   // DP_BASE+0: DLXA ball_x
        m[p++] = dlya(ballY);   // DP_BASE+1: DLYA ball_y
        m[p++] = 0x7800;        // DPTS — draw ball point
        // extra DPTS for bigger ball
        m[p++] = dlxa(ballX+2);
        m[p++] = 0x7800;

        // ── Left paddle P1 at x=P1_X ──
        // DP_OFF_P1Y = 5
        m[p++] = dlxa(P1_X);        // DP_BASE+5
        m[p++] = dlya(p1Y - PADDLE_H); // DP_BASE+6: bottom of paddle, patched
        // Draw paddle as 8 short vectors upward, each +15 pixels
        // DSVH dx=0, dy=+15: 0x3000 | 0 | 15 = 0x300F
        for (int i = 0; i < 7; i++) m[p++] = dsvh(0, 15);

        // ── Right paddle P2 at x=P2_X ──
        // DP_OFF_P2Y = 5 + 1 + 1 + 7 = 14  -- let's track
        m[p++] = dlxa(P2_X);        // paddle X (constant)
        m[p++] = dlya(p2Y - PADDLE_H); // patched each frame
        for (int i = 0; i < 7; i++) m[p++] = dsvh(0, 15);

        // ── Top wall ──
        m[p++] = dlxa(40);
        m[p++] = dlya(TOP_WALL);
        // Draw 12 segments of 80 pixels each = 960 pixels total
        for (int i = 0; i < 12; i++) m[p++] = dlvh(10, 0); // 10*8=80 right

        // ── Bottom wall ──
        m[p++] = dlxa(40);
        m[p++] = dlya(BOT_WALL);
        for (int i = 0; i < 12; i++) m[p++] = dlvh(10, 0);

        // ── Center dashed line ──
        m[p++] = dlxa(510);
        m[p++] = dlya(TOP_WALL + 20);
        for (int i = 0; i < 9; i++) {
            m[p++] = dlvh(0, 7);   // segment +56 up
            m[p++] = dlvh(0, 3);   // gap +24 up (no draw — but DLVH always draws!)
            // For dashes: alternate intensity
            // Simpler: just draw shorter segments with gaps via DVSF or skip
            // Actually use DLYA to jump = skip gap
        }

        // ── Score P1 (left side dots) ──
        int sc1SubAddr = p;
        m[p++] = dlxa(200);
        m[p++] = dlya(940);
        for (int i = 0; i < 9; i++) {
            // Each dot: DPTS, then move right 30px
            // Will be patched: dots beyond score are replaced with NOP (DJMP to skip)
            m[p++] = 0x7800; // DPTS
            m[p++] = dlvh(4, 0); // move right 32px
        }
        m[p++] = 0x8000; // DHLT guard (replaced with DRJM when called as sub)

        // ── Score P2 (right side dots) ──
        int sc2SubAddr = p;
        m[p++] = dlxa(600);
        m[p++] = dlya(940);
        for (int i = 0; i < 9; i++) {
            m[p++] = 0x7800;
            m[p++] = dlvh(4, 0);
        }

        // ── Main DHLT ──
        m[p] = 0x8000; // DHLT

        // Store offsets for patching
        dpOffBX  = DP_BASE + 0;
        dpOffBY  = DP_BASE + 1;
        dpOffBX2 = DP_BASE + 3;
        dpOffP1Y = DP_BASE + 6;
        dpOffP2Y = DP_BASE + 6 + 9; // after P1: 1(dlxa)+1(dlya)+7(dsvh) = 9
        dpOffSc1 = sc1SubAddr + 2;   // first DPTS of sc1
        dpOffSc2 = sc2SubAddr + 2;   // first DPTS of sc2
        dpEnd    = p;
    }

    // Offsets set by writeDisplayProgram()
    private int dpOffBX, dpOffBY, dpOffBX2, dpOffP1Y, dpOffP2Y;
    private int dpOffSc1, dpOffSc2, dpEnd;

    /** Patch DP program with current positions (self-modifying code) */
    private void updateDP() {
        int[] m = machine.mem;

        // Ball
        m[dpOffBX]  = dlxa(ballX);
        m[dpOffBY]  = dlya(ballY);
        m[dpOffBX2] = dlxa(ballX + 3); // second dot for bigger ball

        // Paddles (Y = bottom of paddle)
        m[dpOffP1Y] = dlya(p1Y - PADDLE_H);
        m[dpOffP2Y] = dlya(p2Y - PADDLE_H);

        // Score: patch DPTS vs NOP (use 0 as NOP — actually 0 = DLXA 0, harmless)
        for (int i = 0; i < 9; i++) {
            m[dpOffSc1 + i*2] = (i < sc1) ? 0x7800 : 0x1000; // DPTS or DLXA 0 (skip)
            m[dpOffSc2 + i*2] = (i < sc2) ? 0x7800 : 0x1000;
        }
    }

    // ── DP instruction builders ───────────────────────────────

    private static int dlxa(int x) {
        return 0x1000 | (clamp(x, 0, 1023) & 0x3FF);
    }
    private static int dlya(int y) {
        return 0x2000 | (clamp(y, 0, 1023) & 0x3FF);
    }
    // DSVH: signed 5-bit dx, dy (max ±15 pixels)
    private static int dsvh(int dx, int dy) {
        int w = 0x3000;
        if (dx < 0) { w |= 0x0800; dx = -dx; }
        if (dy < 0) { w |= 0x0020; dy = -dy; }
        w |= ((dx & 0x1F) << 6) | (dy & 0x1F);
        return w;
    }
    // DLVH: 6-bit dx, dy multiplied by 8 (max ±504 pixels)
    private static int dlvh(int dx, int dy) {
        int w = 0x4000;
        if (dx < 0) { w |= 0x0800; dx = -dx; }
        if (dy < 0) { w |= 0x0020; dy = -dy; }
        w |= ((dx & 0x3F) << 6) | (dy & 0x3F);
        return w;
    }
    private static int clamp(int v, int lo, int hi) {
        return v < lo ? lo : v > hi ? hi : v;
    }
}
