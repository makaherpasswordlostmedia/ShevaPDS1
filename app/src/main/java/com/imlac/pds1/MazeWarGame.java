package com.imlac.pds1;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

/**
 * ================================================================
 *  MAZE WAR — Imlac PDS-1 Edition
 *
 *  Faithful recreation of the 1974 original by Steve Colley,
 *  Greg Thompson & Howard Palmer (NASA Ames / MIT AI Lab).
 *
 *  Original ran on Imlac PDS-1 with ~2KB of display code.
 *  This implementation runs as a native Java demo inside the
 *  emulator, using the Machine display list API (dlLine/dlPoint).
 *
 *  Architecture mirrors the original:
 *  - Grid-based orthogonal movement (no free-roam)
 *  - Raycasting for first-person view (DDA algorithm)
 *  - Vector rendering — only lines and points, no fill
 *  - Eyeball enemies (the famous PDS-1 sprites)
 *  - Bullets travel through corridors
 *  - Score tracking
 *
 *  Controls (map to Machine.keyboard):
 *    W / UP    = move forward
 *    S / DOWN  = move backward
 *    A / LEFT  = turn left
 *    D / RIGHT = turn right
 *    SPACE / F = fire
 *    M         = toggle minimap
 * ================================================================
 */
public class MazeWarGame {

    // ── Display constants ──────────────────────────────────────
    private static final int SCR_W  = 1024;
    private static final int SCR_H  = 1024;
    private static final int HALF_H = SCR_H / 2;

    // ── Maze ──────────────────────────────────────────────────
    public  static final int MZ = 16;   // maze size 16x16
    // Wall bits: 0=North(+Y), 1=East(+X), 2=South(-Y), 3=West(-X)
    private final int[] maze = new int[MZ * MZ];

    private static final int[] DX  = { 0, 1, 0, -1};
    private static final int[] DY  = { 1, 0,-1,  0};
    private static final int[] OPP = { 2, 3, 0,  1};

    // ── Player ────────────────────────────────────────────────
    private int   px    = 1;   // grid x
    private int   py    = 1;   // grid y
    private int   pdir  = 0;   // 0=N 1=E 2=S 3=W
    private int   pHP   = 3;
    private int   score = 0;
    private int   level = 1;

    private int   fireCooldown = 0;
    private int   moveCooldown = 0;
    private int   turnCooldown = 0;
    private int   flashTimer   = 0;  // red flash on hit
    private int   killFlash    = 0;  // green flash on kill
    private int   msgTimer     = 0;
    private String msgText     = "";

    // ── Enemies ───────────────────────────────────────────────
    private static class Enemy {
        int   gx, gy;          // grid position
        int   dir;             // facing direction
        int   hp     = 1;
        int   think  = 30;     // AI think timer
        int   cool   = 80;     // fire cooldown
        boolean alive = true;
    }
    private final List<Enemy> enemies = new ArrayList<>();

    // ── Bullets ───────────────────────────────────────────────
    private static class Bullet {
        double x, y;           // floating point position
        int    dir;
        boolean isPlayer;
        int    life = 60;
        boolean alive = true;
    }
    private final List<Bullet> bullets = new ArrayList<>();

    // ── Game state ────────────────────────────────────────────
    public enum State { TITLE, PLAYING, DEAD, WIN }
    private State state = State.TITLE;
    private int   titleFrame = 0;

    // ── Input ─────────────────────────────────────────────────
    private boolean kFwd, kBack, kLeft, kRight, kFire;
    private int     prevKeyboard = 0;
    private boolean prevAnyKey   = false;

    /** Called from EmulatorActivity with controller state each frame */
    public void setInput(boolean up, boolean down, boolean left, boolean right,
                         boolean fire, int keyboard) {
        kFwd   = up;
        kBack  = down;
        kLeft  = left;
        kRight = right;
        kFire  = fire;

        // Also accept keyboard for M toggle and any-key on title/dead
        int k = keyboard & 0x7F;
        boolean anyNew = (keyboard != 0 && prevKeyboard == 0);
        if (anyNew) {
            if (state == State.TITLE) startGame();
            if (state == State.DEAD)  startGame();
        }
        if (k == 'M' && (prevKeyboard & 0x7F) != 'M') showMinimap = !showMinimap;
        prevKeyboard = keyboard;
    }

    // ── Minimap ───────────────────────────────────────────────
    private boolean showMinimap = false;

    // ── Machine ref ───────────────────────────────────────────
    private final Machine M;

