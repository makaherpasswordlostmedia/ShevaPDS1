// Demos.swift — Built-in demo programs for Imlac PDS-1
// Ported from Demos.java

import Foundation

final class Demos {

    enum DemoType: Int, CaseIterable {
        case lines, star, lissajous, text, bounce, maze, spacewar, scope, userAsm, mazeWar
    }

    private let M: Machine
    var current: DemoType = .star
    private var angle  = 0.0
    private var t      = 0.0
    var frame          = 0

    private var ballX=512.0,ballY=512.0,ballVx=7.3,ballVy=5.8
    private var trailX=[Double](repeating:0,count:16)
    private var trailY=[Double](repeating:0,count:16)
    private var trailN=0

    private var mazeGrid=[[Int]]()
    private var mazeReady=false
    private let MW=18,MH=14

    private var sw1x=350.0,sw1y=512.0,sw1a=0.0,sw1vx=0.0,sw1vy=0.0
    private var sw2x=674.0,sw2y=512.0,sw2a=Double.pi,sw2vx=0.0,sw2vy=0.0
    private var bx=[Double](repeating:0,count:4),by=[Double](repeating:0,count:4)
    private var bvx=[Double](repeating:0,count:4),bvy=[Double](repeating:0,count:4)
    private var blife=[Int](repeating:0,count:4)
    private var swInit=false
    private var textScroll=0.0

    var mazeWarGame: MazeWarGame?
    func getMazeWarGame() -> MazeWarGame? { return mazeWarGame }
    func currentDemoIndex() -> Int { return current.rawValue }
    func initMazeWar() { if mazeWarGame == nil { mazeWarGame = MazeWarGame(machine: M) } }

    init(_ machine: Machine) { M = machine }

    func setDemo(_ t: DemoType) { current = t }

    func runCurrentDemo() {
        switch current {
        case .lines:     demoLines()
        case .star:      demoStar()
        case .lissajous: demoLissajous()
        case .text:      demoText()
        case .bounce:    demoBounce()
        case .maze:      demoMaze()
        case .spacewar:  demoSpacewar()
        case .scope:     demoScope()
        case .userAsm:   break
        case .mazeWar:   demoMazeWar()
        }
        angle += 0.018; t += 0.016; frame += 1
    }

    // ── Helpers ───────────────────────────────────────────────
    private func vl(_ x1:Int,_ y1:Int,_ x2:Int,_ y2:Int,_ b:Float) { M.dlLine(x1,y1,x2,y2,b) }
    private func vp(_ x:Int,_ y:Int,_ b:Float) { M.dlPoint(x,y,b) }
    private func rect(_ x:Int,_ y:Int,_ w:Int,_ h:Int,_ b:Float) {
        vl(x,y,x+w,y,b);vl(x+w,y,x+w,y+h,b);vl(x+w,y+h,x,y+h,b);vl(x,y+h,x,y,b)
    }
    private func circle(_ cx:Int,_ cy:Int,_ r:Int,_ segs:Int,_ b:Float) {
        var px=cx+r,py=cy
        for i in 1...segs {
            let a=Double(i)/Double(segs)*2*Double.pi
            let nx=cx+Int(cos(a)*Double(r)), ny=cy+Int(sin(a)*Double(r))
            vl(px,py,nx,ny,b); px=nx; py=ny
        }
    }
    private func border(_ b:Float) { rect(20,20,984,984,b) }

