package com.imlac.pds1;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

/**
 * Maze War — Imlac PDS-1 (1974) recreation.
 * Authentic grid-based movement, wireframe 3D corridor renderer.
 */
public class MazeWarGame {

    // ── Screen constants ──────────────────────────────────────
    private static final int SW = 1024, SH = 1024;
    private static final int VX0 = 40,  VX1 = 780;
    private static final int VY0 = 80,  VY1 = 940;
    private static final int VCX = (VX0+VX1)/2, VCY = (VY0+VY1)/2;
    private static final int VW  = VX1-VX0,      VH  = VY1-VY0;

    // ── Maze ─────────────────────────────────────────────────
    private static final int MZ = 16;
    // Wall bits: bit0=N(+Y) bit1=E(+X) bit2=S(-Y) bit3=W(-X)
    private final int[] maze = new int[MZ*MZ];
    private static final int[] DX  = { 0, 1, 0,-1};
    private static final int[] DY  = { 1, 0,-1, 0};
    private static final int[] OPP = { 2, 3, 0, 1};

    // ── Player ────────────────────────────────────────────────
    private int px=1, py=1, pdir=0;
    private int score=0, level=1, hp=3;
    private int moveCd=0, turnCd=0, fireCd=0;
    private int hitFlash=0, killFlash=0;

    // ── Enemies ───────────────────────────────────────────────
    private static class Enemy {
        int x, y, dir, think=30, fireCd=80;
        boolean alive=true;
    }
    private final List<Enemy> enemies = new ArrayList<>();

    // ── Bullets ───────────────────────────────────────────────
    private static class Bullet {
        double x, y; int dir, life=55; boolean fromPlayer, alive=true;
    }
    private final List<Bullet> bullets = new ArrayList<>();

    // ── State ─────────────────────────────────────────────────
    private enum State { TITLE, PLAY, DEAD }
    private State state = State.TITLE;
    private int   frame = 0;
    private String msg  = ""; int msgT = 0;

    // ── Input — written by Activity each frame ─────────────────
    public volatile boolean iUp, iDown, iLeft, iRight, iFire;
    // prevs for edge detection
    private boolean pUp, pDown, pLeft, pRight, pFire;

    // ── Machine ref ───────────────────────────────────────────
    private final Machine M;

    public MazeWarGame(Machine m) { this.M = m; }

    // ─────────────────────────────────────────────────────────
    //  PUBLIC — called each render frame from Demos.java
    // ─────────────────────────────────────────────────────────
    public void tick() {
        // Merge keyboard input with controller input (OR them together)
        int k = M.keyboard & 0x7F;
        iUp    |= (k=='W'); iDown  |= (k=='S');
        iLeft  |= (k=='A'); iRight |= (k=='D');
        iFire  |= (k==' ' || k=='F');

        switch (state) {
            case TITLE: tickTitle(); break;
            case PLAY:  tickPlay();  break;
            case DEAD:  tickDead();  break;
        }

        pUp=iUp; pDown=iDown; pLeft=iLeft; pRight=iRight; pFire=iFire;
        frame++;
    }

    public void draw() {
        switch (state) {
            case TITLE: drawTitle(); break;
            case PLAY:  drawPlay();  break;
            case DEAD:  drawDead();  break;
        }
    }

    // ─────────────────────────────────────────────────────────
    //  TITLE
    // ─────────────────────────────────────────────────────────
    private void tickTitle() {
        boolean anyPressed = (iUp||iDown||iLeft||iRight||iFire)
                           && !(pUp||pDown||pLeft||pRight||pFire);
        if (anyPressed) startGame();
    }

    private void drawTitle() {
        // Animated eyeball
        double t = frame * 0.04;
        int ex=SW/2, ey=620, rx=110, ry=70;
        circle(ex, ey, rx, ry, 20, 0.9f);
        circle(ex, ey, rx/3, (int)(ry*0.8f), 14, 1.0f);
        // legs
        for (int i=-3; i<=3; i++) { if(i==0) continue;
            vl(ex+i*32, ey+ry+2, ex+i*32+i*6, ey+ry+35, 0.55f); }

        txt("MAZE WAR",       SW/2-240, 490, 19, 1.0f);
        txt("IMLAC PDS-1  1974", SW/2-270, 425, 11, 0.5f);
        if ((frame/20)%2==0)
            txt("PRESS ANY BUTTON", SW/2-230, 340, 11, 0.9f);
        txt("UP/DN=MOVE  LT/RT=TURN  A=FIRE", SW/2-330, 285, 8, 0.25f);
    }

