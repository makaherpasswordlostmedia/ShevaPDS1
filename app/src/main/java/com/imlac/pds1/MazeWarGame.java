package com.imlac.pds1;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Random;

/**
 * Maze War — Imlac PDS-1 (1974).
 * Supports single-player vs AI and LAN multiplayer (via NetGame).
 */
public class MazeWarGame implements NetSession.EventListener {

    // ── Screen constants ──────────────────────────────────────
    private static final int VX0=40, VX1=780, VY0=80, VY1=940;
    private static final int VCX=(VX0+VX1)/2, VCY=(VY0+VY1)/2;
    private static final int VW=VX1-VX0, VH=VY1-VY0;

    // ── Maze ─────────────────────────────────────────────────
    private static final int MZ = 16;
    private final int[] maze = new int[MZ*MZ];
    private static final int[] DX  = { 0, 1, 0,-1};
    private static final int[] DY  = { 1, 0,-1, 0};
    private static final int[] OPP = { 2, 3, 0, 1};
    private long mazeSeed = 0;

    // ── Local player ──────────────────────────────────────────
    private int px=1, py=1, pdir=0, hp=3, score=0, level=1;
    private int moveCd=0, turnCd=0, fireCd=0, hitFlash=0, killFlash=0;

    // ── Network player (visible as enemy eyeball) ─────────────
    private int  netX=14, netY=14, netDir=2, netHp=3, netScore=0;
    private boolean netAlive=true;
    private int  netHitFlash=0;

    // ── Network ───────────────────────────────────────────────
    private NetSession net;
    private boolean multiMode = false;
    private int     netSendCd = 0;     // send every 3 frames

    // ── AI enemies (single-player only) ───────────────────────
    private static class Enemy {
        int x,y,dir,think=30,fireCd=80; boolean alive=true;
    }
    private final List<Enemy> aiEnemies = new ArrayList<>();

    // ── Bullets ───────────────────────────────────────────────
    private static class Bullet {
        double x,y; int dir,life=55; boolean fromPlayer,alive=true;
    }
    private final List<Bullet> bullets = new ArrayList<>();

    // ── State ─────────────────────────────────────────────────
    private enum State { TITLE, LOBBY, PLAY, DEAD }
    private State state = State.TITLE;
    private int   frame = 0;
    private String msg=""; int msgT=0;

    // ── Status text for lobby ─────────────────────────────────
    private String lobbyStatus = "";

    // ── Input ─────────────────────────────────────────────────
    public volatile boolean iUp,iDown,iLeft,iRight,iFire;
    private boolean pUp,pDown,pLeft,pRight,pFire;

    // ── Machine ───────────────────────────────────────────────
    private final Machine M;

    public MazeWarGame(Machine m) { this.M = m; }

    // ─────────────────────────────────────────────────────────
    //  PUBLIC API
    // ─────────────────────────────────────────────────────────
    public void tick() {
        int k = M.keyboard & 0x7F;
        iUp    |= (k=='W'); iDown  |= (k=='S');
        iLeft  |= (k=='A'); iRight |= (k=='D');
        iFire  |= (k==' ' || k=='F');

        switch (state) {
            case TITLE: tickTitle(); break;
            case LOBBY: tickLobby(); break;
            case PLAY:  tickPlay();  break;
            case DEAD:  tickDead();  break;
        }
        pUp=iUp; pDown=iDown; pLeft=iLeft; pRight=iRight; pFire=iFire;
        frame++;
    }

    public void draw() {
        switch (state) {
            case TITLE: drawTitle(); break;
            case LOBBY: drawLobby(); break;
            case PLAY:  drawPlay();  break;
            case DEAD:  drawDead();  break;
        }
    }

    // ── Called from Activity buttons ──────────────────────────
    public void startSinglePlayer() { multiMode=false; startGame(new Random().nextLong()); }

    public void hostMulti(NetSession n) {
        net = n; multiMode = true;
        net.setEventListener(this);
        state = State.LOBBY;
        lobbyStatus = "HOSTING... WAIT FOR GUEST";
    }

