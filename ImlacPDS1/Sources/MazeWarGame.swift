// MazeWarGame.swift — Maze War (1974) for Imlac PDS-1 iOS
// Ported from MazeWarGame.java

import Foundation

final class MazeWarGame {

    // ── Screen constants ──────────────────────────────────────
    private let VX0=40,VX1=780,VY0=80,VY1=940
    private var VCX: Int { (VX0+VX1)/2 }
    private var VCY: Int { (VY0+VY1)/2 }
    private var VW:  Int { VX1-VX0 }
    private var VH:  Int { VY1-VY0 }

    // ── Maze ─────────────────────────────────────────────────
    private let MZ = 16
    private var maze = [Int](repeating: 0xF, count: 256)
    private let DX  = [0,1,0,-1]
    private let DY  = [1,0,-1,0]
    private let OPP = [2,3,0,1]

    // ── Player ────────────────────────────────────────────────
    private var px=1,py=1,pdir=0,hp=3,score=0,level=1
    private var moveCd=0,turnCd=0,fireCd=0,hitFlash=0,killFlash=0

    // ── Network peer ─────────────────────────────────────────
    private var netX=14,netY=14,netDir=2,netHp=3,netScore=0
    private var netAlive=true,netHitFlash=0

    // ── Network ───────────────────────────────────────────────
    var net: NetSession?
    private var multiMode=false,netSendCd=0

    // ── AI ───────────────────────────────────────────────────
    private class Enemy {
        var x,y,dir: Int; var think=30,fireCd=80,alive=true
        init(_ x:Int,_ y:Int,_ dir:Int){self.x=x;self.y=y;self.dir=dir}
    }
    private var aiEnemies=[Enemy]()

    // ── Bullets ───────────────────────────────────────────────
    private class Bullet {
        var x,y: Double; var dir,life: Int; var fromPlayer,alive: Bool
        init(_ x:Double,_ y:Double,_ dir:Int,_ fp:Bool){self.x=x;self.y=y;self.dir=dir;self.life=55;self.fromPlayer=fp;self.alive=true}
    }
    private var bullets=[Bullet]()

    // ── State ─────────────────────────────────────────────────
    private enum State { case title,lobby,play,dead }
    private var state=State.title
    private var frame=0
    private var msg="",msgT=0,lobbyStatus=""

    // ── Input ─────────────────────────────────────────────────
    var iUp=false,iDown=false,iLeft=false,iRight=false,iFire=false
    private var pUp=false,pDown=false,pLeft=false,pRight=false,pFire=false

    // ── Machine ───────────────────────────────────────────────
    private let M: Machine

    init(machine: Machine) { M = machine }

    // ─────────────────────────────────────────────────────────
    //  PUBLIC API
    // ─────────────────────────────────────────────────────────
    func tick() {
        let k = M.keyboard & 0x7F
        iUp    = iUp    || (k == Int(UInt8(ascii:"W")))
        iDown  = iDown  || (k == Int(UInt8(ascii:"S")))
        iLeft  = iLeft  || (k == Int(UInt8(ascii:"A")))
        iRight = iRight || (k == Int(UInt8(ascii:"D")))
        iFire  = iFire  || (k == 32 || k == Int(UInt8(ascii:"F")))

        switch state {
        case .title: tickTitle()
        case .lobby: break
        case .play:  tickPlay()
        case .dead:  tickDead()
        }
        pUp=iUp;pDown=iDown;pLeft=iLeft;pRight=iRight;pFire=iFire
        iUp=false;iDown=false;iLeft=false;iRight=false;iFire=false
        frame += 1
    }

    func draw() {
        switch state {
        case .title: drawTitle()
        case .lobby: drawLobby()
        case .play:  drawPlay()
        case .dead:  drawDead()
        }
    }

    func startSinglePlayer() { multiMode=false; startGame(seed: UInt64.random(in: 0...UInt64.max)) }