    // ─────────────────────────────────────────────────────────
    //  DEAD
    // ─────────────────────────────────────────────────────────
    private void tickDead() {
        boolean anyPressed = (iUp||iDown||iLeft||iRight||iFire)
                           && !(pUp||pDown||pLeft||pRight||pFire);
        if (anyPressed) startGame();
    }
    private void drawDead() {
        txt("GAME OVER",  SW/2-200, 580, 19, 0.9f);
        txt("SCORE "+score, SW/2-160, 500, 14, 0.7f);
        if ((frame/20)%2==0)
            txt("PRESS ANY BUTTON", SW/2-230, 400, 11, 0.85f);
    }

    // ─────────────────────────────────────────────────────────
    //  GAME INIT
    // ─────────────────────────────────────────────────────────
    private void startGame() {
        genMaze(); px=1; py=1; pdir=0;
        score=0; level=1; hp=3;
        moveCd=0; turnCd=0; fireCd=0; hitFlash=0; killFlash=0;
        bullets.clear();
        spawnEnemies(level+1);
        state=State.PLAY;
    }

    // ─────────────────────────────────────────────────────────
    //  MAZE GENERATION (recursive backtracker)
    // ─────────────────────────────────────────────────────────
    private void genMaze() {
        Arrays.fill(maze, 0xF);
        boolean[] vis = new boolean[MZ*MZ];
        carve(1,1,vis);
    }
    private void carve(int x, int y, boolean[] vis) {
        vis[y*MZ+x] = true;
        int[] d = {0,1,2,3};
        for (int i=3;i>0;i--){int j=(int)(Math.random()*(i+1));int t=d[i];d[i]=d[j];d[j]=t;}
        for (int dd : d) {
            int nx=x+DX[dd], ny=y+DY[dd];
            if (nx<1||nx>=MZ-1||ny<1||ny>=MZ-1||vis[ny*MZ+nx]) continue;
            maze[y*MZ+x]   &= ~(1<<dd);
            maze[ny*MZ+nx] &= ~(1<<OPP[dd]);
            carve(nx,ny,vis);
        }
    }
    private boolean wall(int x, int y, int dir) {
        if (x<0||x>=MZ||y<0||y>=MZ) return true;
        return (maze[y*MZ+x]&(1<<dir))!=0;
    }
    private boolean solid(int x, int y) {
        if (x<0||x>=MZ||y<0||y>=MZ) return true;
        return maze[y*MZ+x]==0xF;
    }

    private void spawnEnemies(int n) {
        enemies.clear();
        for (int i=0;i<n;i++) {
            Enemy e=new Enemy();
            for (int t=0;t<200;t++) {
                e.x=2+(int)(Math.random()*(MZ-4));
                e.y=2+(int)(Math.random()*(MZ-4));
                if (!solid(e.x,e.y) && Math.abs(e.x-px)+Math.abs(e.y-py)>3) break;
            }
            e.dir=(int)(Math.random()*4);
            enemies.add(e);
        }
    }

    // ─────────────────────────────────────────────────────────
    //  GAME TICK
    // ─────────────────────────────────────────────────────────
    private void tickPlay() {
        if (moveCd>0) moveCd--;
        if (turnCd>0) turnCd--;
        if (fireCd>0) fireCd--;
        if (hitFlash>0) hitFlash--;
        if (killFlash>0) killFlash--;
        if (msgT>0) msgT--;

        // Turn (edge-triggered: only on new press)
        if (turnCd==0) {
            if (iLeft && !pLeft)  { pdir=(pdir+3)%4; turnCd=8; }
            if (iRight && !pRight){ pdir=(pdir+1)%4; turnCd=8; }
        }
        // Move (held OK, but cooldown prevents too-fast)
        if (moveCd==0) {
            if (iUp   && !wall(px,py,pdir))           { px+=DX[pdir]; py+=DY[pdir]; moveCd=12; }
            else if (iDown && !wall(px,py,(pdir+2)%4)){ px-=DX[pdir]; py-=DY[pdir]; moveCd=12; }
        }
        // Fire (edge)
        if (iFire && !pFire && fireCd==0) {
            Bullet b=new Bullet(); b.x=px+.5; b.y=py+.5;
            b.dir=pdir; b.fromPlayer=true; bullets.add(b); fireCd=20;
        }

        tickBullets(); tickEnemies(); checkWin();
    }