    public void joinMulti(NetSession n) {
        net = n; multiMode = true;
        net.setEventListener(this);
        state = State.LOBBY;
        lobbyStatus = "SEARCHING FOR HOST...";
    }

    public void stopNet() {
        if (net != null) { net.stop(); net = null; }
        multiMode = false;
        state = State.TITLE;
    }

    // ─────────────────────────────────────────────────────────
    //  NetGame.Listener callbacks (from network thread)
    // ─────────────────────────────────────────────────────────
    @Override
    public void onConnected(boolean asHost, long seed) {
        mazeSeed = seed;
        genMaze(seed);
        // Players start on opposite corners
        if (asHost) { px=1;    py=1;    pdir=0; netX=14; netY=14; netDir=2; }
        else        { px=14;   py=14;   pdir=2; netX=1;  netY=1;  netDir=0; }
        hp=3; score=0; netHp=3; netScore=0; netAlive=true;
        bullets.clear();
        state = State.PLAY;
        msg="CONNECTED! FIGHT!"; msgT=50;
    }

    @Override
    public void onPeerMazeState(int x, int y, int dir, int hp2, int sc) {
        netX=x; netY=y; netDir=dir; netHp=hp2; netScore=sc;
        netAlive = (hp2>0);
    }


    @Override
    public void onPeerSync(int demoIdx, int keyboard) {
        // Demo sync noted (handled by EmulatorActivity)
    }

    @Override
    public void onPeerBullet(int dir) {
        Bullet b = new Bullet();
        b.x = netX+.5; b.y = netY+.5;
        b.dir = dir; b.fromPlayer = false;
        bullets.add(b);
    }

    @Override
    public void onPeerKilled() {
        netAlive = false; netHitFlash = 20;
        msg = "OPPONENT KILLED!"; msgT = 40;
    }

    @Override
    public void onDisconnected() {
        msg = "DISCONNECTED"; msgT = 80;
        multiMode = false;
        if (state == State.PLAY) state = State.DEAD;
        else state = State.TITLE;
    }

    // ─────────────────────────────────────────────────────────
    //  TITLE
    // ─────────────────────────────────────────────────────────
    private void tickTitle() {
        boolean anyNew = (iUp||iDown||iLeft||iRight||iFire)
                       && !(pUp||pDown||pLeft||pRight||pFire);
        if (anyNew) startGame(new Random().nextLong());
    }

    private void drawTitle() {
        // Eyeball
        double t = frame * 0.04;
        int ex=VCX+100, ey=VCY, rx=90, ry=55;
        circle(ex,ey,rx,ry,20,0.9f);
        circle(ex,ey,rx/3,(int)(ry*.8f),12,1f);
        for (int i=-3;i<=3;i++){if(i==0) continue;
            vl(ex+i*28,ey+ry+2,ex+i*28+i*5,ey+ry+28,0.55f);}

        txt("MAZE WAR",       VX0+10, VCY+60, 18, 1.0f);
        txt("IMLAC PDS-1  1974", VX0+10, VCY+10, 10, 0.5f);
        txt("SINGLE PLAYER  -  ANY BUTTON", VX0+10, VCY-40, 8, 0.4f);
        txt("MULTIPLAYER  -  USE MENU BELOW", VX0+10, VCY-70, 8, 0.35f);
        if ((frame/20)%2==0)
            txt("PRESS ANY BUTTON FOR SINGLE", VX0+10, VCY-110, 9, 0.8f);
    }

    // ─────────────────────────────────────────────────────────
    //  LOBBY
    // ─────────────────────────────────────────────────────────
    private void tickLobby() {
        // Animated waiting - state transitions handled by network callbacks
    }

    private void drawLobby() {
        // Spinning dash
        String[] spin = {"|","/"," -","\\"};
        String sp = spin[(frame/8)%4];
        txt("MAZE WAR  ONLINE", VCX-200, VCY+80, 13, 0.9f);
        txt(lobbyStatus, VCX-lobbyStatus.length()*11, VCY+10, 11, 0.7f);
        txt(sp, VCX-10, VCY-50, 16, 0.6f);
        txt("CANCEL  -  BACK BUTTON", VCX-200, VCY-110, 8, 0.25f);
    }