    // ── Vector font ───────────────────────────────────────────
    private let FONT: [[[Float]]] = [
        [[0,0,2,4],[2,4,4,0],[1,2,3,2]],
        [[0,0,0,4],[0,4,2,4],[0,2,2,2],[0,0,2,0],[2,4,3,3],[3,3,2,2],[2,2,3,1],[3,1,2,0]],
        [[3,4,0,4],[0,4,0,0],[0,0,3,0]],
        [[0,0,0,4],[0,4,2,4],[2,4,4,2],[4,2,2,0],[2,0,0,0]],
        [[0,0,0,4],[0,4,4,4],[0,2,3,2],[0,0,4,0]],
        [[0,0,0,4],[0,4,4,4],[0,2,3,2]],
        [[3,4,0,4],[0,4,0,0],[0,0,4,0],[4,0,4,2],[4,2,2,2]],
        [[0,0,0,4],[4,0,4,4],[0,2,4,2]],
        [[1,0,3,0],[1,4,3,4],[2,0,2,4]],
        [[1,4,3,4],[3,4,3,0],[3,0,0,0]],
        [[0,0,0,4],[0,2,4,4],[0,2,4,0]],
        [[0,4,0,0],[0,0,4,0]],
        [[0,0,0,4],[0,4,2,2],[2,2,4,4],[4,4,4,0]],
        [[0,0,0,4],[0,4,4,0],[4,0,4,4]],
        [[0,0,4,0],[4,0,4,4],[4,4,0,4],[0,4,0,0]],
        [[0,0,0,4],[0,4,3,4],[3,4,4,3],[4,3,3,2],[3,2,0,2]],
        [[0,0,4,0],[4,0,4,4],[4,4,0,4],[0,4,0,0],[2,2,4,0]],
        [[0,0,0,4],[0,4,3,4],[3,4,4,3],[4,3,3,2],[3,2,0,2],[2,2,4,0]],
        [[4,4,0,4],[0,4,0,2],[0,2,4,2],[4,2,4,0],[4,0,0,0]],
        [[0,4,4,4],[2,4,2,0]],
        [[0,4,0,0],[0,0,4,0],[4,0,4,4]],
        [[0,4,2,0],[2,0,4,4]],
        [[0,4,1,0],[1,0,2,2],[2,2,3,0],[3,0,4,4]],
        [[0,0,4,4],[4,0,0,4]],
        [[0,4,2,2],[4,4,2,2],[2,2,2,0]],
        [[0,4,4,4],[4,4,0,0],[0,0,4,0]],
        [[0,0,4,0],[4,0,4,4],[4,4,0,4],[0,4,0,0],[0,0,4,4]],
        [[1,4,2,4],[2,4,2,0],[1,0,3,0]],
        [[0,4,4,4],[4,4,4,3],[4,3,0,1],[0,1,0,0],[0,0,4,0]],
        [[0,4,4,4],[4,4,4,0],[0,0,4,0],[0,2,4,2]],
        [[0,4,0,2],[0,2,4,2],[4,4,4,0]],
        [[4,4,0,4],[0,4,0,2],[0,2,4,2],[4,2,4,0],[4,0,0,0]],
        [[4,4,0,4],[0,4,0,0],[0,0,4,0],[4,0,4,2],[4,2,0,2]],
        [[0,4,4,4],[4,4,2,0]],
        [[0,0,4,0],[4,0,4,4],[4,4,0,4],[0,4,0,0],[0,2,4,2]],
        [[4,0,4,4],[4,4,0,4],[0,4,0,2],[0,2,4,2]],
        []
    ]
    private let CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 "

    func vchar(_ c: Character, _ ox: Int, _ oy: Int, _ sc: Float, _ b: Float) {
        guard let i = CHARS.firstIndex(of: c.uppercased().first ?? c),
              i < CHARS.endIndex else { return }
        let idx = CHARS.distance(from: CHARS.startIndex, to: i)
        guard idx < FONT.count else { return }
        for s in FONT[idx] {
            vl(ox+Int(s[0]*sc),oy+Int(s[1]*sc),ox+Int(s[2]*sc),oy+Int(s[3]*sc),b)
        }
    }

    func vtext(_ s: String, _ ox: Int, _ oy: Int, _ sc: Float, _ b: Float) {
        var x = ox
        for c in s.uppercased() {
            vchar(c, x, oy, sc, b)
            x += Int(sc * 5.5)
        }
    }

    // ── LINES ─────────────────────────────────────────────────
    private func demoLines() {
        let cx=512,cy=512,r=450.0
        for i in 0..<20 {
            let a1=Double(i)/20*2*Double.pi+angle
            let a2=Double(i+7)/20*2*Double.pi+angle*0.7
            vl(cx+Int(cos(a1)*r),cy+Int(sin(a1)*r),cx+Int(cos(a2)*r/2),cy+Int(sin(a2)*r/2),0.85)
        }
        for i in 0..<8 {
            let a=Double(i)/8*2*Double.pi-angle*0.3
            vl(cx,cy,cx+Int(cos(a)*r),cy+Int(sin(a)*r),0.3)
        }
        border(0.5); vtext("IMLAC PDS-1",280,80,16,0.7); vtext("ROTATING LINES",200,30,10,0.4)
    }

    // ── STAR ──────────────────────────────────────────────────
    private func demoStar() {
        drawStar(512,512,7,400,160,angle,1.0)
        drawStar(512,512,5,120,50,-angle*2.5,0.7)
        border(0.4); vtext("STAR",380,60,20,0.6)
    }
    private func drawStar(_ cx:Int,_ cy:Int,_ pts:Int,_ r1:Int,_ r2:Int,_ a0:Double,_ b:Float){
        let n=pts*2
        for i in 0..<n {
            let a1=Double(i)/Double(n)*2*Double.pi+a0
            let a2=Double(i+1)/Double(n)*2*Double.pi+a0
            let ra=i%2==0 ? r1:r2, rb=(i+1)%2==0 ? r1:r2
            vl(cx+Int(cos(a1)*Double(ra)),cy+Int(sin(a1)*Double(ra)),
               cx+Int(cos(a2)*Double(rb)),cy+Int(sin(a2)*Double(rb)),b)
        }
    }