    func hostMulti(_ n: NetSession) { net=n; multiMode=true; n.eventListener=self; state = .lobby; lobbyStatus="HOSTING... WAIT FOR GUEST" }
    func joinMulti(_ n: NetSession) { net=n; multiMode=true; n.eventListener=self; state = .lobby; lobbyStatus="SEARCHING FOR HOST..." }
    func stopNet() { net?.stop(); net=nil; multiMode=false; state = .title }

    // ─────────────────────────────────────────────────────────
    //  TITLE / LOBBY / DEAD
    // ─────────────────────────────────────────────────────────
    private func tickTitle() {
        let anyNew=(iUp||iDown||iLeft||iRight||iFire)&&!(pUp||pDown||pLeft||pRight||pFire)
        if anyNew { startGame(seed: UInt64.random(in: 0...UInt64.max)) }
    }
    private func drawTitle() {
        let ex=VCX+100,ey=VCY,rx=90,ry=55
        circle(ex,ey,rx,ry,20,0.9)
        circle(ex,ey,rx/3,Int(Float(ry)*0.8),12,1.0)
        for i in -3...3 { if i==0{continue}; vl(ex+i*28,ey+ry+2,ex+i*28+i*5,ey+ry+28,0.55) }
        txt("MAZE WAR",VX0+10,VCY+60,18,1.0)
        txt("IMLAC PDS-1  1974",VX0+10,VCY+10,10,0.5)
        txt("SINGLE  -  ANY BUTTON",VX0+10,VCY-40,8,0.4)
        txt("MULTI   -  HOST OR JOIN",VX0+10,VCY-70,8,0.35)
        if (frame/20)%2==0 { txt("PRESS ANY BUTTON",VX0+10,VCY-110,9,0.8) }
    }
    private func drawLobby() {
        let spin=["|","/","-","\\"]
        txt("MAZE WAR  ONLINE",VCX-200,VCY+80,13,0.9)
        txt(lobbyStatus,VCX-lobbyStatus.count*11,VCY+10,11,0.7)
        txt(spin[(frame/8)%4],VCX-10,VCY-50,16,0.6)
        txt("CANCEL  -  DISC BUTTON",VCX-200,VCY-110,8,0.25)
    }
    private func drawDead() {
        txt("GAME OVER",VCX-190,VCY+80,18,0.9)
        txt("SCORE \(score)",VCX-160,VCY+10,13,0.7)
        if (frame/20)%2==0 { txt("PRESS ANY BUTTON",VCX-215,VCY-70,11,0.85) }
    }
    private func tickDead() {
        let anyNew=(iUp||iDown||iLeft||iRight||iFire)&&!(pUp||pDown||pLeft||pRight||pFire)
        if anyNew { multiMode=false; state = .title }
    }

    // ─────────────────────────────────────────────────────────
    //  MAZE GENERATION
    // ─────────────────────────────────────────────────────────
    private func startGame(seed: UInt64) {
        genMaze(seed: Int(seed & 0x7FFFFFFF))
        px=1;py=1;pdir=0;hp=3;score=0;level=1
        moveCd=0;turnCd=0;fireCd=0;hitFlash=0;killFlash=0
        bullets.removeAll(); aiEnemies.removeAll()
        if !multiMode { spawnAI(n: level+1) }
        state = .play
    }
    private func genMaze(seed: Int) {
        maze = [Int](repeating: 0xF, count: MZ*MZ)
        var rng = seed
        var vis = [Bool](repeating: false, count: MZ*MZ)
        carve(1,1,&vis,&rng)
    }
    private func nextRnd(_ rng: inout Int) -> Int { rng = rng &* 1664525 &+ 1013904223; return (rng>>16)&0x7FFF }
    private func carve(_ x: Int,_ y: Int,_ vis: inout [Bool],_ rng: inout Int) {
        vis[y*MZ+x]=true
        var d=[0,1,2,3]; for i in stride(from:3,through:1,by:-1){let j=nextRnd(&rng)%(i+1);d.swapAt(i,j)}
        for dd in d {
            let nx=x+DX[dd],ny=y+DY[dd]
            if nx<1||nx>=MZ-1||ny<1||ny>=MZ-1||vis[ny*MZ+nx] { continue }
            maze[y*MZ+x]   &= ~(1<<dd)
            maze[ny*MZ+nx] &= ~(1<<OPP[dd])
            carve(nx,ny,&vis,&rng)
        }
    }
    private func wall(_ x:Int,_ y:Int,_ dir:Int)->Bool {
        if x<0||x>=MZ||y<0||y>=MZ { return true }
        return (maze[y*MZ+x] & (1<<dir)) != 0
    }
    private func solid(_ x:Int,_ y:Int)->Bool {
        if x<0||x>=MZ||y<0||y>=MZ { return true }
        return maze[y*MZ+x]==0xF
    }
    private func spawnAI(n: Int) {
        for _ in 0..<n {
            var ex=0,ey=0
            for _ in 0..<200 {
                ex=2+Int.random(in:0..<MZ-4); ey=2+Int.random(in:0..<MZ-4)
                if !solid(ex,ey)&&abs(ex-px)+abs(ey-py)>3 { break }
            }
            aiEnemies.append(Enemy(ex,ey,Int.random(in:0..<4)))
        }
    }