    // ─────────────────────────────────────────────────────────
    //  GAME INIT
    // ─────────────────────────────────────────────────────────
    private void startGame(long seed) {
        mazeSeed=seed; genMaze(seed);
        px=1; py=1; pdir=0; hp=3; score=0; level=1;
        moveCd=0; turnCd=0; fireCd=0; hitFlash=0; killFlash=0;
        bullets.clear(); aiEnemies.clear();
        if (!multiMode) spawnAI(level+1);
        state = State.PLAY;
    }

    // ─────────────────────────────────────────────────────────
    //  MAZE
    // ─────────────────────────────────────────────────────────
    private void genMaze(long seed) {
        Arrays.fill(maze,0xF);
        Random rnd = new Random(seed);
        boolean[] vis = new boolean[MZ*MZ];
        carve(1,1,vis,rnd);
    }
    private void carve(int x, int y, boolean[] vis, Random rnd) {
        vis[y*MZ+x]=true;
        int[] d={0,1,2,3};
        for (int i=3;i>0;i--){int j=rnd.nextInt(i+1);int t=d[i];d[i]=d[j];d[j]=t;}
        for (int dd:d){
            int nx=x+DX[dd],ny=y+DY[dd];
            if (nx<1||nx>=MZ-1||ny<1||ny>=MZ-1||vis[ny*MZ+nx]) continue;
            maze[y*MZ+x]   &=~(1<<dd);
            maze[ny*MZ+nx] &=~(1<<OPP[dd]);
            carve(nx,ny,vis,rnd);
        }
    }
    private boolean wall(int x,int y,int dir){
        if(x<0||x>=MZ||y<0||y>=MZ) return true;
        return (maze[y*MZ+x]&(1<<dir))!=0;
    }
    private boolean solid(int x,int y){
        if(x<0||x>=MZ||y<0||y>=MZ) return true;
        return maze[y*MZ+x]==0xF;
    }
    private void spawnAI(int n){
        for(int i=0;i<n;i++){
            Enemy e=new Enemy();
            Random r=new Random();
            for(int t=0;t<200;t++){
                e.x=2+r.nextInt(MZ-4); e.y=2+r.nextInt(MZ-4);
                if(!solid(e.x,e.y)&&Math.abs(e.x-px)+Math.abs(e.y-py)>3) break;
            }
            e.dir=new Random().nextInt(4); aiEnemies.add(e);
        }
    }

    // ─────────────────────────────────────────────────────────
    //  PLAY TICK
    // ─────────────────────────────────────────────────────────
    private void tickPlay() {
        if(moveCd>0)moveCd--; if(turnCd>0)turnCd--;
        if(fireCd>0)fireCd--; if(hitFlash>0)hitFlash--;
        if(killFlash>0)killFlash--; if(msgT>0)msgT--;
        if(netHitFlash>0)netHitFlash--;

        // Turn (edge)
        if(turnCd==0){
            if(iLeft&&!pLeft){ pdir=(pdir+3)%4; turnCd=8; }
            if(iRight&&!pRight){ pdir=(pdir+1)%4; turnCd=8; }
        }
        // Move
        if(moveCd==0){
            if(iUp&&!wall(px,py,pdir)){ px+=DX[pdir]; py+=DY[pdir]; moveCd=12; }
            else if(iDown&&!wall(px,py,(pdir+2)%4)){ px-=DX[pdir]; py-=DY[pdir]; moveCd=12; }
        }
        // Fire
        if(iFire&&!pFire&&fireCd==0){
            Bullet b=new Bullet(); b.x=px+.5; b.y=py+.5;
            b.dir=pdir; b.fromPlayer=true; bullets.add(b); fireCd=20;
            if(multiMode&&net!=null) net.sendBullet(pdir);
        }

        tickBullets();
        if(!multiMode) { tickAI(); checkWin(); }
        else           { tickNetPlayer(); }

        // Network send
        if(multiMode&&net!=null&&net.isConnected()){
            if(netSendCd<=0){ net.sendMazeState(px,py,pdir,hp,score); netSendCd=3; }
            else netSendCd--;
        }
    }

