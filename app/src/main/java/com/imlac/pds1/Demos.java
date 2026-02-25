package com.imlac.pds1;

/**
 * Built-in demo programs for the Imlac PDS-1 emulator.
 * Each demo fills Machine.vectors[] with draw commands
 * that CrtView then renders as phosphor vector graphics.
 */
public class Demos {

    public enum Type {
        LINES, STAR, LISSAJOUS, TEXT, BOUNCE, MAZE, SPACEWAR, SCOPE
    }

    private final Machine M;
    private Type   current = Type.STAR;
    private double angle   = 0;
    private double t       = 0;
    private int    frame   = 0;

    // Demo state
    private double ballX = 512, ballY = 512, ballVx = 7.3, ballVy = 5.8;
    private final double[] trailX = new double[16];
    private final double[] trailY = new double[16];
    private int trailN = 0;

    private int[][] mazeGrid;      // [y][x] = wall bits N/E/S/W
    private boolean mazeReady = false;
    private static final int MW = 18, MH = 14;

    private double sw1x=350,sw1y=512,sw1a=0,sw1vx=0,sw1vy=0;
    private double sw2x=674,sw2y=512,sw2a=Math.PI,sw2vx=0,sw2vy=0;
    private double[] bx=new double[4],by=new double[4];
    private double[] bvx=new double[4],bvy=new double[4];
    private int[]    blife=new int[4];
    private boolean  swInit=false;

    private double textScroll = 0;

    public Demos(Machine machine) { this.M = machine; }

    public void setDemo(Type t) { this.current = t; }
    public Type getDemo() { return current; }

    public void runCurrentDemo() {
        switch (current) {
            case LINES:     demoLines();     break;
            case STAR:      demoStar();      break;
            case LISSAJOUS: demoLissajous(); break;
            case TEXT:      demoText();      break;
            case BOUNCE:    demoBounce();    break;
            case MAZE:      demoMaze();      break;
            case SPACEWAR:  demoSpacewar();  break;
            case SCOPE:     demoScope();     break;
        }
        angle += 0.018;
        t     += 0.016;
        frame++;
    }

    // ── Vector helpers ────────────────────────────────────────
    private void vl(int x1, int y1, int x2, int y2, float b) {
        M.dlLine(x1,y1,x2,y2,b);
    }
    private void vp(int x, int y, float b) {
        M.dlPoint(x,y,b);
    }
    private void rect(int x, int y, int w, int h, float b) {
        vl(x,y,x+w,y,b); vl(x+w,y,x+w,y+h,b);
        vl(x+w,y+h,x,y+h,b); vl(x,y+h,x,y,b);
    }
    private void circle(int cx, int cy, int r, int segs, float b) {
        double prev_a = 0;
        int px = cx+(int)(Math.cos(0)*r), py = cy+(int)(Math.sin(0)*r);
        for (int i = 1; i <= segs; i++) {
            double a = (double)i/segs * 2*Math.PI;
            int nx = cx+(int)(Math.cos(a)*r);
            int ny = cy+(int)(Math.sin(a)*r);
            vl(px,py,nx,ny,b);
            px=nx; py=ny;
        }
    }