    // ── Vector font (same as Demos.java) ──────────────────────
    private static final float[][][] FONT = {
        /*A*/ {{0,0,2,4},{2,4,4,0},{1,2,3,2}},
        /*B*/ {{0,0,0,4},{0,4,2,4},{0,2,2,2},{0,0,2,0},{2,4,3,3},{3,3,2,2},{2,2,3,1},{3,1,2,0}},
        /*C*/ {{3,4,0,4},{0,4,0,0},{0,0,3,0}},
        /*D*/ {{0,0,0,4},{0,4,2,4},{2,4,4,2},{4,2,2,0},{2,0,0,0}},
        /*E*/ {{0,0,0,4},{0,4,4,4},{0,2,3,2},{0,0,4,0}},
        /*F*/ {{0,0,0,4},{0,4,4,4},{0,2,3,2}},
        /*G*/ {{3,4,0,4},{0,4,0,0},{0,0,4,0},{4,0,4,2},{4,2,2,2}},
        /*H*/ {{0,0,0,4},{4,0,4,4},{0,2,4,2}},
        /*I*/ {{1,0,3,0},{1,4,3,4},{2,0,2,4}},
        /*J*/ {{1,4,3,4},{3,4,3,0},{3,0,0,0}},
        /*K*/ {{0,0,0,4},{0,2,4,4},{0,2,4,0}},
        /*L*/ {{0,4,0,0},{0,0,4,0}},
        /*M*/ {{0,0,0,4},{0,4,2,2},{2,2,4,4},{4,4,4,0}},
        /*N*/ {{0,0,0,4},{0,4,4,0},{4,0,4,4}},
        /*O*/ {{0,0,4,0},{4,0,4,4},{4,4,0,4},{0,4,0,0}},
        /*P*/ {{0,0,0,4},{0,4,3,4},{3,4,4,3},{4,3,3,2},{3,2,0,2}},
        /*Q*/ {{0,0,4,0},{4,0,4,4},{4,4,0,4},{0,4,0,0},{2,2,4,0}},
        /*R*/ {{0,0,0,4},{0,4,3,4},{3,4,4,3},{4,3,3,2},{3,2,0,2},{2,2,4,0}},
        /*S*/ {{4,4,0,4},{0,4,0,2},{0,2,4,2},{4,2,4,0},{4,0,0,0}},
        /*T*/ {{0,4,4,4},{2,4,2,0}},
        /*U*/ {{0,4,0,0},{0,0,4,0},{4,0,4,4}},
        /*V*/ {{0,4,2,0},{2,0,4,4}},
        /*W*/ {{0,4,1,0},{1,0,2,2},{2,2,3,0},{3,0,4,4}},
        /*X*/ {{0,0,4,4},{4,0,0,4}},
        /*Y*/ {{0,4,2,2},{4,4,2,2},{2,2,2,0}},
        /*Z*/ {{0,4,4,4},{4,4,0,0},{0,0,4,0}},
        /*0*/ {{0,0,4,0},{4,0,4,4},{4,4,0,4},{0,4,0,0},{0,0,4,4}},
        /*1*/ {{1,4,2,4},{2,4,2,0},{1,0,3,0}},
        /*2*/ {{0,4,4,4},{4,4,4,3},{4,3,0,1},{0,1,0,0},{0,0,4,0}},
        /*3*/ {{0,4,4,4},{4,4,4,0},{0,0,4,0},{0,2,4,2}},
        /*4*/ {{0,4,0,2},{0,2,4,2},{4,4,4,0}},
        /*5*/ {{4,4,0,4},{0,4,0,2},{0,2,4,2},{4,2,4,0},{4,0,0,0}},
        /*6*/ {{4,4,0,4},{0,4,0,0},{0,0,4,0},{4,0,4,2},{4,2,0,2}},
        /*7*/ {{0,4,4,4},{4,4,2,0}},
        /*8*/ {{0,0,4,0},{4,0,4,4},{4,4,0,4},{0,4,0,0},{0,2,4,2}},
        /*9*/ {{4,0,4,4},{4,4,0,4},{0,4,0,2},{0,2,4,2}},
        /*-*/ {{0,2,4,2}},
        /*:*/ {{2,1,2,1},{2,3,2,3}},
        /*!*/ {{2,4,2,1},{2,0,2,0}},
        /* */ {}
    };
    private static final String CHARSET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-:! ";

    // ================================================================
    //  CONSTRUCTOR
    // ================================================================
    public MazeWarGame(Machine machine) {
        this.M = machine;
    }

    // ================================================================
    //  PUBLIC API — called by Demos.java each frame
    // ================================================================
    public void update(int keyboard) {
        readInput(keyboard);  // keyboard fallback only; main input via setInput()
        switch (state) {
            case TITLE:   updateTitle();   break;
            case PLAYING: updatePlaying(); break;
            case DEAD:    updateDead();    break;
            case WIN:     updateWin();     break;
        }
        titleFrame++;
    }

    public void render() {
        switch (state) {
            case TITLE:   renderTitle();   break;
            case PLAYING: renderPlaying(); break;
            case DEAD:    renderDead();    break;
            case WIN:     renderWin();     break;
        }
    }

    // ================================================================
    //  INPUT
    // ================================================================
    private boolean keyJustPressed(int keyboard, char c) {
        return (keyboard & 0x7F) == (c & 0x7F) && (prevKeyboard & 0x7F) != (c & 0x7F);
    }

    private void readInput(int keyboard) {
        // Keyboard fallback (only if no controller input)
        int k = keyboard & 0x7F;
        if (!kFwd && !kBack && !kLeft && !kRight) {
            kFwd   = (k == 'W'); kBack  = (k == 'S');
            kLeft  = (k == 'A'); kRight = (k == 'D');
        }
        if (!kFire) kFire = (k == ' ' || k == 'F');
    }

    // ================================================================
    //  GAME INIT
    // ================================================================
    private void startGame() {
        generateMaze();
        px = 1; py = 1; pdir = 0;
        pHP = 3; score = 0; level = 1;
        fireCooldown = 0; moveCooldown = 0; turnCooldown = 0;
        flashTimer = 0; killFlash = 0;
        bullets.clear();
        spawnEnemies(level + 1);
        state = State.PLAYING;
    }

    // ================================================================
    //  MAZE GENERATION (recursive backtracker)
    // ================================================================
    private void generateMaze() {
        Arrays.fill(maze, 0xF);  // all walls
        boolean[] visited = new boolean[MZ * MZ];
        carve(1, 1, visited);
    }