    // ── LISSAJOUS ─────────────────────────────────────────────
    private func demoLissajous() {
        var px = -1, py = -1
        for i in 0...600 {
            let tt=Double(i)/600*2*Double.pi
            let x=512+Int(460*sin(3*tt+angle)); let y=512+Int(460*sin(2*tt))
            if px >= 0 { vl(px,py,x,y,0.85) }
            px=x; py=y
        }
        border(0.4); vtext("LISSAJOUS",300,60,16,0.5)
    }

    // ── TEXT ──────────────────────────────────────────────────
    private let TEXT_LINES = ["IMLAC PDS-1","1970 MIT AI LAB","PROGRAMMED","DISPLAY SYSTEM",
        "16-BIT CPU","4096 WORDS RAM","VECTOR CRT","1024 X 1024","LIGHT PEN","SPACEWAR 1974",
        "ARPANET NODE","LOGO LANGUAGE"]
    private func demoText() {
        for (i,line) in TEXT_LINES.enumerated() {
            let y=Int((780.0-Double(i)*140+textScroll).truncatingRemainder(dividingBy:1100))-100
            if y > -80 && y < 1050 { vtext(line,80,y,20,0.9) }
        }
        textScroll += 1.5
        if textScroll > Double(TEXT_LINES.count)*145 { textScroll=0 }
        border(0.3)
    }

    // ── BOUNCE ────────────────────────────────────────────────
    private func demoBounce() {
        ballX+=ballVx; ballY+=ballVy
        if ballX<60||ballX>964 { ballVx *= -1; ballX=max(60,min(964,ballX)) }
        if ballY<60||ballY>964 { ballVy *= -1; ballY=max(60,min(964,ballY)) }
        if trailN<15 { trailX[trailN]=ballX;trailY[trailN]=ballY;trailN+=1 }
        else {
            trailX = Array(trailX[1...14]) + [ballX] + [0]
            trailY = Array(trailY[1...14]) + [ballY] + [0]
        }
        for i in 0..<trailN-1 { vp(Int(trailX[i]),Int(trailY[i]),Float(i+1)/Float(trailN)*0.4) }
        circle(Int(ballX),Int(ballY),35,16,1.0)
        vl(Int(ballX)-50,Int(ballY),Int(ballX)+50,Int(ballY),0.25)
        vl(Int(ballX),Int(ballY)-50,Int(ballX),Int(ballY)+50,0.25)
        [60,964].forEach { x in [60,964].forEach { y in circle(x,y,20,8,0.4) } }
        rect(20,20,984,984,0.6); vtext("BOUNCE",350,40,14,0.6)
    }

    // ── MAZE ──────────────────────────────────────────────────
    private let CDX=[0,1,0,-1],CDY=[1,0,-1,0],COPP=[2,3,0,1]
    private func demoMaze() {
        if !mazeReady { initMaze() }
        let cw=(1024-60)/MW, ch=(1024-60)/MH, ox=30, oy=30
        for y in 0..<MH { for x in 0..<MW {
            let cell=mazeGrid[y][x],px=ox+x*cw,py=oy+y*ch
            if (cell&1) != 0 { vl(px,py+ch,px+cw,py+ch,0.85) }
            if (cell&2) != 0 { vl(px+cw,py,px+cw,py+ch,0.85) }
            if (cell&4) != 0 { vl(px,py,px+cw,py,0.85) }
            if (cell&8) != 0 { vl(px,py,px,py+ch,0.85) }
        }}
        circle(ox+cw/2,oy+ch/2,12,8,0.6)
        circle(ox+(MW-1)*cw+cw/2,oy+(MH-1)*ch+ch/2,12,8,1.0)
        vtext("MAZE",370,965,14,0.55)
    }
    private func initMaze() {
        mazeGrid = [[Int]](repeating:[Int](repeating:0xF,count:MW),count:MH)
        var vis = [[Bool]](repeating:[Bool](repeating:false,count:MW),count:MH)
        carveMaze(0,0,&vis); mazeReady=true
    }
    private func carveMaze(_ x:Int,_ y:Int,_ vis:inout [[Bool]]) {
        vis[y][x]=true
        let dirs=[0,1,2,3].shuffled()
        for d in dirs {
            let nx=x+CDX[d],ny=y+CDY[d]
            if nx<0||nx>=MW||ny<0||ny>=MH||vis[ny][nx] { continue }
            mazeGrid[y][x]  &= ~(1<<d)
            mazeGrid[ny][nx] &= ~(1<<COPP[d])
            carveMaze(nx,ny,&vis)
        }
    }