    // ─────────────────────────────────────────────────────────
    //  PLAY TICK
    // ─────────────────────────────────────────────────────────
    private func tickPlay() {
        if moveCd>0{moveCd-=1}; if turnCd>0{turnCd-=1}
        if fireCd>0{fireCd-=1}; if hitFlash>0{hitFlash-=1}
        if killFlash>0{killFlash-=1}; if msgT>0{msgT-=1}; if netHitFlash>0{netHitFlash-=1}

        if turnCd==0 {
            if iLeft&&!pLeft  { pdir=(pdir+3)%4; turnCd=8 }
            if iRight&&!pRight { pdir=(pdir+1)%4; turnCd=8 }
        }
        if moveCd==0 {
            if iUp&&!wall(px,py,pdir)    { px+=DX[pdir];py+=DY[pdir];moveCd=12 }
            else if iDown&&!wall(px,py,(pdir+2)%4) { px-=DX[pdir];py-=DY[pdir];moveCd=12 }
        }
        if iFire&&!pFire&&fireCd==0 {
            bullets.append(Bullet(Double(px)+0.5,Double(py)+0.5,pdir,true))
            fireCd=20; net?.sendBullet(pdir)
        }
        tickBullets()
        if !multiMode { tickAI(); checkWin() } else { if !netAlive&&netHitFlash<=0{netAlive=true} }
        if multiMode, let n=net, n.isConnected() {
            if netSendCd<=0 { n.sendMazeState(px,py,pdir,hp,score); netSendCd=3 } else { netSendCd-=1 }
        }
    }
    private func tickBullets() {
        for b in bullets {
            guard b.alive else { continue }
            b.life-=1; if b.life<=0{b.alive=false;continue}
            b.x+=Double(DX[b.dir])*0.2; b.y+=Double(DY[b.dir])*0.2
            if solid(Int(b.x),Int(b.y)){b.alive=false;continue}
            if b.fromPlayer {
                for e in aiEnemies {
                    guard e.alive else { continue }
                    if abs(b.x-(Double(e.x)+0.5))<0.6&&abs(b.y-(Double(e.y)+0.5))<0.6 {
                        e.alive=false;b.alive=false;score+=1;killFlash=12;msg="KILL";msgT=30;break
                    }
                }
                if multiMode&&netAlive&&abs(b.x-(Double(netX)+0.5))<0.6&&abs(b.y-(Double(netY)+0.5))<0.6 {
                    b.alive=false;netAlive=false;netHitFlash=20;score+=1
                    net?.sendKill(); msg="YOU KILLED OPPONENT!";msgT=50
                }
            } else {
                if abs(b.x-(Double(px)+0.5))<0.55&&abs(b.y-(Double(py)+0.5))<0.55 {
                    b.alive=false;hp-=1;hitFlash=18
                    msg=hp>0 ? "HIT! HP:\(hp)" : "YOU DIED"; msgT=45
                    if hp<=0 { state = .dead }
                }
            }
        }
        bullets.removeAll { !$0.alive }
    }
    private func tickAI() {
        for e in aiEnemies {
            guard e.alive else { continue }
            e.think-=1; e.fireCd-=1
            if e.think<=0 {
                e.think=15+Int.random(in:0..<25)
                let dx=px-e.x,dy=py-e.y; var want = -1
                if abs(dx)>abs(dy) { want=dx>0 ? 1:3 } else if dy != 0 { want=dy>0 ? 0:2 }
                if Double.random(in:0..<1)<0.6&&want>=0&&!wall(e.x,e.y,want) {
                    e.dir=want;e.x+=DX[want];e.y+=DY[want]
                } else {
                    let ds=[0,1,2,3].shuffled()
                    for dd in ds { if !wall(e.x,e.y,dd){e.dir=dd;e.x+=DX[dd];e.y+=DY[dd];break} }
                }
            }
            if e.fireCd<=0 {
                var sh=false
                if e.dir==0&&e.x==px&&py>e.y { sh=los(e.x,e.y,px,py) }
                if e.dir==2&&e.x==px&&py<e.y { sh=los(px,py,e.x,e.y) }
                if e.dir==1&&e.y==py&&px>e.x { sh=los(e.x,e.y,px,py) }
                if e.dir==3&&e.y==py&&px<e.x { sh=los(px,py,e.x,e.y) }
                if sh {
                    bullets.append(Bullet(Double(e.x)+0.5,Double(e.y)+0.5,e.dir,false))
                    e.fireCd=60+Int.random(in:0..<60)
                }
            }
        }
    }
    private func los(_ x1:Int,_ y1:Int,_ x2:Int,_ y2:Int)->Bool {
        if x1==x2 { for y in y1..<y2 { if wall(x1,y,0){return false} } }
        else       { for x in x1..<x2 { if wall(x,y1,1){return false} } }
        return true
    }
    private func checkWin() {
        if aiEnemies.allSatisfy({!$0.alive}) {
            level+=1; msg="LEVEL \(level)!"; msgT=60
            genMaze(seed: Int.random(in:0..<Int.max)); px=1;py=1;pdir=0
            bullets.removeAll(); aiEnemies.removeAll(); spawnAI(n: min(level+1,7))
        }
    }