    private void carve(int x, int y, boolean[] visited) {
        visited[y * MZ + x] = true;
        int[] dirs = {0, 1, 2, 3};
        // Fisher-Yates shuffle
        for (int i = 3; i > 0; i--) {
            int j = (int)(Math.random() * (i + 1));
            int tmp = dirs[i]; dirs[i] = dirs[j]; dirs[j] = tmp;
        }
        for (int d : dirs) {
            int nx = x + DX[d], ny = y + DY[d];
            if (nx < 1 || nx >= MZ-1 || ny < 1 || ny >= MZ-1) continue;
            if (visited[ny * MZ + nx]) continue;
            maze[y * MZ + x]   &= ~(1 << d);
            maze[ny * MZ + nx] &= ~(1 << OPP[d]);
            carve(nx, ny, visited);
        }
    }

    private boolean hasWall(int x, int y, int dir) {
        if (x < 0 || x >= MZ || y < 0 || y >= MZ) return true;
        return (maze[y * MZ + x] & (1 << dir)) != 0;
    }

    private boolean isSolid(int x, int y) {
        if (x < 0 || x >= MZ || y < 0 || y >= MZ) return true;
        return maze[y * MZ + x] == 0xF;
    }

    // ================================================================
    //  ENEMY SPAWN
    // ================================================================
    private void spawnEnemies(int n) {
        enemies.clear();
        for (int i = 0; i < n; i++) {
            Enemy e = new Enemy();
            int attempts = 0;
            do {
                e.gx = 2 + (int)(Math.random() * (MZ - 4));
                e.gy = 2 + (int)(Math.random() * (MZ - 4));
                attempts++;
            } while (attempts < 100 &&
                     (isSolid(e.gx, e.gy) ||
                      (Math.abs(e.gx - px) < 3 && Math.abs(e.gy - py) < 3)));
            e.dir = (int)(Math.random() * 4);
            e.think = 20 + (int)(Math.random() * 40);
            e.cool  = 60 + (int)(Math.random() * 60);
            enemies.add(e);
        }
    }

    // ================================================================
    //  UPDATE — PLAYING
    // ================================================================
    private void updatePlaying() {
        if (moveCooldown > 0) moveCooldown--;
        if (turnCooldown > 0) turnCooldown--;
        if (fireCooldown > 0) fireCooldown--;
        if (flashTimer   > 0) flashTimer--;
        if (killFlash    > 0) killFlash--;
        if (msgTimer     > 0) msgTimer--;

        // Player movement (grid-based)
        if (turnCooldown == 0) {
            if (kLeft)  { pdir = (pdir + 3) % 4; turnCooldown = 8; }
            else if (kRight) { pdir = (pdir + 1) % 4; turnCooldown = 8; }
        }
        if (moveCooldown == 0) {
            if (kFwd  && !hasWall(px, py, pdir)) {
                px += DX[pdir]; py += DY[pdir]; moveCooldown = 10;
            } else if (kBack && !hasWall(px, py, (pdir+2)%4)) {
                px -= DX[pdir]; py -= DY[pdir]; moveCooldown = 10;
            }
        }

        // Fire
        if (kFire && fireCooldown == 0) {
            Bullet b = new Bullet();
            b.x = px + 0.5; b.y = py + 0.5;
            b.dir = pdir; b.isPlayer = true;
            bullets.add(b);
            fireCooldown = 18;
        }

        updateBullets();
        updateEnemies();
        checkLevelClear();
    }

    private void updateBullets() {
        for (Bullet b : bullets) {
            if (!b.alive) continue;
            b.life--;
            if (b.life <= 0) { b.alive = false; continue; }

            double speed = 0.18;
            b.x += DX[b.dir] * speed;
            b.y += DY[b.dir] * speed;

            int gx = (int) b.x, gy = (int) b.y;
            if (isSolid(gx, gy)) { b.alive = false; continue; }

            if (b.isPlayer) {
                for (Enemy e : enemies) {
                    if (!e.alive) continue;
                    if (Math.abs(b.x - (e.gx+0.5)) < 0.6 &&
                        Math.abs(b.y - (e.gy+0.5)) < 0.6) {
                        e.alive = false; b.alive = false;
                        score++;
                        killFlash = 12;
                        showMsg("KILL!", 35);
                        break;
                    }
                }
            } else {
                if (Math.abs(b.x - (px+0.5)) < 0.55 &&
                    Math.abs(b.y - (py+0.5)) < 0.55) {
                    b.alive = false;
                    pHP--;
                    flashTimer = 18;
                    showMsg(pHP > 0 ? "HIT! HP:" + pHP : "YOU DIED", 50);
                    if (pHP <= 0) {
                        state = State.DEAD;
                    }
                }
            }
        }
        bullets.removeIf(b -> !b.alive);
    }