    private void tickBullets(){
        for(Bullet b:bullets){
            if(!b.alive) continue;
            b.life--; if(b.life<=0){b.alive=false;continue;}
            b.x+=DX[b.dir]*0.2; b.y+=DY[b.dir]*0.2;
            if(solid((int)b.x,(int)b.y)){b.alive=false;continue;}
            if(b.fromPlayer){
                // Hit AI
                for(Enemy e:aiEnemies){ if(!e.alive) continue;
                    if(Math.abs(b.x-(e.x+.5))<0.6&&Math.abs(b.y-(e.y+.5))<0.6){
                        e.alive=false;b.alive=false;score++;killFlash=12;
                        msg="KILL";msgT=30;break;}}
                // Hit net player
                if(multiMode&&netAlive&&
                   Math.abs(b.x-(netX+.5))<0.6&&Math.abs(b.y-(netY+.5))<0.6){
                    b.alive=false; netAlive=false; netHitFlash=20; score++;
                    if(net!=null) net.sendKill();
                    msg="YOU KILLED OPPONENT!"; msgT=50;
                }
            } else {
                // Hit local player
                if(Math.abs(b.x-(px+.5))<0.55&&Math.abs(b.y-(py+.5))<0.55){
                    b.alive=false; hp--; hitFlash=18;
                    msg=(hp>0?"HIT! HP:"+hp:"YOU DIED"); msgT=45;
                    if(hp<=0) state=State.DEAD;
                }
            }
        }
        bullets.removeIf(b->!b.alive);
    }

    private void tickAI(){
        for(Enemy e:aiEnemies){ if(!e.alive) continue;
            e.think--; e.fireCd--;
            if(e.think<=0){
                e.think=15+(int)(Math.random()*25);
                int dx=px-e.x,dy=py-e.y; int want=-1;
                if(Math.abs(dx)>Math.abs(dy)) want=dx>0?1:3;
                else if(dy!=0) want=dy>0?0:2;
                if(Math.random()<0.6&&want>=0&&!wall(e.x,e.y,want)){
                    e.dir=want;e.x+=DX[want];e.y+=DY[want];
                } else {
                    int[] ds={0,1,2,3};
                    for(int i=3;i>0;i--){int j=(int)(Math.random()*(i+1));int t=ds[i];ds[i]=ds[j];ds[j]=t;}
                    for(int dd:ds){if(!wall(e.x,e.y,dd)){e.dir=dd;e.x+=DX[dd];e.y+=DY[dd];break;}}
                }
            }
            if(e.fireCd<=0){
                boolean sh=false;
                if(e.dir==0&&e.x==px&&py>e.y) sh=los(e.x,e.y,px,py);
                if(e.dir==2&&e.x==px&&py<e.y) sh=los(px,py,e.x,e.y);
                if(e.dir==1&&e.y==py&&px>e.x) sh=los(e.x,e.y,px,py);
                if(e.dir==3&&e.y==py&&px<e.x) sh=los(px,py,e.x,e.y);
                if(sh){Bullet b=new Bullet();b.x=e.x+.5;b.y=e.y+.5;
                    b.dir=e.dir;b.fromPlayer=false;bullets.add(b);
                    e.fireCd=60+(int)(Math.random()*60);}
            }
        }
    }

    private void tickNetPlayer(){
        // net player state updated via onPeerState callback
        // respawn after kill
        if(!netAlive && netHitFlash<=0) netAlive=true;
    }

    private boolean los(int x1,int y1,int x2,int y2){
        if(x1==x2){for(int y=y1;y<y2;y++) if(wall(x1,y,0)) return false;}
        else{for(int x=x1;x<x2;x++) if(wall(x,y1,1)) return false;}
        return true;
    }

    private void checkWin(){
        for(Enemy e:aiEnemies) if(e.alive) return;
        level++; msg="LEVEL "+level+"!"; msgT=60;
        genMaze(new Random().nextLong()); px=1;py=1;pdir=0;
        bullets.clear(); aiEnemies.clear(); spawnAI(Math.min(level+1,7));
    }