    // ── Vector font ───────────────────────────────────────────
    // Strokes: {x1,y1,x2,y2} on a 4×4 grid, Y-up
    private static final float[][][] FONT = {
        {/* A */{0,0,2,4},{2,4,4,0},{1,2,3,2}},
        {/* B */{0,0,0,4},{0,4,2,4},{0,2,2,2},{0,0,2,0},{2,4,3,3},{3,3,2,2},{2,2,3,1},{3,1,2,0}},
        {/* C */{3,4,0,4},{0,4,0,0},{0,0,3,0}},
        {/* D */{0,0,0,4},{0,4,2,4},{2,4,4,2},{4,2,2,0},{2,0,0,0}},
        {/* E */{0,0,0,4},{0,4,4,4},{0,2,3,2},{0,0,4,0}},
        {/* F */{0,0,0,4},{0,4,4,4},{0,2,3,2}},
        {/* G */{3,4,0,4},{0,4,0,0},{0,0,4,0},{4,0,4,2},{4,2,2,2}},
        {/* H */{0,0,0,4},{4,0,4,4},{0,2,4,2}},
        {/* I */{1,0,3,0},{1,4,3,4},{2,0,2,4}},
        {/* J */{1,4,3,4},{3,4,3,0},{3,0,0,0}},
        {/* K */{0,0,0,4},{0,2,4,4},{0,2,4,0}},
        {/* L */{0,4,0,0},{0,0,4,0}},
        {/* M */{0,0,0,4},{0,4,2,2},{2,2,4,4},{4,4,4,0}},
        {/* N */{0,0,0,4},{0,4,4,0},{4,0,4,4}},
        {/* O */{0,0,4,0},{4,0,4,4},{4,4,0,4},{0,4,0,0}},
        {/* P */{0,0,0,4},{0,4,3,4},{3,4,4,3},{4,3,3,2},{3,2,0,2}},
        {/* Q */{0,0,4,0},{4,0,4,4},{4,4,0,4},{0,4,0,0},{2,2,4,0}},
        {/* R */{0,0,0,4},{0,4,3,4},{3,4,4,3},{4,3,3,2},{3,2,0,2},{2,2,4,0}},
        {/* S */{4,4,0,4},{0,4,0,2},{0,2,4,2},{4,2,4,0},{4,0,0,0}},
        {/* T */{0,4,4,4},{2,4,2,0}},
        {/* U */{0,4,0,0},{0,0,4,0},{4,0,4,4}},
        {/* V */{0,4,2,0},{2,0,4,4}},
        {/* W */{0,4,1,0},{1,0,2,2},{2,2,3,0},{3,0,4,4}},
        {/* X */{0,0,4,4},{4,0,0,4}},
        {/* Y */{0,4,2,2},{4,4,2,2},{2,2,2,0}},
        {/* Z */{0,4,4,4},{4,4,0,0},{0,0,4,0}},
        {/* 0 */{0,0,4,0},{4,0,4,4},{4,4,0,4},{0,4,0,0},{0,0,4,4}},
        {/* 1 */{1,4,2,4},{2,4,2,0},{1,0,3,0}},
        {/* 2 */{0,4,4,4},{4,4,4,3},{4,3,0,1},{0,1,0,0},{0,0,4,0}},
        {/* 3 */{0,4,4,4},{4,4,4,0},{0,0,4,0},{0,2,4,2}},
        {/* 4 */{0,4,0,2},{0,2,4,2},{4,4,4,0}},
        {/* 5 */{4,4,0,4},{0,4,0,2},{0,2,4,2},{4,2,4,0},{4,0,0,0}},
        {/* 6 */{4,4,0,4},{0,4,0,0},{0,0,4,0},{4,0,4,2},{4,2,0,2}},
        {/* 7 */{0,4,4,4},{4,4,2,0}},
        {/* 8 */{0,0,4,0},{4,0,4,4},{4,4,0,4},{0,4,0,0},{0,2,4,2}},
        {/* 9 */{4,0,4,4},{4,4,0,4},{0,4,0,2},{0,2,4,2}},
        {/* - */{0,2,4,2}},
        {/* . */{2,0,2,0}},
        {/* : */{2,1,2,1},{2,3,2,3}},
        {/* ! */{2,4,2,1},{2,0,2,0}},
        {/* SPACE */},
    };
    private static final String CHARSET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-.:! ";

    private void vchar(char c, int ox, int oy, float scale, float b) {
        char cu = Character.toUpperCase(c);
        int idx = CHARSET.indexOf(cu);
        if (idx < 0 || idx >= FONT.length) return;
        for (float[] s : FONT[idx]) {
            vl(ox+(int)(s[0]*scale), oy+(int)(s[1]*scale),
               ox+(int)(s[2]*scale), oy+(int)(s[3]*scale), b);
        }
    }

    private void vtext(String str, int ox, int oy, float scale, float b) {
        int x = ox;
        for (char c : str.toCharArray()) {
            if (c == '\n') { oy -= (int)(scale*6); x = ox; continue; }
            vchar(c, x, oy, scale, b);
            x += (int)(scale * 5.5f);
        }
    }

    private void border(float b) { rect(20,20,984,984,b); }

    // ── LINES ─────────────────────────────────────────────────
    private void demoLines() {
        int cx=512,cy=512,r=450;
        for (int i=0;i<20;i++){
            double a1=(double)i/20*2*Math.PI+angle;
            double a2=(double)(i+7)/20*2*Math.PI+angle*0.7;
            vl(cx+(int)(Math.cos(a1)*r),cy+(int)(Math.sin(a1)*r),
               cx+(int)(Math.cos(a2)*r/2),cy+(int)(Math.sin(a2)*r/2),0.85f);
        }
        for(int i=0;i<8;i++){
            double a=(double)i/8*2*Math.PI-angle*0.3;
            vl(cx,cy,cx+(int)(Math.cos(a)*r),cy+(int)(Math.sin(a)*r),0.3f);
        }
        border(0.5f);
        vtext("IMLAC PDS-1",280,80,16,0.7f);
        vtext("ROTATING LINES",200,30,10,0.4f);
    }

    // ── STAR ──────────────────────────────────────────────────
    private void demoStar() {
        int cx=512,cy=512;
        drawStar(cx,cy,7,400,160,angle,1.0f);
        drawStar(cx,cy,5,120,50,-angle*2.5,0.7f);
        border(0.4f);
        vtext("STAR",380,60,20,0.6f);
    }