    private void updateEnemies() {
        for (Enemy e : enemies) {
            if (!e.alive) continue;

            e.think--;
            e.cool--;

            if (e.think <= 0) {
                e.think = 15 + (int)(Math.random() * 25);

                int dx = px - e.gx, dy = py - e.gy;
                int wantDir = -1;
                if (Math.abs(dx) > Math.abs(dy)) wantDir = dx > 0 ? 1 : 3;
                else if (dy != 0)                wantDir = dy > 0 ? 0 : 2;

                // 65% chance chase, 35% random
                if (Math.random() < 0.65 && wantDir >= 0 && !hasWall(e.gx, e.gy, wantDir)) {
                    e.dir = wantDir;
                    e.gx += DX[wantDir]; e.gy += DY[wantDir];
                } else {
                    // try random open direction
                    int[] shuffled = {0,1,2,3};
                    for (int i=3;i>0;i--){int j=(int)(Math.random()*(i+1));int tmp=shuffled[i];shuffled[i]=shuffled[j];shuffled[j]=tmp;}
                    for (int d : shuffled) {
                        if (!hasWall(e.gx, e.gy, d)) {
                            e.dir = d;
                            e.gx += DX[d]; e.gy += DY[d];
                            break;
                        }
                    }
                }
            }

            // Shoot if facing player along clear corridor
            if (e.cool <= 0) {
                boolean aligned = false;
                if (e.dir==0 && e.gx==px && py>e.gy) aligned=corridorClear(e.gx,e.gy,px,py);
                if (e.dir==2 && e.gx==px && py<e.gy) aligned=corridorClear(px,py,e.gx,e.gy);
                if (e.dir==1 && e.gy==py && px>e.gx) aligned=corridorClear(e.gx,e.gy,px,py);
                if (e.dir==3 && e.gy==py && px<e.gx) aligned=corridorClear(px,py,e.gx,e.gy);

                if (aligned) {
                    Bullet b = new Bullet();
                    b.x = e.gx+0.5; b.y = e.gy+0.5;
                    b.dir = e.dir; b.isPlayer = false;
                    bullets.add(b);
                    e.cool = 70 + (int)(Math.random()*50);
                }
            }
        }
    }

    private boolean corridorClear(int x1, int y1, int x2, int y2) {
        // Check no walls between (x1,y1)..(x2,y2) along same row/col
        if (x1 == x2) {
            for (int y = y1; y < y2; y++)
                if (hasWall(x1, y, 0)) return false;
        } else {
            for (int x = x1; x < x2; x++)
                if (hasWall(x, y1, 1)) return false;
        }
        return true;
    }

    private void checkLevelClear() {
        boolean any = false;
        for (Enemy e : enemies) if (e.alive) { any = true; break; }
        if (!any) {
            level++;
            showMsg("LEVEL " + level + "!", 70);
            generateMaze();
            px = 1; py = 1; pdir = 0;
            bullets.clear();
            spawnEnemies(Math.min(level + 1, 6));
        }
    }

    private void showMsg(String txt, int dur) { msgText = txt; msgTimer = dur; }

    // ================================================================
    //  RAYCASTING — DDA algorithm
    //  Returns wall distance for a given ray angle
    // ================================================================
    private static class RayHit {
        double dist;
        int    side;   // 0=EW wall, 1=NS wall
    }
    private final RayHit rayHit = new RayHit();

    private void castRay(double rayAngle) {
        double sinA = Math.sin(rayAngle);
        double cosA = Math.cos(rayAngle);

        int mapX = px, mapY = py;
        double posX = px + 0.5, posY = py + 0.5;

        double dX = Math.abs(cosA) < 1e-9 ? 1e9 : Math.abs(1.0 / cosA);
        double dY = Math.abs(sinA) < 1e-9 ? 1e9 : Math.abs(1.0 / sinA);

        int stepX, stepY;
        double sideX, sideY;

        if (cosA < 0) { stepX=-1; sideX=(posX-mapX)*dX; }
        else           { stepX= 1; sideX=(mapX+1-posX)*dX; }
        if (sinA < 0) { stepY=-1; sideY=(posY-mapY)*dY; }
        else           { stepY= 1; sideY=(mapY+1-posY)*dY; }

        int side = 0;
        for (int i = 0; i < 64; i++) {
            if (sideX < sideY) { sideX+=dX; mapX+=stepX; side=0; }
            else               { sideY+=dY; mapY+=stepY; side=1; }
            if (isSolid(mapX, mapY)) break;
        }

        double dist = (side==0) ? (sideX-dX) : (sideY-dY);
        rayHit.dist = Math.max(0.01, dist);
        rayHit.side = side;
    }

    // ================================================================
    //  RENDER — PLAYING
    //  All rendering through Machine display list (dlLine / dlPoint)
    // ================================================================
    private static final double FOV      = Math.PI / 2.2;  // ~82°
    private static final int    N_RAYS   = 48;             // PDS-1 style: few wide columns
    private static final int    VIEW_X0  = 30;
    private static final int    VIEW_X1  = 780;
    private static final int    VIEW_Y0  = 80;
    private static final int    VIEW_Y1  = 940;
    private static final int    VIEW_W   = VIEW_X1 - VIEW_X0;
    private static final int    VIEW_H   = VIEW_Y1 - VIEW_Y0;
    private static final int    VIEW_CX  = (VIEW_X0 + VIEW_X1) / 2;
    private static final int    VIEW_CY  = (VIEW_Y0 + VIEW_Y1) / 2;