    // ─────────────────────────────────────────────────────────
    //  DRAW
    // ─────────────────────────────────────────────────────────
    private func drawPlay() {
        vl(VX0,VY0,VX1,VY0,0.5);vl(VX1,VY0,VX1,VY1,0.5)
        vl(VX1,VY1,VX0,VY1,0.5);vl(VX0,VY1,VX0,VY0,0.5)
        if hitFlash>0 { let f=Float(hitFlash)/18; vl(VX0,VY0,VX1,VY0,f);vl(VX1,VY0,VX1,VY1,f);vl(VX1,VY1,VX0,VY1,f);vl(VX0,VY1,VX0,VY0,f) }
        draw3D(); drawEnemiesInView(); drawHUD()
        if msgT>0 { txt(msg,VCX-msg.count*11,VCY-60,13,min(1,Float(msgT)/20)) }
        if multiMode { txt(net?.isConnected()==true ? "NET OK":"NET...",VX0+8,VY0-22,7,0.4) }
    }
    private func draw3D() {
        let MAX=10; var depth=0,wx=px,wy=py
        for d in 1...MAX {
            if wall(wx,wy,pdir){depth=d-1;break}
            wx+=DX[pdir];wy+=DY[pdir]
            if solid(wx,wy){depth=d-1;break}
            depth=d
        }
        depth=max(0,depth)
        var lt=[Int](repeating:0,count:MAX+2),rt=[Int](repeating:0,count:MAX+2)
        var tp=[Int](repeating:0,count:MAX+2),bt=[Int](repeating:0,count:MAX+2)
        for d in 0...depth+1 {
            let sc=Float(1.4)/Float(d+1)
            lt[d]=clampX(VCX-Int(Float(VW)/2*sc)); rt[d]=clampX(VCX+Int(Float(VW)/2*sc))
            tp[d]=clampY(VCY-Int(Float(VH)/2*sc)); bt[d]=clampY(VCY+Int(Float(VH)/2*sc))
        }
        var cx2=px,cy2=py
        for d in 0...depth {
            let bright=max(Float(0.2),1-Float(d)*0.1)
            let hl = !wall(cx2,cy2,(pdir+3)%4), hr = !wall(cx2,cy2,(pdir+1)%4)
            let hf = !wall(cx2,cy2,pdir) && d < depth
            if !hl {vl(lt[d],tp[d],lt[d+1],tp[d+1],bright*0.8);vl(lt[d],bt[d],lt[d+1],bt[d+1],bright*0.8);vl(lt[d+1],tp[d+1],lt[d+1],bt[d+1],bright*0.6)}
            else   {vl(lt[d],tp[d],lt[d],bt[d],bright*0.5)}
            if !hr {vl(rt[d],tp[d],rt[d+1],tp[d+1],bright*0.8);vl(rt[d],bt[d],rt[d+1],bt[d+1],bright*0.8);vl(rt[d+1],tp[d+1],rt[d+1],bt[d+1],bright*0.6)}
            else   {vl(rt[d],tp[d],rt[d],bt[d],bright*0.5)}
            if !hf {vl(lt[d+1],tp[d+1],rt[d+1],tp[d+1],bright);vl(lt[d+1],bt[d+1],rt[d+1],bt[d+1],bright)
                    vl(lt[d+1],tp[d+1],lt[d+1],bt[d+1],bright*0.8);vl(rt[d+1],tp[d+1],rt[d+1],bt[d+1],bright*0.8);break}
            cx2+=DX[pdir];cy2+=DY[pdir]
        }
        vl(VX0,VY0,lt[0],tp[0],0.35);vl(VX1,VY0,rt[0],tp[0],0.35)
        vl(VX0,VY1,lt[0],bt[0],0.35);vl(VX1,VY1,rt[0],bt[0],0.35)
        vl(VCX-12,VCY,VCX-4,VCY,0.6);vl(VCX+4,VCY,VCX+12,VCY,0.6)
        vl(VCX,VCY-12,VCX,VCY-4,0.6);vl(VCX,VCY+4,VCX,VCY+12,0.6)
    }
    private func drawEnemiesInView() {
        for e in aiEnemies { if e.alive { drawEntityIfVisible(e.x,e.y,false) } }
        if multiMode&&netAlive { drawEntityIfVisible(netX,netY,true) }
    }
    private func drawEntityIfVisible(_ ex:Int,_ ey:Int,_ isNet:Bool) {
        var relDir = -1
        if pdir==0&&ex==px&&ey>py { relDir=0 }
        if pdir==1&&ey==py&&ex>px { relDir=1 }
        if pdir==2&&ex==px&&ey<py { relDir=2 }
        if pdir==3&&ey==py&&ex<px { relDir=3 }
        guard relDir==pdir else { return }
        let dist=pdir==0||pdir==2 ? abs(ey-py) : abs(ex-px)
        guard dist>=1&&dist<=8 else { return }
        for d in 0..<dist { if wall(px+DX[pdir]*d,py+DY[pdir]*d,pdir){return} }
        let sc=Float(1.4)/Float(Float(dist)+0.5)
        let sz=max(8,min(Int(Float(VH)*0.25*sc),120))
        var b=max(Float(0.3),0.9-Float(dist)*0.08)
        if isNet&&netHitFlash>0 { b=1.0 }
        drawEye(VCX,VCY,sz,b)
    }
    private func drawEye(_ cx:Int,_ cy:Int,_ sz:Int,_ b:Float) {
        let rx=sz,ry=Int(Float(sz)*0.55)
        circle(cx,cy,rx,ry,16,b)
        circle(cx,cy,rx/3,Int(Float(ry)*0.7),10,b*1.1)
        vl(cx-rx,cy,cx+rx,cy,b*0.3)
        if sz>25 { for i in -2...2 { if i==0{continue}; vl(cx+i*(rx/3),cy+ry+2,cx+i*(rx/3)+i*4,cy+ry+20,b*0.6) } }
    }
    private func drawHUD() {
        for i in 0..<3 { let hx=VX0+20+i*28; circle(hx,VY1+25,9,9,8,i<hp ? 0.9:0.2) }
        txt(String(format:"%04d",score),VX1-120,VY1+18,9,0.7)
        txt(["N","E","S","W"][pdir],VX1+15,VY1+18,10,0.6)
        txt("LV\(level)",VCX-32,VY0-22,9,0.35)
        if fireCd>0 { vl(VCX-40,VY1+52,VCX-40+Int(Float(fireCd)/20*80),VY1+52,0.4) }
        if multiMode { txt("OPP:\(String(format:"%04d",netScore))",VX0+8,VY1+18,9,0.5) }
    }

