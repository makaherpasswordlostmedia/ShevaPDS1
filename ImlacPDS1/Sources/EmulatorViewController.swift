// EmulatorViewController.swift — Main iOS UI for Imlac PDS-1 Emulator
// Replaces EmulatorActivity.java

import UIKit

final class EmulatorViewController: UIViewController {

    // ── Core ──────────────────────────────────────────────────
    let machine = Machine()
    var demos:   Demos!
    var crtView: CrtView!

    // ── Net ───────────────────────────────────────────────────
    var netSession: NetSession?
    var chatLines  = [String]()
    var lastPeerDemo = -1
    var syncSendCd   = 0

    // ── MP thread ─────────────────────────────────────────────
    private var mpThread: Thread?
    private var mpRunning = false
    private let ctrl = [Bool](repeating: false, count: 6)  // fwd,back,left,right,fire,b
    private var ctrlArr = [Bool](repeating: false, count: 6)

    // ── UI ────────────────────────────────────────────────────
    // Labels
    var tvFps: UILabel!
    var tvPc: UILabel!
    var tvAc: UILabel!
    var tvNetStatus: UILabel!
    var tvChatLog:   UILabel!
    // Panels
    var panelChat: UIView!
    var panelController: UIView!
    var panelKeyboard:   UIView!
    var keyboardVisible  = false
    // Inputs
    var etChat: UITextField!
    // Buttons (dpad)
    var btnUp, btnDown, btnLeft, btnRight, btnFire: UIButton?