    private void tickDead(){
        boolean anyNew=(iUp||iDown||iLeft||iRight||iFire)&&!(pUp||pDown||pLeft||pRight||pFire);
        if(anyNew){ multiMode=false; state=State.TITLE; }
    }

    // ─────────────────────────────────────────────────────────
    //  DRAW
    // ─────────────────────────────────────────────────────────
    private void drawPlay(){
        vl(VX0,VY0,VX1,VY0,.5f);vl(VX1,VY0,VX1,VY1,.5f);
        vl(VX1,VY1,VX0,VY1,.5f);vl(VX0,VY1,VX0,VY0,.5f);
        if(hitFlash>0){float f=hitFlash/18f;
            vl(VX0,VY0,VX1,VY0,f);vl(VX1,VY0,VX1,VY1,f);
            vl(VX1,VY1,VX0,VY1,f);vl(VX0,VY1,VX0,VY0,f);}
        draw3D(); drawEnemiesInView(); drawHUD();
        if(msgT>0){float b=Math.min(1f,msgT/20f); txt(msg,VCX-msg.length()*11,VCY-60,13,b);}
        // Net indicator
        if(multiMode){ txt(net!=null&&net.isConnected()?"NET OK":"NET...", VX0+8,VY0-22,7,0.4f);}
    }

    private void draw3D(){
        final int MAX=10;
        int depth=0; int wx=px,wy=py;
        for(int d=1;d<=MAX;d++){
            if(wall(wx,wy,pdir)){depth=d-1;break;}
            wx+=DX[pdir];wy+=DY[pdir];
            if(solid(wx,wy)){depth=d-1;break;}
            depth=d;
        }
        depth=Math.max(0,depth);

        int[] lt=new int[MAX+2],rt=new int[MAX+2],tp=new int[MAX+2],bt=new int[MAX+2];
        for(int d=0;d<=depth+1;d++){
            float sc=1.4f/(d+1f);
            lt[d]=cx(VCX-(int)(VW/2f*sc)); rt[d]=cx(VCX+(int)(VW/2f*sc));
            tp[d]=cy(VCY-(int)(VH/2f*sc)); bt[d]=cy(VCY+(int)(VH/2f*sc));
        }

        int cx2=px,cy2=py;
        for(int d=0;d<=depth;d++){
            float bright=Math.max(0.2f,1f-d*0.1f);
            boolean hl=!wall(cx2,cy2,(pdir+3)%4);
            boolean hr=!wall(cx2,cy2,(pdir+1)%4);
            boolean hf=!wall(cx2,cy2,pdir)&&d<depth;
            if(!hl){vl(lt[d],tp[d],lt[d+1],tp[d+1],bright*.8f);vl(lt[d],bt[d],lt[d+1],bt[d+1],bright*.8f);vl(lt[d+1],tp[d+1],lt[d+1],bt[d+1],bright*.6f);}
            else{vl(lt[d],tp[d],lt[d],bt[d],bright*.5f);}
            if(!hr){vl(rt[d],tp[d],rt[d+1],tp[d+1],bright*.8f);vl(rt[d],bt[d],rt[d+1],bt[d+1],bright*.8f);vl(rt[d+1],tp[d+1],rt[d+1],bt[d+1],bright*.6f);}
            else{vl(rt[d],tp[d],rt[d],bt[d],bright*.5f);}
            if(!hf){vl(lt[d+1],tp[d+1],rt[d+1],tp[d+1],bright);vl(lt[d+1],bt[d+1],rt[d+1],bt[d+1],bright);
                    vl(lt[d+1],tp[d+1],lt[d+1],bt[d+1],bright*.8f);vl(rt[d+1],tp[d+1],rt[d+1],bt[d+1],bright*.8f);break;}
            cx2+=DX[pdir]; cy2+=DY[pdir];
        }
        // Vanishing lines
        vl(VX0,VY0,lt[0],tp[0],.35f);vl(VX1,VY0,rt[0],tp[0],.35f);
        vl(VX0,VY1,lt[0],bt[0],.35f);vl(VX1,VY1,rt[0],bt[0],.35f);
        // Crosshair
        vl(VCX-12,VCY,VCX-4,VCY,.6f);vl(VCX+4,VCY,VCX+12,VCY,.6f);
        vl(VCX,VCY-12,VCX,VCY-4,.6f);vl(VCX,VCY+4,VCX,VCY+12,.6f);
    }