    // ─────────────────────────────────────────────────────────
    //  DRAW HELPERS
    // ─────────────────────────────────────────────────────────
    private func vl(_ x1:Int,_ y1:Int,_ x2:Int,_ y2:Int,_ b:Float) { M.dlLine(x1,y1,x2,y2,b) }
    private func clampX(_ x:Int)->Int { max(VX0,min(VX1,x)) }
    private func clampY(_ y:Int)->Int { max(VY0,min(VY1,y)) }

    private func circle(_ cx:Int,_ cy:Int,_ rx:Int,_ ry:Int,_ segs:Int,_ b:Float) {
        var ppx=cx+rx,ppy=cy
        for i in 1...segs {
            let a=Double(i)/Double(segs)*2*Double.pi
            let nx=cx+Int(cos(a)*Double(rx)),ny=cy+Int(sin(a)*Double(ry))
            vl(ppx,ppy,nx,ny,b); ppx=nx;ppy=ny
        }
    }

    // ── Vector font ───────────────────────────────────────────
    private let F: [[[Float]]] = [
        [[0,0,2,4],[2,4,4,0],[1,2,3,2]],[[0,0,0,4],[0,4,2,4],[0,2,2,2],[0,0,2,0],[2,4,3,3],[3,3,2,2],[2,2,3,1],[3,1,2,0]],
        [[3,4,0,4],[0,4,0,0],[0,0,3,0]],[[0,0,0,4],[0,4,2,4],[2,4,4,2],[4,2,2,0],[2,0,0,0]],
        [[0,0,0,4],[0,4,4,4],[0,2,3,2],[0,0,4,0]],[[0,0,0,4],[0,4,4,4],[0,2,3,2]],
        [[3,4,0,4],[0,4,0,0],[0,0,4,0],[4,0,4,2],[4,2,2,2]],[[0,0,0,4],[4,0,4,4],[0,2,4,2]],
        [[1,0,3,0],[1,4,3,4],[2,0,2,4]],[[1,4,3,4],[3,4,3,0],[3,0,0,0]],
        [[0,0,0,4],[0,2,4,4],[0,2,4,0]],[[0,4,0,0],[0,0,4,0]],
        [[0,0,0,4],[0,4,2,2],[2,2,4,4],[4,4,4,0]],[[0,0,0,4],[0,4,4,0],[4,0,4,4]],
        [[0,0,4,0],[4,0,4,4],[4,4,0,4],[0,4,0,0]],[[0,0,0,4],[0,4,3,4],[3,4,4,3],[4,3,3,2],[3,2,0,2]],
        [[0,0,4,0],[4,0,4,4],[4,4,0,4],[0,4,0,0],[2,2,4,0]],[[0,0,0,4],[0,4,3,4],[3,4,4,3],[4,3,3,2],[3,2,0,2],[2,2,4,0]],
        [[4,4,0,4],[0,4,0,2],[0,2,4,2],[4,2,4,0],[4,0,0,0]],[[0,4,4,4],[2,4,2,0]],
        [[0,4,0,0],[0,0,4,0],[4,0,4,4]],[[0,4,2,0],[2,0,4,4]],
        [[0,4,1,0],[1,0,2,2],[2,2,3,0],[3,0,4,4]],[[0,0,4,4],[4,0,0,4]],
        [[0,4,2,2],[4,4,2,2],[2,2,2,0]],[[0,4,4,4],[4,4,0,0],[0,0,4,0]],
        [[0,0,4,0],[4,0,4,4],[4,4,0,4],[0,4,0,0],[0,0,4,4]],[[1,4,2,4],[2,4,2,0],[1,0,3,0]],
        [[0,4,4,4],[4,4,4,3],[4,3,0,1],[0,1,0,0],[0,0,4,0]],[[0,4,4,4],[4,4,4,0],[0,0,4,0],[0,2,4,2]],
        [[0,4,0,2],[0,2,4,2],[4,4,4,0]],[[4,4,0,4],[0,4,0,2],[0,2,4,2],[4,2,4,0],[4,0,0,0]],
        [[4,4,0,4],[0,4,0,0],[0,0,4,0],[4,0,4,2],[4,2,0,2]],[[0,4,4,4],[4,4,2,0]],
        [[0,0,4,0],[4,0,4,4],[4,4,0,4],[0,4,0,0],[0,2,4,2]],[[4,0,4,4],[4,4,0,4],[0,4,0,2],[0,2,4,2]],
        []
    ]
    private let CH = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 "