    // ── Lifecycle ─────────────────────────────────────────────
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        demos = Demos(machine)
        buildUI()
        startMP()
        crtView.machine = machine
        crtView.demos   = demos
        crtView.start()
        startFpsTicker()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        crtView.stop(); mpRunning=false
    }

    override var prefersStatusBarHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }

    // ─────────────────────────────────────────────────────────
    //  BUILD UI
    // ─────────────────────────────────────────────────────────
    private func buildUI() {
        let W = UIScreen.main.bounds.width
        let H = UIScreen.main.bounds.height

        // CRT display (left ~75%)
        let crtW = W * 0.72
        crtView = CrtView(frame: CGRect(x:0, y:0, width:crtW, height:H))
        crtView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(crtView)

        // Right panel
        let panelX = crtW
        let panelW = W - crtW
        let panel = UIScrollView(frame: CGRect(x:panelX, y:0, width:panelW, height:H))
        panel.backgroundColor = UIColor(white:0.04, alpha:1)
        panel.showsVerticalScrollIndicator = false
        view.addSubview(panel)

        var y: CGFloat = 8

        // FPS + registers
        tvFps = monoLabel("31fps", size:8, color:.green)
        panel.addSubview(tvFps); tvFps.frame=CGRect(x:4,y:y,width:panelW-8,height:12); y+=14
        tvPc = monoLabel("PC:0000  AC:0000", size:7, color:UIColor(white:0.6,alpha:1))
        panel.addSubview(tvPc); tvPc.frame=CGRect(x:4,y:y,width:panelW-8,height:10); y+=12
        tvAc = monoLabel("IR:0000  L:0", size:7, color:UIColor(white:0.5,alpha:1))
        panel.addSubview(tvAc); tvAc.frame=CGRect(x:4,y:y,width:panelW-8,height:10); y+=14

        // Control buttons row
        y = addButtonRow(panel, y:y, panelW:panelW, titles:["PWR","RST","RUN","HLT","STP"],
            colors:[.systemGreen,.gray,.systemBlue,.systemRed,.gray],
            actions:[#selector(onPwr),#selector(onRst),#selector(onRun),#selector(onHlt),#selector(onStp)])

        // Demo buttons
        y = addButtonRow(panel, y:y, panelW:panelW,
            titles:["STAR","WAVE","LISS","TEXT","BNCE"],
            colors:[.systemCyan,.systemCyan,.systemCyan,.systemCyan,.systemCyan],
            actions:[#selector(onStar),#selector(onScope),#selector(onLiss),#selector(onText),#selector(onBounce)])
        y = addButtonRow(panel, y:y, panelW:panelW,
            titles:["MAZE","WARS","SPWR","MAZE WAR","GAMES"],
            colors:[.systemCyan,.systemCyan,.systemCyan,UIColor(red:0.1,green:0.8,blue:0.1,alpha:1),.systemBlue],
            actions:[#selector(onMaze),#selector(onMazeWar),#selector(onSpacewar),#selector(onMazeWar),#selector(onGames)])

        // Multiplayer
        y = addButtonRow(panel, y:y, panelW:panelW,
            titles:["HOST","JOIN","DISC"],
            colors:[UIColor(red:0.8,green:0.8,blue:0,alpha:1),
                    UIColor(red:0,green:0.8,blue:0.8,alpha:1),
                    UIColor(red:0.8,green:0.2,blue:0.2,alpha:1)],
            actions:[#selector(onHost),#selector(onJoin),#selector(onDisc)])

        // Chat panel (hidden by default)
        panelChat = UIView(frame: CGRect(x:4, y:y, width:panelW-8, height:80))
        panelChat.isHidden = true
        panel.addSubview(panelChat)

        tvNetStatus = monoLabel("● OFFLINE", size:7, color:UIColor(red:0.4,green:0,blue:0,alpha:1))
        tvNetStatus.frame = CGRect(x:0,y:0,width:panelW-8,height:10)
        panelChat.addSubview(tvNetStatus)

        tvChatLog = monoLabel("", size:7, color:UIColor(red:0,green:0.7,blue:0,alpha:1))
        tvChatLog.frame = CGRect(x:0,y:12,width:panelW-8,height:44)
        tvChatLog.numberOfLines = 0
        tvChatLog.backgroundColor = UIColor(white:0.02,alpha:1)
        panelChat.addSubview(tvChatLog)

        // Chat input
        let chatRow = UIView(frame: CGRect(x:0,y:58,width:panelW-8,height:20))
        panelChat.addSubview(chatRow)
        etChat = UITextField(frame: CGRect(x:0,y:0,width:panelW-50,height:20))
        etChat.backgroundColor = UIColor(white:0.05,alpha:1)
        etChat.textColor = UIColor(red:0,green:0.8,blue:0.2,alpha:1)
        etChat.font = UIFont.monospacedSystemFont(ofSize:8, weight:.regular)
        etChat.placeholder="chat..."; etChat.returnKeyType = .send
        etChat.delegate = self; chatRow.addSubview(etChat)
        let btnSend = UIButton(type:.system)
        btnSend.frame = CGRect(x:panelW-50,y:0,width:40,height:20)
        btnSend.setTitle("▶",for:.normal); btnSend.tintColor=UIColor(red:0,green:1,blue:0.3,alpha:1)
        btnSend.backgroundColor=UIColor(white:0.06,alpha:1)
        btnSend.addTarget(self,action:#selector(sendChat),for:.touchUpInside); chatRow.addSubview(btnSend)
        y += 86

        // Divider
        let div = UIView(frame: CGRect(x:4,y:y,width:panelW-8,height:1))
        div.backgroundColor = UIColor(white:0.15,alpha:1); panel.addSubview(div); y+=5

        // Toggle keyboard/controller
        let btnToggle = makeButton("⌨ KBD", textColor:.yellow, bgColor:UIColor(white:0.06,alpha:1))
        btnToggle.frame = CGRect(x:4,y:y,width:panelW-8,height:20)
        btnToggle.addTarget(self,action:#selector(toggleInput),for:.touchUpInside)
        panel.addSubview(btnToggle); y+=22

        // Controller panel (dpad + action buttons)
        panelController = buildControllerPanel(width: panelW, atY: y)
        panel.addSubview(panelController); y+=panelController.bounds.height+4

        // Keyboard panel (hidden)
        panelKeyboard = buildKeyboardPanel(width: panelW, atY: y)
        panelKeyboard.isHidden = true
        panel.addSubview(panelKeyboard); y+=panelKeyboard.bounds.height+4

        // Hint
        let hint = monoLabel("W=fwd S=back A/D=turn SPACE=fire",size:6,color:UIColor(white:0.3,alpha:1))
        hint.frame=CGRect(x:4,y:y,width:panelW-8,height:16)
        hint.numberOfLines=2; panel.addSubview(hint); y+=20

        panel.contentSize = CGSize(width:panelW, height:y+20)
    }

    // ── Controller ────────────────────────────────────────────
    private func buildControllerPanel(width: CGFloat, atY: CGFloat) -> UIView {
        let h: CGFloat = 160
        let container = UIView(frame: CGRect(x:0, y:atY, width:width, height:h))

        let btnSz: CGFloat = 44
        let cx = width/2 - btnSz/2
        let cy: CGFloat = h/2 - btnSz/2

        func dpad(_ title:String, x:CGFloat, y:CGFloat, dir:Int) -> UIButton {
            let btn = makeButton(title, textColor:UIColor(red:0,green:0.8,blue:0.2,alpha:1),
                                 bgColor:UIColor(white:0.08,alpha:1))
            btn.frame = CGRect(x:x,y:y,width:btnSz,height:btnSz)
            btn.layer.cornerRadius = 8
            let d = dir
            btn.addTarget(self, action:#selector(dpadDown(_:)), for:.touchDown)
            btn.addTarget(self, action:#selector(dpadDown(_:)), for:.touchDragEnter)
            btn.addTarget(self, action:#selector(dpadUp(_:)), for:.touchUpInside)
            btn.addTarget(self, action:#selector(dpadUp(_:)), for:.touchUpOutside)
            btn.addTarget(self, action:#selector(dpadUp(_:)), for:.touchCancel)
            btn.tag = d
            container.addSubview(btn)
            return btn
        }

        btnUp    = dpad("▲", x:cx, y:cy-btnSz-4, dir:0)
        btnDown  = dpad("▼", x:cx, y:cy+btnSz+4, dir:1)
        btnLeft  = dpad("◀", x:cx-btnSz-4, y:cy, dir:2)
        btnRight = dpad("▶", x:cx+btnSz+4, y:cy, dir:3)

        // B / Fire
        let btnB = makeButton("B", textColor:.systemBlue, bgColor:UIColor(white:0.08,alpha:1))
        btnB.frame = CGRect(x:width-btnSz*2-8, y:cy-20, width:btnSz, height:btnSz)
        btnB.layer.cornerRadius = btnSz/2
        btnB.tag = 4
        btnB.addTarget(self,action:#selector(dpadDown(_:)),for:.touchDown)
        btnB.addTarget(self,action:#selector(dpadUp(_:)),for:.touchUpInside)
        btnB.addTarget(self,action:#selector(dpadUp(_:)),for:.touchUpOutside)
        btnB.addTarget(self,action:#selector(dpadUp(_:)),for:.touchCancel)
        container.addSubview(btnB)

        // A / Fire
        let btnA = makeButton("A", textColor:.systemYellow, bgColor:UIColor(white:0.08,alpha:1))
        btnA.frame = CGRect(x:width-btnSz-4, y:cy-20, width:btnSz, height:btnSz)
        btnA.layer.cornerRadius = btnSz/2
        btnA.tag = 5
        btnA.addTarget(self,action:#selector(dpadDown(_:)),for:.touchDown)
        btnA.addTarget(self,action:#selector(dpadUp(_:)),for:.touchUpInside)
        btnA.addTarget(self,action:#selector(dpadUp(_:)),for:.touchUpOutside)
        btnA.addTarget(self,action:#selector(dpadUp(_:)),for:.touchCancel)
        container.addSubview(btnA)

        return container
    }

    // ── Keyboard ──────────────────────────────────────────────
    private func buildKeyboardPanel(width: CGFloat, atY: CGFloat) -> UIView {
        let rows = ["1234567890","QWERTYUIOP","ASDFGHJKL","ZXCVBNM"]
        var y: CGFloat = 0
        let btnH: CGFloat = 22
        let container = UIView()

        for row in rows {
            let rowW = width - 8
            let btnW = rowW / CGFloat(row.count)
            for (i, ch) in row.enumerated() {
                let btn = makeButton(String(ch), textColor:UIColor(red:0,green:0.9,blue:0.3,alpha:1),
                                    bgColor:UIColor(white:0.05,alpha:1))
                btn.frame = CGRect(x:4+CGFloat(i)*btnW, y:y, width:btnW-1, height:btnH)
                btn.titleLabel?.font = UIFont.monospacedSystemFont(ofSize: 8, weight: .regular)
                btn.layer.borderWidth = 0.5
                btn.layer.borderColor = UIColor(white:0.2,alpha:1).cgColor
                let c = ch
                btn.addTarget(self, action:#selector(kbdTap(_:)), for:.touchUpInside)
                btn.accessibilityLabel = String(c)
                container.addSubview(btn)
            }
            y += btnH + 2
        }
        // Special keys
        let specials: [(String, CGFloat, CGFloat, String)] = [
            ("SPC",4,y,width*0.35-5),("ENT",width*0.35,y,width*0.3-2),
            ("BSP",width*0.65,y,width*0.35-12),("ESC",4,y+btnH+2,width-16)
        ]
        for (title, x, sy, w) in specials {
            let btn = makeButton(title, textColor:UIColor(red:0,green:0.9,blue:0.3,alpha:1),
                                 bgColor:UIColor(white:0.05,alpha:1))
            btn.frame = CGRect(x:x,y:sy,width:w,height:btnH)
            btn.titleLabel?.font = UIFont.monospacedSystemFont(ofSize:7, weight:.regular)
            btn.accessibilityLabel = title
            btn.addTarget(self,action:#selector(kbdTap(_:)),for:.touchUpInside)
            container.addSubview(btn)
        }
        container.frame = CGRect(x:0, y:atY, width:width, height:y+btnH*2+6)
        return container
    }

    @objc private func kbdTap(_ sender: UIButton) {
        let label = sender.accessibilityLabel ?? sender.currentTitle ?? ""
        var code = 0
        switch label {
        case "SPC": code = 32
        case "ENT": code = 13
        case "BSP": code = 8
        case "ESC": code = 27
        default: code = Int((label.uppercased().first?.asciiValue ?? 0))
        }
        machine.keyboard = code
        DispatchQueue.main.asyncAfter(deadline: .now()+0.15) { [weak self] in
            if self?.machine.keyboard == code { self?.machine.keyboard = 0 }
        }
    }

    @objc private func toggleInput() {
        keyboardVisible = !keyboardVisible
        panelKeyboard.isHidden   = !keyboardVisible
        panelController.isHidden =  keyboardVisible
    }

    // ─────────────────────────────────────────────────────────
    //  DPAD
    // ─────────────────────────────────────────────────────────
    @objc private func dpadDown(_ sender: UIButton) {
        sender.alpha = 0.45
        let tag = sender.tag
        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            switch tag {
            case 0: self.machine.keyboard = Int(UInt8(ascii:"W"))
            case 1: self.machine.keyboard = Int(UInt8(ascii:"S"))
            case 2: self.machine.keyboard = Int(UInt8(ascii:"A"))
            case 3: self.machine.keyboard = Int(UInt8(ascii:"D"))
            case 4,5: self.machine.keyboard = 32
            default: break
            }
        }
        // Also set MazeWar direct input
        if let mwg = demos.getMazeWarGame() {
            switch tag {
            case 0: mwg.iUp=true
            case 1: mwg.iDown=true
            case 2: mwg.iLeft=true
            case 3: mwg.iRight=true
            case 4,5: mwg.iFire=true
            default: break
            }
        }
    }

    @objc private func dpadUp(_ sender: UIButton) {
        sender.alpha = 1.0
        machine.keyboard = 0
        if let mwg = demos.getMazeWarGame() {
            switch sender.tag {
            case 0: mwg.iUp=false
            case 1: mwg.iDown=false
            case 2: mwg.iLeft=false
            case 3: mwg.iRight=false
            case 4,5: mwg.iFire=false
            default: break
            }
        }
    }

    // ─────────────────────────────────────────────────────────
    //  MP THREAD
    // ─────────────────────────────────────────────────────────
    private func startMP() {
        mpRunning = true
        let t = Thread {
            while self.mpRunning {
                if self.machine.mp_run {
                    for _ in 0..<200 { self.machine.mpStep() }
                    for _ in 0..<50  { self.machine.dpStep() }
                }
                Thread.sleep(forTimeInterval: 0.001)
            }
        }
        t.name = "mp-thread"; t.start(); mpThread = t
    }

    // ─────────────────────────────────────────────────────────
    //  FPS ticker
    // ─────────────────────────────────────────────────────────
    private func startFpsTicker() {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            let fps = self.crtView.actualFps
            let target = self.crtView.maxFps
            self.tvFps?.text = "\(Int(fps))/\(target)fps"
            self.tvPc?.text  = String(format:"PC:%04X  AC:%04X", self.machine.mp_pc, self.machine.mp_ac)
            self.tvAc?.text  = String(format:"IR:%04X  L:%d", self.machine.mp_ir, self.machine.mp_link)
        }
    }

    // ─────────────────────────────────────────────────────────
    //  DEMO BUTTONS
    // ─────────────────────────────────────────────────────────
    @objc func onStar()     { demos.setDemo(.star) }
    @objc func onScope()    { demos.setDemo(.scope) }
    @objc func onLiss()     { demos.setDemo(.lissajous) }
    @objc func onText()     { demos.setDemo(.text) }
    @objc func onBounce()   { demos.setDemo(.bounce) }
    @objc func onMaze()     { demos.setDemo(.maze) }
    @objc func onSpacewar() { demos.setDemo(.spacewar) }
    @objc func onGames()    { demos.setDemo(.lines) }
    @objc func onMazeWar() {
        demos.initMazeWar(); demos.setDemo(.mazeWar)
        demos.getMazeWarGame()?.startSinglePlayer()
    }

    // ─────────────────────────────────────────────────────────
    //  MACHINE BUTTONS
    // ─────────────────────────────────────────────────────────
    @objc func onPwr() { machine.powerOn() }
    @objc func onRst() { machine.reset() }
    @objc func onRun() { machine.mp_halt=false; machine.mp_run=true }
    @objc func onHlt() { machine.mp_halt=true;  machine.mp_run=false }
    @objc func onStp() { machine.mpStep() }

    // ─────────────────────────────────────────────────────────
    //  MULTIPLAYER
    // ─────────────────────────────────────────────────────────
    @objc func onHost() {
        netSession?.stop()
        netSession = NetSession()
        netSession!.chatListener  = self
        netSession!.eventListener = self
        let seed = Int.random(in: 1..<Int.max)
        demos.initMazeWar()
        demos.getMazeWarGame()?.hostMulti(netSession!)
        demos.setDemo(.mazeWar)
        netSession!.host(seed)
        setNetStatus("⚡ HOSTING — waiting for guest...")
        showChatPanel(true)
        addChat("SYS: hosting on port \(NetSession.PORT_GAME)")
        showToast("Hosting — waiting for guest")
    }

    @objc func onJoin() {
        netSession?.stop()
        netSession = NetSession()
        netSession!.chatListener  = self
        netSession!.eventListener = self
        demos.initMazeWar()
        demos.getMazeWarGame()?.joinMulti(netSession!)
        demos.setDemo(.mazeWar)
        netSession!.discover()
        setNetStatus("🔍 SEARCHING for host...")
        showChatPanel(true)
        addChat("SYS: searching...")
        showToast("Searching for host...")
    }

    @objc func onDisc() {
        netSession?.stop(); netSession=nil
        demos.getMazeWarGame()?.stopNet()
        setNetStatus("● OFFLINE"); showChatPanel(false)
        addChat("SYS: disconnected")
    }

    // ─────────────────────────────────────────────────────────
    //  CHAT
    // ─────────────────────────────────────────────────────────
    @objc func sendChat() {
        guard let text = etChat.text?.trimmingCharacters(in:.whitespaces), !text.isEmpty else { return }
        if let n = netSession, n.isConnected() { n.sendChat(text) }
        else { addChat("SYS: not connected") }
        etChat.text = ""
    }

    func addChat(_ line: String) {
        chatLines.append(line)
        if chatLines.count > 6 { chatLines.removeFirst() }
        tvChatLog?.text = chatLines.joined(separator: "\n")
    }

    func setNetStatus(_ s: String) { tvNetStatus?.text = s }

    func showChatPanel(_ show: Bool) {
        panelChat.isHidden = !show
    }

    // ─────────────────────────────────────────────────────────
    //  HELPERS
    // ─────────────────────────────────────────────────────────
    @discardableResult
    private func addButtonRow(_ parent: UIView, y: CGFloat, panelW: CGFloat,
                               titles: [String], colors: [UIColor],
                               actions: [Selector]) -> CGFloat {
        let btnH: CGFloat = 24
        let btnW = (panelW - 8) / CGFloat(titles.count)
        for (i, title) in titles.enumerated() {
            let btn = makeButton(title, textColor:colors[i], bgColor:UIColor(white:0.05,alpha:1))
            btn.frame = CGRect(x:4+CGFloat(i)*btnW, y:y, width:btnW-1, height:btnH)
            btn.addTarget(self, action:actions[i], for:.touchUpInside)
            parent.addSubview(btn)
        }
        return y + btnH + 3
    }

    private func makeButton(_ title: String, textColor: UIColor, bgColor: UIColor) -> UIButton {
        let btn = UIButton(type:.system)
        btn.setTitle(title, for:.normal)
        btn.setTitleColor(textColor, for:.normal)
        btn.backgroundColor = bgColor
        btn.titleLabel?.font = UIFont.monospacedSystemFont(ofSize:8, weight:.regular)
        btn.layer.cornerRadius = 3
        return btn
    }

    private func monoLabel(_ text: String, size: CGFloat, color: UIColor) -> UILabel {
        let lbl = UILabel()
        lbl.text = text
        lbl.textColor = color
        lbl.font = UIFont.monospacedSystemFont(ofSize:size, weight:.regular)
        lbl.adjustsFontSizeToFitWidth = true
        return lbl
    }

    private func showToast(_ msg: String) {
        let toast = UILabel()
        toast.text = msg
        toast.textColor = .white
        toast.backgroundColor = UIColor(white:0.1,alpha:0.9)
        toast.font = UIFont.monospacedSystemFont(ofSize:12, weight:.regular)
        toast.textAlignment = .center
        toast.layer.cornerRadius = 8; toast.clipsToBounds = true
        toast.frame = CGRect(x:20, y:view.bounds.height-80, width:view.bounds.width-40, height:36)
        view.addSubview(toast)
        UIView.animate(withDuration:0.3, delay:2, options:[], animations:{ toast.alpha=0 }) { _ in toast.removeFromSuperview() }
    }
}

// ── UITextFieldDelegate ───────────────────────────────────
extension EmulatorViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        sendChat(); return true
    }
}

// ── NetSession listeners ──────────────────────────────────
extension EmulatorViewController: NetSessionEventListener, NetSessionChatListener {

    func onConnected(asHost: Bool, seed: Int) {
        setNetStatus(asHost ? "✓ HOST connected" : "✓ GUEST connected")
        addChat("SYS: connected! \(asHost ? "you=HOST":"you=GUEST")")
    }
    func onPeerSync(_ demoIdx: Int, _ keyboard: Int) {
        if demoIdx != lastPeerDemo { lastPeerDemo=demoIdx; addChat("OPP demo: \(demoIdx)") }
    }
    func onPeerMazeState(_ x:Int,_ y:Int,_ dir:Int,_ hp:Int,_ score:Int) {}
    func onPeerBullet(_ dir:Int) {}
    func onPeerKilled() {}
    func onDisconnected() {
        setNetStatus("✕ DISCONNECTED"); addChat("SYS: peer disconnected")
        showToast("Peer disconnected")
    }
    func onChatMessage(from: String, msg: String) { addChat("\(from): \(msg)") }
}