    private void drawStar(int cx,int cy,int pts,int r1,int r2,double a0,float b){
        int n=pts*2;
        for(int i=0;i<n;i++){
            double a1=(double)i/n*2*Math.PI+a0;
            double a2=(double)(i+1)/n*2*Math.PI+a0;
            int ra=(i%2==0)?r1:r2, rb=((i+1)%2==0)?r1:r2;
            vl(cx+(int)(Math.cos(a1)*ra),cy+(int)(Math.sin(a1)*ra),
               cx+(int)(Math.cos(a2)*rb),cy+(int)(Math.sin(a2)*rb),b);
        }
    }

    // ── LISSAJOUS ─────────────────────────────────────────────
    private void demoLissajous() {
        double a=3,b=2;
        int px=-1,py=-1;
        for(int i=0;i<=600;i++){
            double tt=(double)i/600*2*Math.PI;
            int x=512+(int)(460*Math.sin(a*tt+angle));
            int y=512+(int)(460*Math.sin(b*tt));
            if(px>=0) vl(px,py,x,y,0.85f);
            px=x;py=y;
        }
        border(0.4f);
        vtext("LISSAJOUS",300,60,16,0.5f);
    }

    // ── TEXT ──────────────────────────────────────────────────
    private final String[] TEXT_LINES = {
        "IMLAC PDS-1","1970 MIT AI LAB","PROGRAMMED","DISPLAY SYSTEM",
        "16-BIT CPU","4096 WORDS RAM","VECTOR CRT","1024 X 1024",
        "LIGHT PEN","SPACEWAR 1974","ARPANET NODE","LOGO LANGUAGE"
    };

    private void demoText() {
        for(int i=0;i<TEXT_LINES.length;i++){
            int y=(int)(780-i*140+textScroll)%1100-100;
            if(y>-80&&y<1050) vtext(TEXT_LINES[i],80,y,20,0.9f);
        }
        textScroll+=1.5;
        if(textScroll>TEXT_LINES.length*145) textScroll=0;
        border(0.3f);
    }

    // ── BOUNCE ────────────────────────────────────────────────
    private void demoBounce() {
        ballX+=ballVx; ballY+=ballVy;
        if(ballX<60||ballX>964){ballVx*=-1;ballX=Math.max(60,Math.min(964,ballX));}
        if(ballY<60||ballY>964){ballVy*=-1;ballY=Math.max(60,Math.min(964,ballY));}
        if(trailN<15){trailX[trailN]=ballX;trailY[trailN]=ballY;trailN++;}
        else{
            System.arraycopy(trailX,1,trailX,0,14);
            System.arraycopy(trailY,1,trailY,0,14);
            trailX[14]=ballX;trailY[14]=ballY;
        }
        for(int i=0;i<trailN-1;i++) vp((int)trailX[i],(int)trailY[i],(float)(i+1)/trailN*0.4f);
        circle((int)ballX,(int)ballY,35,16,1.0f);
        vl((int)ballX-50,(int)ballY,(int)ballX+50,(int)ballY,0.25f);
        vl((int)ballX,(int)ballY-50,(int)ballX,(int)ballY+50,0.25f);
        circle(60,60,20,8,0.4f); circle(964,60,20,8,0.4f);
        circle(60,964,20,8,0.4f); circle(964,964,20,8,0.4f);
        rect(20,20,984,984,0.6f);
        vtext("BOUNCE",350,40,14,0.6f);
    }

    // ── MAZE ──────────────────────────────────────────────────
    private void demoMaze() {
        if(!mazeReady) initMaze();
        int cw=(1024-60)/MW, ch=(1024-60)/MH, ox=30, oy=30;
        for(int y=0;y<MH;y++) for(int x=0;x<MW;x++){
            int cell=mazeGrid[y][x];
            int px=ox+x*cw, py=oy+y*ch;
            if((cell&1)!=0) vl(px,py+ch,px+cw,py+ch,0.85f); // N
            if((cell&2)!=0) vl(px+cw,py,px+cw,py+ch,0.85f); // E
            if((cell&4)!=0) vl(px,py,px+cw,py,0.85f);       // S
            if((cell&8)!=0) vl(px,py,px,py+ch,0.85f);       // W
        }
        circle(ox+cw/2,oy+ch/2,12,8,0.6f);
        circle(ox+(MW-1)*cw+cw/2,oy+(MH-1)*ch+ch/2,12,8,1.0f);
        vtext("MAZE",370,965,14,0.55f);
    }