    private void drawEnemiesInView(){
        // AI enemies
        for(Enemy e:aiEnemies) if(e.alive) drawEntityIfVisible(e.x,e.y,false);
        // Network player
        if(multiMode&&netAlive) drawEntityIfVisible(netX,netY,true);
    }

    private void drawEntityIfVisible(int ex,int ey,boolean isNet){
        int relDir=-1;
        if(pdir==0&&ex==px&&ey>py) relDir=0;
        if(pdir==1&&ey==py&&ex>px) relDir=1;
        if(pdir==2&&ex==px&&ey<py) relDir=2;
        if(pdir==3&&ey==py&&ex<px) relDir=3;
        if(relDir!=pdir) return;
        int dist=(pdir==0||pdir==2)?Math.abs(ey-py):Math.abs(ex-px);
        if(dist<1||dist>8) return;
        for(int d=0;d<dist;d++){
            int cx2=px+DX[pdir]*d,cy2=py+DY[pdir]*d;
            if(wall(cx2,cy2,pdir)) return;
        }
        float sc=1.4f/(dist+.5f);
        int sz=Math.max(8,Math.min((int)(VH*.25f*sc),120));
        float b=Math.max(.3f,.9f-dist*.08f);
        if(isNet&&netHitFlash>0) b=1.0f; // flash on hit
        drawEye(VCX,VCY,sz,b);
    }

    private void drawEye(int cx,int cy,int sz,float b){
        int rx=sz,ry=(int)(sz*.55f);
        circle(cx,cy,rx,ry,16,b);
        circle(cx,cy,rx/3,(int)(ry*.7f),10,b*1.1f);
        vl(cx-rx,cy,cx+rx,cy,b*.3f);
        if(sz>25) for(int i=-2;i<=2;i++){if(i==0)continue;
            vl(cx+i*(rx/3),cy+ry+2,cx+i*(rx/3)+i*4,cy+ry+20,b*.6f);}
    }

    private void drawHUD(){
        for(int i=0;i<3;i++){int hx=VX0+20+i*28,hy=VY1+25;
            if(i<hp) circle(hx,hy,9,9,8,.9f); else circle(hx,hy,9,9,6,.2f);}
        txt(String.format("%04d",score),VX1-120,VY1+18,9,.7f);
        txt(new String[]{"N","E","S","W"}[pdir],VX1+15,VY1+18,10,.6f);
        txt("LV"+level,VCX-32,VY0-22,9,.35f);
        if(fireCd>0) vl(VCX-40,VY1+52,VCX-40+(int)(fireCd/20f*80),VY1+52,.4f);
        // Net player score
        if(multiMode){ txt("OPP:"+String.format("%04d",netScore),VX0+8,VY1+18,9,.5f); }
    }

    private void drawDead(){
        txt("GAME OVER",VCX-190,VCY+80,18,.9f);
        txt("SCORE "+score,VCX-160,VCY+10,13,.7f);
        if((frame/20)%2==0) txt("PRESS ANY BUTTON",VCX-215,VCY-70,11,.85f);
    }

    // ─────────────────────────────────────────────────────────
    //  DRAW HELPERS
    // ─────────────────────────────────────────────────────────
    private void vl(int x1,int y1,int x2,int y2,float b){M.dlLine(x1,y1,x2,y2,b);}
    private int cx(int x){return Math.max(VX0,Math.min(VX1,x));}
    private int cy(int y){return Math.max(VY0,Math.min(VY1,y));}

    private void circle(int cx,int cy,int rx,int ry,int segs,float b){
        int ppx=cx+rx,ppy=cy;
        for(int i=1;i<=segs;i++){
            double a=i/(double)segs*2*Math.PI;
            int nx=cx+(int)(Math.cos(a)*rx),ny=cy+(int)(Math.sin(a)*ry);
            vl(ppx,ppy,nx,ny,b);ppx=nx;ppy=ny;
        }
    }