    // ── SPACEWAR ──────────────────────────────────────────────
    private func demoSpacewar() {
        if !swInit { blife = [Int](repeating:0,count:4); swInit=true }
        sw1a+=0.025; sw2a+=0.025
        let (dx1,dy1)=(512-sw1x,512-sw1y); let d1=sqrt(dx1*dx1+dy1*dy1)
        if d1>1{sw1vx+=dx1/d1*0.15;sw1vy+=dy1/d1*0.15}
        let (dx2,dy2)=(512-sw2x,512-sw2y); let d2=sqrt(dx2*dx2+dy2*dy2)
        if d2>1{sw2vx+=dx2/d2*0.15;sw2vy+=dy2/d2*0.15}
        sw1x+=sw1vx;sw1y+=sw1vy; sw2x+=sw2vx;sw2y+=sw2vy
        sw1x=sw1x.truncatingRemainder(dividingBy:1024); if sw1x<0{sw1x+=1024}
        sw1y=sw1y.truncatingRemainder(dividingBy:1024); if sw1y<0{sw1y+=1024}
        sw2x=sw2x.truncatingRemainder(dividingBy:1024); if sw2x<0{sw2x+=1024}
        sw2y=sw2y.truncatingRemainder(dividingBy:1024); if sw2y<0{sw2y+=1024}
        if frame%40==0 { fireSW(sw1x,sw1y,sw1a,sw1vx,sw1vy) }
        if frame%53==0 { fireSW(sw2x,sw2y,sw2a,sw2vx,sw2vy) }
        for i in 0..<4 {
            if blife[i]<=0 { continue }; blife[i]-=1
            bx[i]+=bvx[i];by[i]+=bvy[i]; vp(Int(bx[i]),Int(by[i]),1.0)
        }
        circle(512,512,25,12,0.6); circle(512,512,8,8,1.0)
        drawShip(Int(sw1x),Int(sw1y),sw1a,1.0)
        drawShip(Int(sw2x),Int(sw2y),sw2a+Double.pi,0.85)
        vtext("SPACEWAR",310,960,14,0.5); rect(20,20,984,984,0.3)
    }
    private func fireSW(_ x:Double,_ y:Double,_ a:Double,_ vx:Double,_ vy:Double){
        for i in 0..<4 {
            if blife[i]>0{continue}
            bx[i]=x;by[i]=y;bvx[i]=cos(a)*9+vx;bvy[i]=sin(a)*9+vy;blife[i]=80;break
        }
    }
    private func drawShip(_ cx:Int,_ cy:Int,_ a:Double,_ b:Float){
        let (r1,r2,da)=(30.0,20.0,2.5)
        let p1x=cx+Int(cos(a)*r1),p1y=cy+Int(sin(a)*r1)
        let p2x=cx+Int(cos(a+da)*r2),p2y=cy+Int(sin(a+da)*r2)
        let p3x=cx+Int(cos(a-da)*r2),p3y=cy+Int(sin(a-da)*r2)
        vl(p1x,p1y,p2x,p2y,b);vl(p2x,p2y,p3x,p3y,b);vl(p3x,p3y,p1x,p1y,b)
    }

    // ── SCOPE ─────────────────────────────────────────────────
    private func demoScope() {
        let freqs=[(1.0,1.0),(2.0,3.0),(3.0,4.0),(5.0,4.0)]
        let brs:[Float]=[0.9,0.7,0.55,0.4]
        for (f,(fa,fb)) in freqs.enumerated() {
            let ph=angle*Double(f+1)*0.3; var px = -1, py = -1
            for i in 0...400 {
                let tt=Double(i)/400*2*Double.pi
                let x=512+Int(440*sin(fa*tt+ph)); let y=512+Int(440*sin(fb*tt))
                if px >= 0 { vl(px,py,x,y,brs[f]) }; px=x; py=y
            }
        }
        border(0.4); vtext("SCOPE",380,60,14,0.5)
    }

    // ── MAZE WAR ──────────────────────────────────────────────
    private func demoMazeWar() {
        if mazeWarGame == nil { mazeWarGame = MazeWarGame(machine: M) }
        mazeWarGame!.tick()
        mazeWarGame!.draw()
    }
}