    private void renderPlaying() {
        // Flash effects
        if (flashTimer > 0) {
            // Red border flash on hit
            float fb = (float)flashTimer / 18f;
            vl(0,0,SCR_W,0,fb); vl(SCR_W,0,SCR_W,SCR_H,fb);
            vl(SCR_W,SCR_H,0,SCR_H,fb); vl(0,SCR_H,0,0,fb);
        }
        if (killFlash > 0) {
            float fb = (float)killFlash / 12f * 0.5f;
            vl(VIEW_X0,VIEW_Y0,VIEW_X1,VIEW_Y0,fb);
            vl(VIEW_X0,VIEW_Y1,VIEW_X1,VIEW_Y1,fb);
        }

        // CRT border
        vl(VIEW_X0, VIEW_Y0, VIEW_X1, VIEW_Y0, 0.5f);
        vl(VIEW_X1, VIEW_Y0, VIEW_X1, VIEW_Y1, 0.5f);
        vl(VIEW_X1, VIEW_Y1, VIEW_X0, VIEW_Y1, 0.5f);
        vl(VIEW_X0, VIEW_Y1, VIEW_X0, VIEW_Y0, 0.5f);

        // Horizon line
        vl(VIEW_X0, VIEW_CY, VIEW_X1, VIEW_CY, 0.08f);

        // pdir: 0=North(+Y) 1=East(+X) 2=South(-Y) 3=West(-X)
        double playerAngle = Math.PI / 2.0 - pdir * (Math.PI / 2.0);

        // ── Authentic Maze War wireframe corridor renderer ──
        // Draws wall geometry depth-by-depth, exactly like PDS-1 original:
        //   - Project each depth slice to screen trapezoid
        //   - Draw back wall, left wall, right wall per cell
        // No raycasting columns — pure geometric projection

        // View frustum half-width at distance d: halfW(d) = VIEW_W/2 / d * 0.5
        // Screen coords: center=(VIEW_CX, VIEW_CY), full height=VIEW_H
        // At distance d, wall projects to height: VIEW_H / d (capped)
        // Wall left/right edge at distance d: VIEW_CX ± VIEW_W/2/d (capped to view)

        final int MAX_DEPTH = 10;
        final int VCX = VIEW_CX, VCY = VIEW_CY;
        final int VH2 = VIEW_H / 2;
        final int VW2 = VIEW_W / 2;

        // Walk forward from player, tracking left/right wall openings
        int fx = px, fy = py;
        int fdx = DX[pdir], fdy = DY[pdir];
        // Right direction (relative to facing)
        int rdx = DX[(pdir+1)%4], rdy = DY[(pdir+1)%4];

        // Screen X edges of the open corridor at each depth
        int prevL = VIEW_X0, prevR = VIEW_X1;
        int prevT = VIEW_Y0, prevB = VIEW_Y1;

        for (int depth = 1; depth <= MAX_DEPTH; depth++) {
            int nx = fx + fdx, ny = fy + fdy;

            // Scale: at depth d, wall height = VIEW_H/d, half-width proportional
            float scale = 1.0f / depth;
            int wallH = Math.min(VIEW_H, (int)(VIEW_H * scale));
            int wallW = Math.min(VIEW_W, (int)(VIEW_W * scale * 0.5f));

            int topY = VCY - wallH/2;
            int botY = VCY + wallH/2;
            int leftX = VCX - wallW;
            int rightX = VCX + wallW;

            topY  = clampY(topY);  botY  = clampY(botY);
            leftX = Math.max(VIEW_X0, Math.min(VIEW_X1, leftX));
            rightX= Math.max(VIEW_X0, Math.min(VIEW_X1, rightX));

            float bright = Math.max(0.15f, 1.0f - depth * 0.12f);

            // ── Left wall (if no opening to the left) ──
            if (hasWall(fx, fy, (pdir+3)%4)) {
                // Draw left side wall: trapezoid from prev to current depth
                vl(prevL, prevT, leftX, topY, bright);  // top edge
                vl(prevL, prevB, leftX, botY, bright);  // bottom edge
                vl(leftX, topY,  leftX, botY, bright);  // vertical edge
            }

            // ── Right wall (if no opening to the right) ──
            if (hasWall(fx, fy, (pdir+1)%4)) {
                // Draw right side wall: trapezoid
                vl(prevR, prevT, rightX, topY, bright);
                vl(prevR, prevB, rightX, botY, bright);
                vl(rightX, topY, rightX, botY, bright);
            }

            // ── Front wall (if corridor blocked ahead) ──
            if (hasWall(fx, fy, pdir) || isSolid(nx, ny)) {
                // Draw back wall rectangle
                vl(leftX,  topY, rightX, topY, bright);
                vl(leftX,  botY, rightX, botY, bright);
                vl(leftX,  topY, leftX,  botY, bright * 0.7f);
                vl(rightX, topY, rightX, botY, bright * 0.7f);
                break;  // can't see further
            }

            // ── Peek into side openings (left/right corridors) ──
            // Left opening
            if (!hasWall(fx, fy, (pdir+3)%4)) {
                // Left corridor exists — draw its far wall stub
                int sideD = depth + 1;
                float sb = Math.max(0.1f, bright * 0.6f);
                // Just draw a vertical line to suggest the side corridor
                vl(leftX, topY, leftX, botY, sb);
                // And a short horizontal suggesting the side wall
                int stubX = Math.max(VIEW_X0, leftX - wallW/3);
                vl(stubX, (topY+VCY)/2, leftX, (topY+VCY)/2, sb*0.5f);
                vl(stubX, (botY+VCY)/2, leftX, (botY+VCY)/2, sb*0.5f);
            }
            // Right opening
            if (!hasWall(fx, fy, (pdir+1)%4)) {
                int sideD = depth + 1;
                float sb = Math.max(0.1f, bright * 0.6f);
                vl(rightX, topY, rightX, botY, sb);
                int stubX = Math.min(VIEW_X1, rightX + wallW/3);
                vl(stubX, (topY+VCY)/2, rightX, (topY+VCY)/2, sb*0.5f);
                vl(stubX, (botY+VCY)/2, rightX, (botY+VCY)/2, sb*0.5f);
            }

            prevL = leftX; prevR = rightX;
            prevT = topY;  prevB = botY;
            fx = nx; fy = ny;
        }

        // Render enemies visible in FOV
        renderEnemiesInView(playerAngle);

        // Render bullets in view
        renderBulletsInView(playerAngle);

        // HUD
        renderHUD();

        // Minimap
        if (showMinimap) renderMinimap();

        // Message
        if (msgTimer > 0) {
            float b = Math.min(1f, msgTimer / 25f);
            int mw = msgText.length() * 22;
            vtext(msgText, VIEW_CX - mw/2, VIEW_CY - 80, 14, b);
        }
    }