    private void tickBullets() {
        for (Bullet b : bullets) {
            if (!b.alive) continue;
            b.life--;
            if (b.life<=0){b.alive=false;continue;}
            b.x+=DX[b.dir]*0.2; b.y+=DY[b.dir]*0.2;
            if (solid((int)b.x,(int)b.y)){b.alive=false;continue;}
            if (b.fromPlayer) {
                for (Enemy e : enemies) { if (!e.alive) continue;
                    if (Math.abs(b.x-(e.x+.5))<0.6&&Math.abs(b.y-(e.y+.5))<0.6) {
                        e.alive=false; b.alive=false; score++; killFlash=12;
                        msg="KILL"; msgT=35; break; } }
            } else {
                if (Math.abs(b.x-(px+.5))<0.55&&Math.abs(b.y-(py+.5))<0.55) {
                    b.alive=false; hp--; hitFlash=18;
                    msg=(hp>0?"HIT! HP:"+hp:"YOU DIED"); msgT=45;
                    if (hp<=0) state=State.DEAD; }
            }
        }
        bullets.removeIf(b->!b.alive);
    }

    private void tickEnemies() {
        for (Enemy e : enemies) {
            if (!e.alive) continue;
            e.think--; e.fireCd--;
            if (e.think<=0) {
                e.think=15+(int)(Math.random()*25);
                int dx=px-e.x, dy=py-e.y;
                int want=-1;
                if (Math.abs(dx)>Math.abs(dy)) want=dx>0?1:3;
                else if (dy!=0) want=dy>0?0:2;
                if (Math.random()<0.6&&want>=0&&!wall(e.x,e.y,want)) {
                    e.dir=want; e.x+=DX[want]; e.y+=DY[want];
                } else {
                    int[] ds={0,1,2,3};
                    for (int i=3;i>0;i--){int j=(int)(Math.random()*(i+1));int t=ds[i];ds[i]=ds[j];ds[j]=t;}
                    for (int dd:ds) { if (!wall(e.x,e.y,dd)){e.dir=dd;e.x+=DX[dd];e.y+=DY[dd];break;} }
                }
            }
            if (e.fireCd<=0) {
                boolean shoot=false;
                if (e.dir==0&&e.x==px&&py>e.y) shoot=clear(e.x,e.y,px,py);
                if (e.dir==2&&e.x==px&&py<e.y) shoot=clear(px,py,e.x,e.y);
                if (e.dir==1&&e.y==py&&px>e.x) shoot=clear(e.x,e.y,px,py);
                if (e.dir==3&&e.y==py&&px<e.x) shoot=clear(px,py,e.x,e.y);
                if (shoot) {
                    Bullet b=new Bullet(); b.x=e.x+.5; b.y=e.y+.5;
                    b.dir=e.dir; b.fromPlayer=false; bullets.add(b);
                    e.fireCd=60+(int)(Math.random()*60);
                }
            }
        }
    }

    private boolean clear(int x1,int y1,int x2,int y2) {
        if (x1==x2) { for(int y=y1;y<y2;y++) if(wall(x1,y,0)) return false; }
        else        { for(int x=x1;x<x2;x++) if(wall(x,y1,1)) return false; }
        return true;
    }

    private void checkWin() {
        for (Enemy e:enemies) if (e.alive) return;
        level++; msg="LEVEL "+level+"!"; msgT=60;
        genMaze(); px=1; py=1; pdir=0;
        bullets.clear(); spawnEnemies(Math.min(level+1,7));
    }

    // ─────────────────────────────────────────────────────────
    //  DRAW PLAY
    // ─────────────────────────────────────────────────────────
    private void drawPlay() {
        // Viewport border
        vl(VX0,VY0,VX1,VY0,0.5f); vl(VX1,VY0,VX1,VY1,0.5f);
        vl(VX1,VY1,VX0,VY1,0.5f); vl(VX0,VY1,VX0,VY0,0.5f);

        // Hit flash border
        if (hitFlash>0) {
            float f=hitFlash/18f;
            vl(VX0,VY0,VX1,VY0,f); vl(VX1,VY0,VX1,VY1,f);
            vl(VX1,VY1,VX0,VY1,f); vl(VX0,VY1,VX0,VY0,f);
        }

        draw3D();
        drawEnemies();
        drawHUD();

        if (msgT>0) {
            float b=Math.min(1f,msgT/20f);
            txt(msg, VCX-msg.length()*11, VCY-60, 13, b);
        }
    }