    private void initMaze() {
        mazeGrid = new int[MH][MW];
        for(int[] row:mazeGrid) java.util.Arrays.fill(row,0xF);
        boolean[][] vis = new boolean[MH][MW];
        carve(0,0,vis);
        mazeReady=true;
    }

    private static final int[] CDX={0,1,0,-1}, CDY={1,0,-1,0}, COPP={2,3,0,1};

    private void carve(int x,int y,boolean[][] vis){
        vis[y][x]=true;
        Integer[] dirs={0,1,2,3};
        java.util.Arrays.sort(dirs,(a,b)->(int)(Math.random()*3)-1);
        for(int d:dirs){
            int nx=x+CDX[d],ny=y+CDY[d];
            if(nx<0||nx>=MW||ny<0||ny>=MH||vis[ny][nx]) continue;
            mazeGrid[y][x]  &=~(1<<d);
            mazeGrid[ny][nx]&=~(1<<COPP[d]);
            carve(nx,ny,vis);
        }
    }

    // ── SPACEWAR ──────────────────────────────────────────────
    private void demoSpacewar() {
        if(!swInit){for(int i=0;i<4;i++) blife[i]=0;swInit=true;}
        sw1a+=0.025; sw2a+=0.025;
        // Gravity
        double dx1=512-sw1x,dy1=512-sw1y,d1=Math.sqrt(dx1*dx1+dy1*dy1);
        if(d1>1){sw1vx+=dx1/d1*0.15;sw1vy+=dy1/d1*0.15;}
        double dx2=512-sw2x,dy2=512-sw2y,d2=Math.sqrt(dx2*dx2+dy2*dy2);
        if(d2>1){sw2vx+=dx2/d2*0.15;sw2vy+=dy2/d2*0.15;}
        sw1x+=sw1vx;sw1y+=sw1vy; sw2x+=sw2vx;sw2y+=sw2vy;
        sw1x=(sw1x%1024+1024)%1024; sw1y=(sw1y%1024+1024)%1024;
        sw2x=(sw2x%1024+1024)%1024; sw2y=(sw2y%1024+1024)%1024;
        // Fire
        if(frame%40==0) fireSW(sw1x,sw1y,sw1a,sw1vx,sw1vy);
        if(frame%53==0) fireSW(sw2x,sw2y,sw2a,sw2vx,sw2vy);
        // Bullets
        for(int i=0;i<4;i++){
            if(blife[i]<=0) continue; blife[i]--;
            bx[i]+=bvx[i]; by[i]+=bvy[i];
            vp((int)bx[i],(int)by[i],1.0f);
        }
        // Central star
        circle(512,512,25,12,0.6f); circle(512,512,8,8,1.0f);
        // Ships
        drawShip((int)sw1x,(int)sw1y,sw1a,1.0f);
        drawShip((int)sw2x,(int)sw2y,sw2a+Math.PI,0.85f);
        vtext("SPACEWAR",310,960,14,0.5f);
        rect(20,20,984,984,0.3f);
    }

    private void fireSW(double x,double y,double a,double vx,double vy){
        for(int i=0;i<4;i++){
            if(blife[i]>0) continue;
            bx[i]=x;by[i]=y;
            bvx[i]=Math.cos(a)*9+vx;
            bvy[i]=Math.sin(a)*9+vy;
            blife[i]=80;
            break;
        }
    }

    private void drawShip(int cx,int cy,double a,float b){
        double r1=30,r2=20,da=2.5;
        int p1x=cx+(int)(Math.cos(a)*r1),   p1y=cy+(int)(Math.sin(a)*r1);
        int p2x=cx+(int)(Math.cos(a+da)*r2), p2y=cy+(int)(Math.sin(a+da)*r2);
        int p3x=cx+(int)(Math.cos(a-da)*r2), p3y=cy+(int)(Math.sin(a-da)*r2);
        vl(p1x,p1y,p2x,p2y,b); vl(p2x,p2y,p3x,p3y,b); vl(p3x,p3y,p1x,p1y,b);
    }

    // ── SCOPE ─────────────────────────────────────────────────
    private void demoScope() {
        double[][] freqs={{1,1},{2,3},{3,4},{5,4}};
        float[] brs={0.9f,0.7f,0.55f,0.4f};
        for(int f=0;f<4;f++){
            double fa=freqs[f][0],fb=freqs[f][1],ph=angle*(f+1)*0.3;
            int px=-1,py=-1;
            for(int i=0;i<=400;i++){
                double tt=(double)i/400*2*Math.PI;
                int x=512+(int)(440*Math.sin(fa*tt+ph));
                int y=512+(int)(440*Math.sin(fb*tt));
                if(px>=0) vl(px,py,x,y,brs[f]);
                px=x;py=y;
            }
        }
        border(0.4f);
        vtext("SCOPE",380,60,14,0.5f);
    }
}