    private int clampY(int y) { return Math.max(VIEW_Y0, Math.min(VIEW_Y1, y)); }

    // ── Project world point to screen ─────────────────────────
    private static class Proj {
        int    sx, sy, size;
        double dist;
        boolean valid;
    }
    private final Proj proj = new Proj();

    private void projectPoint(double wx, double wy, double playerAngle) {
        double dx = wx - (px + 0.5);
        double dy = wy - (py + 0.5);
        // Rotate to camera space (angle offset)
        // Camera transform: forward=(cos(PA),sin(PA)), right=(sin(PA),-cos(PA))
        double cpa = Math.cos(playerAngle), spa = Math.sin(playerAngle);
        double cx =  dx*spa - dy*cpa;   // screen-X (left/right)
        double cy =  dx*cpa + dy*spa;   // depth (forward)

        proj.valid = false;
        if (cy <= 0.05) return;

        double screenX = (VIEW_W / 2.0) * (1.0 + (cx / cy) / Math.tan(FOV / 2.0));
        proj.sx   = VIEW_X0 + (int) screenX;
        proj.sy   = VIEW_CY;
        proj.size = (int) Math.min(VIEW_H, VIEW_H / cy);
        proj.dist = cy;
        proj.valid = (proj.sx >= VIEW_X0 - proj.size && proj.sx <= VIEW_X1 + proj.size);
    }

    // ── Draw enemy eyeball sprite ──────────────────────────────
    // Authentic to original Maze War: oval eye, pupil, legs
    private void drawEyeball(int cx, int cy, int size, float bright) {
        if (size < 6) {
            vp(cx, cy, bright);
            return;
        }
        int rx = size / 2, ry = (int)(size * 0.35);  // wider than tall

        // Outer eye oval (16 segments)
        int segs = Math.max(8, size / 4);
        int epx = cx + rx, epy = cy;
        for (int i = 1; i <= segs; i++) {
            double a = (double)i / segs * 2 * Math.PI;
            int nx = cx + (int)(Math.cos(a) * rx);
            int ny = cy + (int)(Math.sin(a) * ry);
            vl(epx, epy, nx, ny, bright);
            epx = nx; epy = ny;
        }

        // Pupil (8 segments)
        int pr = Math.max(2, size / 5);
        int epx2 = cx + pr, epy2 = cy;
        int pSegs = Math.max(6, size / 6);
        for (int i = 1; i <= pSegs; i++) {
            double a = (double)i / pSegs * 2 * Math.PI;
            int nx = cx + (int)(Math.cos(a) * pr);
            int ny = cy + (int)(Math.sin(a) * pr * 0.8);
            vl(epx2, epy2, nx, ny, bright * 1.2f);
            epx2 = nx; epy2 = ny;
        }

        // Iris cross-hairs
        vl(cx - pr, cy, cx - rx, cy, bright * 0.4f);
        vl(cx + pr, cy, cx + rx, cy, bright * 0.4f);
        vl(cx, cy - pr, cx, cy - ry, bright * 0.4f);
        vl(cx, cy + pr, cx, cy + ry, bright * 0.4f);

        // Legs (classic Maze War feature!)
        if (size > 30) {
            int legY = cy + ry + 2;
            for (int i = -2; i <= 2; i++) {
                if (i == 0) continue;
                int lx = cx + i * (rx / 3);
                vl(lx, legY, lx + i * 3, legY + Math.max(4, size/6), bright * 0.7f);
            }
        }
    }

    private void renderEnemiesInView(double playerAngle) {
        // Sort far to near
        enemies.sort((ea, eb) -> {
            double da = dist2(ea.gx, ea.gy);
            double db = dist2(eb.gx, eb.gy);
            return Double.compare(db, da);
        });

        for (Enemy e : enemies) {
            if (!e.alive) continue;
            projectPoint(e.gx + 0.5, e.gy + 0.5, playerAngle);
            if (!proj.valid) continue;

            // Wall occlusion: cast ray toward enemy, check if wall is closer
            double ex2 = e.gx + 0.5 - (px + 0.5);
            double ey2 = e.gy + 0.5 - (py + 0.5);
            double rayA = Math.atan2(ey2, ex2);
            castRay(rayA);
            if (proj.dist > rayHit.dist + 0.5) continue;

            float bright = (float) Math.min(0.95, 0.8 / (proj.dist * 0.3 + 0.1));
            drawEyeball(proj.sx, VIEW_CY, (int)(proj.size * 0.55), bright);
        }
    }

    private void renderBulletsInView(double playerAngle) {
        for (Bullet b : bullets) {
            if (!b.alive) continue;
            projectPoint(b.x, b.y, playerAngle);
            if (!proj.valid) continue;
            float bright = (float) Math.min(1.0, 0.9 / (proj.dist * 0.2 + 0.1));
            vp(proj.sx, VIEW_CY, bright);
            // Add a small cross for visibility
            vl(proj.sx-4, VIEW_CY, proj.sx+4, VIEW_CY, bright * 0.5f);
            vl(proj.sx, VIEW_CY-4, proj.sx, VIEW_CY+4, bright * 0.5f);
        }
    }