    // ── 3D Corridor (authentic Maze War wireframe) ────────────
    // Draws nested rectangles receding into distance.
    // Each rectangle represents one cell boundary ahead.
    // Side walls drawn as trapezoids between adjacent rects.
    private void draw3D() {
        final int MAX_D = 10;

        // Find how far we can see straight ahead
        int depth = 0;
        int wx = px, wy = py;
        for (int d=1; d<=MAX_D; d++) {
            if (wall(wx,wy,pdir)) { depth=d-1; break; }
            wx+=DX[pdir]; wy+=DY[pdir];
            if (solid(wx,wy)) { depth=d-1; break; }
            depth=d;
        }
        depth = Math.max(0, depth);

        // Project rect at distance d from player
        // Scale: at d=0 (player cell) fills whole viewport
        //        at d=1 it's half size, d=2 quarter, etc.
        // Use: half = VH/2 / (d+1) * 1.4  for a nice FOV feel

        // Pre-compute screen rects for each depth
        int[] lt = new int[MAX_D+2]; // left X
        int[] rt = new int[MAX_D+2]; // right X
        int[] tp = new int[MAX_D+2]; // top Y
        int[] bt = new int[MAX_D+2]; // bottom Y

        for (int d=0; d<=depth+1; d++) {
            float scale = 1.4f / (d + 1.0f);
            int hh = (int)(VH/2f * scale);
            int hw = (int)(VW/2f * scale);
            lt[d] = clampX(VCX - hw);
            rt[d] = clampX(VCX + hw);
            tp[d] = clampY(VCY - hh);
            bt[d] = clampY(VCY + hh);
        }

        // Walk from player outward, draw geometry per cell
        int cx=px, cy=py;
        for (int d=0; d<=depth; d++) {
            float bright = Math.max(0.2f, 1.0f - d * 0.1f);

            boolean hasLeft  = !wall(cx,cy,(pdir+3)%4);
            boolean hasRight = !wall(cx,cy,(pdir+1)%4);
            boolean hasFront = !wall(cx,cy,pdir) && d<depth;

            // Left wall trapezoid (if solid left)
            if (!hasLeft) {
                vl(lt[d],tp[d], lt[d+1],tp[d+1], bright*0.8f); // top
                vl(lt[d],bt[d], lt[d+1],bt[d+1], bright*0.8f); // bottom
                vl(lt[d+1],tp[d+1], lt[d+1],bt[d+1], bright*0.6f); // far vert
            } else {
                // Open left: draw entrance line + side corridor hint
                vl(lt[d],tp[d], lt[d],bt[d], bright*0.5f);
            }

            // Right wall trapezoid
            if (!hasRight) {
                vl(rt[d],tp[d], rt[d+1],tp[d+1], bright*0.8f);
                vl(rt[d],bt[d], rt[d+1],bt[d+1], bright*0.8f);
                vl(rt[d+1],tp[d+1], rt[d+1],bt[d+1], bright*0.6f);
            } else {
                vl(rt[d],tp[d], rt[d],bt[d], bright*0.5f);
            }

            // Back wall (at the end of corridor)
            if (!hasFront) {
                vl(lt[d+1],tp[d+1], rt[d+1],tp[d+1], bright); // top
                vl(lt[d+1],bt[d+1], rt[d+1],bt[d+1], bright); // bottom
                vl(lt[d+1],tp[d+1], lt[d+1],bt[d+1], bright*0.8f); // left
                vl(rt[d+1],tp[d+1], rt[d+1],bt[d+1], bright*0.8f); // right
                break;
            }

            cx+=DX[pdir]; cy+=DY[pdir];
        }

        // Vanishing lines: connect viewport corners to d=0 rect
        vl(VX0,VY0, lt[0],tp[0], 0.35f);
        vl(VX1,VY0, rt[0],tp[0], 0.35f);
        vl(VX0,VY1, lt[0],bt[0], 0.35f);
        vl(VX1,VY1, rt[0],bt[0], 0.35f);

        // Crosshair
        vl(VCX-12,VCY, VCX-4,VCY, 0.6f); vl(VCX+4,VCY, VCX+12,VCY, 0.6f);
        vl(VCX,VCY-12, VCX,VCY-4, 0.6f); vl(VCX,VCY+4, VCX,VCY+12, 0.6f);
    }