    private func ch(_ c: Character, _ ox: Int, _ oy: Int, _ sc: Float, _ b: Float) {
        let uc = c.uppercased().first ?? c
        guard let idx = CH.firstIndex(of: uc) else { return }
        let i = CH.distance(from: CH.startIndex, to: idx)
        guard i < F.count else { return }
        for s in F[i] { vl(ox+Int(s[0]*sc),oy+Int(s[1]*sc),ox+Int(s[2]*sc),oy+Int(s[3]*sc),b) }
    }
    private func txt(_ s: String, _ ox: Int, _ oy: Int, _ sc: Float, _ b: Float) {
        var x=ox; for c in s.uppercased() { ch(c,x,oy,sc,b); x+=Int(sc*5.5) }
    }
}

// ─────────────────────────────────────────────────────────
//  NetSession.EventListener conformance
// ─────────────────────────────────────────────────────────
extension MazeWarGame: NetSessionEventListener {
    func onConnected(asHost: Bool, seed: Int) {
        genMaze(seed: seed)
        if asHost { px=1;py=1;pdir=0;netX=14;netY=14;netDir=2 }
        else       { px=14;py=14;pdir=2;netX=1;netY=1;netDir=0 }
        hp=3;score=0;netHp=3;netScore=0;netAlive=true
        bullets.removeAll(); state = .play; msg="CONNECTED! FIGHT!"; msgT=50
    }
    func onPeerMazeState(_ x:Int,_ y:Int,_ dir:Int,_ hp2:Int,_ sc:Int) {
        netX=x;netY=y;netDir=dir;netHp=hp2;netScore=sc;netAlive=(hp2>0)
    }
    func onPeerSync(_ demoIdx: Int, _ keyboard: Int) {}
    func onPeerBullet(_ dir: Int) {
        bullets.append(Bullet(Double(netX)+0.5,Double(netY)+0.5,dir,false))
    }
    func onPeerKilled() { netAlive=false;netHitFlash=20;msg="OPPONENT KILLED!";msgT=40 }
    func onDisconnected() {
        msg="DISCONNECTED";msgT=80;multiMode=false
        state = (state == .play) ? .dead : .title
    }
}