    private double dist2(int ex, int ey) {
        double dx = ex - px, dy = ey - py;
        return dx*dx + dy*dy;
    }

    // ── HUD ───────────────────────────────────────────────────
    private void renderHUD() {
        // Crosshair
        int cx = VIEW_CX, cy = VIEW_CY;
        vl(cx-14,cy, cx-5,cy, 0.6f);
        vl(cx+5, cy, cx+14,cy, 0.6f);
        vl(cx,cy-14, cx,cy-5, 0.6f);
        vl(cx,cy+5,  cx,cy+14, 0.6f);
        vp(cx, cy, 0.35f);

        // HP dots (top-left)
        vtext("HP", VIEW_X0+8, VIEW_Y1+25, 9, 0.4f);
        for (int i = 0; i < 3; i++) {
            int hx = VIEW_X0 + 60 + i * 24;
            int hy = VIEW_Y1 + 18;
            if (i < pHP) {
                // Filled circle
                for (int j = 0; j < 8; j++) {
                    double a = j / 8.0 * 2 * Math.PI;
                    vl(hx+(int)(Math.cos(a)*7), hy+(int)(Math.sin(a)*7),
                       hx+(int)(Math.cos(a+Math.PI/8)*7), hy+(int)(Math.sin(a+Math.PI/8)*7), 0.9f);
                }
            } else {
                // Empty circle
                for (int j = 0; j < 6; j++) {
                    double a = j / 6.0 * 2 * Math.PI;
                    vl(hx+(int)(Math.cos(a)*7), hy+(int)(Math.sin(a)*7),
                       hx+(int)(Math.cos(a+Math.PI/3)*7), hy+(int)(Math.sin(a+Math.PI/3)*7), 0.2f);
                }
            }
        }

        // Score (top-right)
        String sc = String.format("%04d", score);
        vtext(sc, VIEW_X1 - 115, VIEW_Y1+25, 9, 0.7f);

        // Compass direction (top-right corner)
        String[] dirs = {"N","E","S","W"};
        vtext(dirs[pdir], VIEW_X1 + 15, VIEW_Y1 + 20, 10, 0.6f);

        // DEBUG
        vtext(String.format("P%d,%d D%s", px,py,dirs[pdir]), VIEW_X0+8, VIEW_Y0-40, 8, 0.6f);
        vtext(String.format("FWD:%b LT:%b RT:%b KB:%04X", kFwd,kLeft,kRight,M.keyboard), VIEW_X0+8, VIEW_Y0-60, 8, 0.6f);
        vtext(String.format("MOV:%d TRN:%d", moveCooldown,turnCooldown), VIEW_X0+8, VIEW_Y0-80, 8, 0.6f);

        // Level (top)
        vtext("LV" + level, VIEW_CX - 40, VIEW_Y0 - 20, 9, 0.4f);

        // Fire cooldown bar
        if (fireCooldown > 0) {
            int bw = (int)(fireCooldown / 18.0 * 80);
            vl(VIEW_CX - 40, VIEW_Y1 + 55, VIEW_CX - 40 + bw, VIEW_Y1 + 55, 0.5f);
        }

        // "FIRE" label
        vtext("FIRE", VIEW_X1 + 10, VIEW_Y0 + 20, 7, 0.25f);
        vtext("MOVE", VIEW_X1 + 10, VIEW_Y0 + 50, 7, 0.25f);
    }

    // ── MINIMAP ───────────────────────────────────────────────
    private void renderMinimap() {
        int ox = VIEW_X1 + 15, oy = VIEW_Y0 + 80;
        int cw = 12, ch = 12;
        int mw = 10, mh = 8;  // show 10x8 cells around player
        int startX = Math.max(0, Math.min(px - mw/2, MZ - mw));
        int startY = Math.max(0, Math.min(py - mh/2, MZ - mh));

        for (int y = startY; y < startY + mh && y < MZ; y++) {
            for (int x = startX; x < startX + mw && x < MZ; x++) {
                int sx = ox + (x-startX)*cw, sy = oy + (mh-1-(y-startY))*ch;
                int cell = maze[y*MZ+x];
                float wb = 0.5f;
                if ((cell&1) != 0) vl(sx,sy+ch, sx+cw,sy+ch, wb);
                if ((cell&2) != 0) vl(sx+cw,sy, sx+cw,sy+ch, wb);
                if ((cell&4) != 0) vl(sx,sy, sx+cw,sy, wb);
                if ((cell&8) != 0) vl(sx,sy, sx,sy+ch, wb);
            }
        }

        // Player dot
        if (px >= startX && px < startX+mw && py >= startY && py < startY+mh) {
            int pdx = ox+(px-startX)*cw+cw/2;
            int pdy = oy+(mh-1-(py-startY))*ch+ch/2;
            vp(pdx, pdy, 1.0f);
            // Direction arrow
            int adx = DX[pdir]*cw/2, ady = -DY[pdir]*ch/2;
            vl(pdx, pdy, pdx+adx, pdy+ady, 0.7f);
        }

        // Enemy dots
        for (Enemy e : enemies) {
            if (!e.alive) continue;
            if (e.gx < startX || e.gx >= startX+mw) continue;
            if (e.gy < startY || e.gy >= startY+mh) continue;
            int edx = ox+(e.gx-startX)*cw+cw/2;
            int edy = oy+(mh-1-(e.gy-startY))*ch+ch/2;
            vl(edx-3,edy, edx+3,edy, 0.8f);
            vl(edx,edy-3, edx,edy+3, 0.8f);
        }

        vtext("MAP", ox, oy + mh*ch + 15, 7, 0.3f);
    }