    // ── Vector font ───────────────────────────────────────────
    private static final float[][][] F={
        {{0,0,2,4},{2,4,4,0},{1,2,3,2}},{{0,0,0,4},{0,4,2,4},{0,2,2,2},{0,0,2,0},{2,4,3,3},{3,3,2,2},{2,2,3,1},{3,1,2,0}},
        {{3,4,0,4},{0,4,0,0},{0,0,3,0}},{{0,0,0,4},{0,4,2,4},{2,4,4,2},{4,2,2,0},{2,0,0,0}},
        {{0,0,0,4},{0,4,4,4},{0,2,3,2},{0,0,4,0}},{{0,0,0,4},{0,4,4,4},{0,2,3,2}},
        {{3,4,0,4},{0,4,0,0},{0,0,4,0},{4,0,4,2},{4,2,2,2}},{{0,0,0,4},{4,0,4,4},{0,2,4,2}},
        {{1,0,3,0},{1,4,3,4},{2,0,2,4}},{{1,4,3,4},{3,4,3,0},{3,0,0,0}},
        {{0,0,0,4},{0,2,4,4},{0,2,4,0}},{{0,4,0,0},{0,0,4,0}},
        {{0,0,0,4},{0,4,2,2},{2,2,4,4},{4,4,4,0}},{{0,0,0,4},{0,4,4,0},{4,0,4,4}},
        {{0,0,4,0},{4,0,4,4},{4,4,0,4},{0,4,0,0}},{{0,0,0,4},{0,4,3,4},{3,4,4,3},{4,3,3,2},{3,2,0,2}},
        {{0,0,4,0},{4,0,4,4},{4,4,0,4},{0,4,0,0},{2,2,4,0}},{{0,0,0,4},{0,4,3,4},{3,4,4,3},{4,3,3,2},{3,2,0,2},{2,2,4,0}},
        {{4,4,0,4},{0,4,0,2},{0,2,4,2},{4,2,4,0},{4,0,0,0}},{{0,4,4,4},{2,4,2,0}},
        {{0,4,0,0},{0,0,4,0},{4,0,4,4}},{{0,4,2,0},{2,0,4,4}},
        {{0,4,1,0},{1,0,2,2},{2,2,3,0},{3,0,4,4}},{{0,0,4,4},{4,0,0,4}},
        {{0,4,2,2},{4,4,2,2},{2,2,2,0}},{{0,4,4,4},{4,4,0,0},{0,0,4,0}},
        {{0,0,4,0},{4,0,4,4},{4,4,0,4},{0,4,0,0},{0,0,4,4}},{{1,4,2,4},{2,4,2,0},{1,0,3,0}},
        {{0,4,4,4},{4,4,4,3},{4,3,0,1},{0,1,0,0},{0,0,4,0}},{{0,4,4,4},{4,4,4,0},{0,0,4,0},{0,2,4,2}},
        {{0,4,0,2},{0,2,4,2},{4,4,4,0}},{{4,4,0,4},{0,4,0,2},{0,2,4,2},{4,2,4,0},{4,0,0,0}},
        {{4,4,0,4},{0,4,0,0},{0,0,4,0},{4,0,4,2},{4,2,0,2}},{{0,4,4,4},{4,4,2,0}},
        {{0,0,4,0},{4,0,4,4},{4,4,0,4},{0,4,0,0},{0,2,4,2}},{{4,0,4,4},{4,4,0,4},{0,4,0,2},{0,2,4,2}},
        {}
    };
    private static final String CH="ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ";
    private void ch(char c,int ox,int oy,float sc,float b){
        int i=CH.indexOf(Character.toUpperCase(c));
        if(i<0||i>=F.length) return;
        for(float[] s:F[i]) vl(ox+(int)(s[0]*sc),oy+(int)(s[1]*sc),ox+(int)(s[2]*sc),oy+(int)(s[3]*sc),b);
    }
    private void txt(String s,int ox,int oy,float sc,float b){
        int x=ox; for(char c:s.toCharArray()){ch(c,x,oy,sc,b);x+=(int)(sc*5.5f);}
    }
}