    // ── Draw enemy eyeballs visible in current corridor ───────
    private void drawEnemies() {
        for (Enemy e : enemies) {
            if (!e.alive) continue;
            // Check if enemy is in front of player on the same axis
            int relDir = -1;
            if (pdir==0 && e.x==px && e.y>py) relDir=0; // N: +Y
            if (pdir==1 && e.y==py && e.x>px) relDir=1; // E: +X
            if (pdir==2 && e.x==px && e.y<py) relDir=2; // S: -Y
            if (pdir==3 && e.y==py && e.x<px) relDir=3; // W: -X
            if (relDir!=pdir) continue;

            int dist = (pdir==0||pdir==2) ? Math.abs(e.y-py) : Math.abs(e.x-px);
            if (dist<1 || dist>8) continue;

            // Check no wall between player and enemy
            boolean blocked=false;
            for (int d=0; d<dist; d++) {
                int cx=px+DX[pdir]*d, cy2=py+DY[pdir]*d;
                if (wall(cx,cy2,pdir)){blocked=true;break;}
            }
            if (blocked) continue;

            // Project to screen
            float scale = 1.4f / (dist + 0.5f);
            int sz = (int)(VH * 0.25f * scale);
            sz = Math.max(8, Math.min(sz, 120));
            drawEye(VCX, VCY, sz, Math.max(0.3f, 0.9f - dist*0.08f));
        }
    }

    private void drawEye(int cx, int cy, int sz, float b) {
        int rx=sz, ry=(int)(sz*0.55f);
        circle(cx,cy,rx,ry,16,b);          // outer oval
        circle(cx,cy,rx/3,(int)(ry*0.7f),10,b*1.1f); // pupil
        vl(cx-rx,cy, cx+rx,cy, b*0.3f);   // iris h-line
        // legs
        if (sz>25) for (int i=-2;i<=2;i++){if(i==0)continue;
            vl(cx+i*(rx/3),cy+ry+2, cx+i*(rx/3)+i*4,cy+ry+20,b*0.6f); }
    }

    // ── HUD ───────────────────────────────────────────────────
    private void drawHUD() {
        // HP
        for (int i=0;i<3;i++) {
            int hx=VX0+20+i*28, hy=VY1+25;
            if (i<hp) { circle(hx,hy,9,9,8,0.9f); }
            else      { circle(hx,hy,9,9,6,0.2f); }
        }
        // Score
        txt(String.format("%04d",score), VX1-120, VY1+18, 9, 0.7f);
        // Direction
        txt(new String[]{"N","E","S","W"}[pdir], VX1+15, VY1+18, 10, 0.6f);
        // Level
        txt("LV"+level, VCX-32, VY0-22, 9, 0.35f);
        // Fire cooldown
        if (fireCd>0)
            vl(VCX-40,VY1+52, VCX-40+(int)(fireCd/20f*80),VY1+52, 0.4f);
        // Hints
        txt("MOVE",  VX1+10, VY0+18, 7, 0.22f);
        txt("FIRE",  VX1+10, VY0+38, 7, 0.22f);
    }

    // ─────────────────────────────────────────────────────────
    //  VECTOR DRAWING HELPERS
    // ─────────────────────────────────────────────────────────
    private void vl(int x1,int y1,int x2,int y2,float b) { M.dlLine(x1,y1,x2,y2,b); }

    private int clampX(int x) { return Math.max(VX0, Math.min(VX1,x)); }
    private int clampY(int y) { return Math.max(VY0, Math.min(VY1,y)); }

    private void circle(int cx,int cy,int rx,int ry,int segs,float b) {
        int px0=cx+rx, py0=cy;
        for (int i=1;i<=segs;i++) {
            double a=i/(double)segs*2*Math.PI;
            int nx=cx+(int)(Math.cos(a)*rx), ny=cy+(int)(Math.sin(a)*ry);
            vl(px0,py0,nx,ny,b); px0=nx; py0=ny;
        }
    }

    // ── Minimal vector font ───────────────────────────────────
    private static final float[][][] F = {
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
        /* */ {}
    };
    private static final String CH = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ";

    private void ch(char c, int ox, int oy, float sc, float b) {
        int i = CH.indexOf(Character.toUpperCase(c));
        if (i<0||i>=F.length) return;
        for (float[] s:F[i])
            vl(ox+(int)(s[0]*sc),oy+(int)(s[1]*sc),
               ox+(int)(s[2]*sc),oy+(int)(s[3]*sc),b);
    }
    private void txt(String s, int ox, int oy, float sc, float b) {
        int x=ox;
        for (char c:s.toCharArray()) { ch(c,x,oy,sc,b); x+=(int)(sc*5.5f); }
    }
}