    // ================================================================
    //  TITLE SCREEN
    // ================================================================
    private void updateTitle() {
        // Any key or button starts the game
        boolean anyKey = kFwd || kBack || kLeft || kRight || kFire
                      || (M.keyboard & 0x7F) != 0;
        if (anyKey && !prevAnyKey) startGame();
        prevAnyKey = anyKey;
    }
    private void updateDead() {
        boolean anyKey = kFwd || kBack || kLeft || kRight || kFire
                      || (M.keyboard & 0x7F) != 0;
        if (anyKey && !prevAnyKey) startGame();
        prevAnyKey = anyKey;
    }
    private void updateWin()  { /* wait for key */ }

    private void renderTitle() {
        double t = titleFrame * 0.03;

        // Animated eyeball
        int ex = SCR_W/2, ey = 600;
        int er = (int)(100 + Math.sin(t) * 10);
        // Outer
        for (int i=0;i<24;i++){
            double a=(double)i/24*2*Math.PI;
            double a2=((double)(i+1))/24*2*Math.PI;
            vl(ex+(int)(Math.cos(a)*er*1.3), ey+(int)(Math.sin(a)*er*0.8),
               ex+(int)(Math.cos(a2)*er*1.3),ey+(int)(Math.sin(a2)*er*0.8), 0.85f);
        }
        // Pupil
        for (int i=0;i<16;i++){
            double a=(double)i/16*2*Math.PI;
            double a2=((double)(i+1))/16*2*Math.PI;
            int pr2=er/3;
            vl(ex+(int)(Math.cos(a)*pr2),   ey+(int)(Math.sin(a)*pr2*0.8),
               ex+(int)(Math.cos(a2)*pr2),  ey+(int)(Math.sin(a2)*pr2*0.8), 1.0f);
        }
        // Iris lines
        for (int i=0;i<6;i++){
            double a=(double)i/6*Math.PI;
            int pr2=er/3;
            vl(ex+(int)(Math.cos(a)*pr2),ey+(int)(Math.sin(a)*pr2*0.8),
               ex+(int)(Math.cos(a)*er*1.2),ey+(int)(Math.sin(a)*er*0.75), 0.3f);
        }
        // Legs
        for (int i=-3;i<=3;i++){if(i==0)continue;
            int lx=ex+i*35; int legY=ey+(int)(er*0.8)+5;
            vl(lx,legY, lx+i*5, legY+40, 0.55f);
        }

        vtext("MAZE WAR",   SCR_W/2 - 245, 450, 20, 1.0f);
        vtext("IMLAC PDS-1  1974", SCR_W/2-280, 380, 12, 0.5f);
        vtext("MIT AI LAB  NASA AMES", SCR_W/2-310, 345, 11, 0.35f);

        boolean blink = (titleFrame/20) % 2 == 0;
        if (blink) vtext("PRESS ANY KEY", SCR_W/2-220, 270, 12, 0.9f);

        vtext("WASD MOVE  SPACE FIRE  M MAP", SCR_W/2-355, 220, 9, 0.25f);
        vtext("FIRST PERSON SHOOTER  1974", SCR_W/2-310, 185, 9, 0.2f);
    }

    private void renderDead() {
        vtext("GAME OVER",  SCR_W/2-210, 620, 20, 0.9f);
        vtext("SCORE " + String.format("%04d", score), SCR_W/2-175, 530, 15, 0.7f);
        vtext("LEVEL " + level, SCR_W/2-110, 470, 13, 0.5f);
        boolean blink = (titleFrame/20) % 2 == 0;
        if (blink) vtext("PRESS ANY KEY", SCR_W/2-220, 380, 12, 0.85f);
    }

    private void renderWin() {
        vtext("YOU WIN!",  SCR_W/2-185, 580, 20, 1.0f);
        vtext("SCORE " + String.format("%04d", score), SCR_W/2-175, 490, 15, 0.8f);
        boolean blink = (titleFrame/20) % 2 == 0;
        if (blink) vtext("PRESS ANY KEY", SCR_W/2-220, 380, 12, 0.9f);
    }

    // ================================================================
    //  VECTOR DRAWING HELPERS
    // ================================================================
    private void vl(int x1, int y1, int x2, int y2, float b) {
        M.dlLine(x1, y1, x2, y2, b);
    }
    private void vp(int x, int y, float b) {
        M.dlPoint(x, y, b);
    }
    private void vchar(char c, int ox, int oy, float scale, float b) {
        char cu = Character.toUpperCase(c);
        int idx = CHARSET.indexOf(cu);
        if (idx < 0 || idx >= FONT.length) return;
        for (float[] s : FONT[idx]) {
            vl(ox+(int)(s[0]*scale), oy+(int)(s[1]*scale),
               ox+(int)(s[2]*scale), oy+(int)(s[3]*scale), b);
        }
    }
    private void vtext(String str, int ox, int oy, float sc, float b) {
        int x = ox;
        for (char c : str.toCharArray()) {
            if (c == '\n') { oy += (int)(sc*6); x=ox; continue; }
            vchar(c, x, oy, sc, b);
            x += (int)(sc * 5.5f);
        }
    }
}
