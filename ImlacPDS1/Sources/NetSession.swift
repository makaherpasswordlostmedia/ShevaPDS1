// NetSession.swift — UDP LAN multiplayer for Imlac PDS-1 iOS
// Ported from NetSession.java

import Foundation
import Network

// ── Event listener protocol ───────────────────────────────
protocol NetSessionEventListener: AnyObject {
    func onConnected(asHost: Bool, seed: Int)
    func onPeerMazeState(_ x:Int,_ y:Int,_ dir:Int,_ hp:Int,_ score:Int)
    func onPeerSync(_ demoIdx:Int,_ keyboard:Int)
    func onPeerBullet(_ dir:Int)
    func onPeerKilled()
    func onDisconnected()
}

protocol NetSessionChatListener: AnyObject {
    func onChatMessage(from: String, msg: String)
}

// ── NetSession ────────────────────────────────────────────
final class NetSession {

    static let PORT_GAME  = 7474
    static let PORT_BCAST = 7475
    private static let PKT = 32
    private static let PEER_TIMEOUT: TimeInterval = 6.0

    enum Role   { case none, host, guest }
    enum Status { case idle, hosting, searching, connected, disconnected }

    private(set) var role:   Role   = .none
    private(set) var status: Status = .idle
    private(set) var peerAddr: String?

    // Peer state
    var peerMazeX=1,peerMazeY=1,peerMazeDir=0,peerMazeHp=3,peerMazeScore=0
    var mazeSeed: Int = 0
    var myId: Int = 0

    weak var eventListener: NetSessionEventListener?
    weak var chatListener:  NetSessionChatListener?

    // Networking (using BSD sockets via GCD)
    private var gameSocket:  Int32 = -1
    private var bcastSocket: Int32 = -1
    private var running = false
    private var netQueue = DispatchQueue(label: "net.session", qos: .userInteractive)
    private var sendQueue = [Data]()
    private var sendLock  = NSLock()
    private var lastPeerTime: Date?

    // ─────────────────────────────────────────────────────────
    //  HOST
    // ─────────────────────────────────────────────────────────
    func host(_ seed: Int) {
        stop(); mazeSeed=seed; role = .host; myId=0; status = .hosting; running=true
        netQueue.async { self.hostLoop() }
    }

    private func hostLoop() {
        gameSocket  = makeUDPSocket(port: NetSession.PORT_GAME,  broadcast: false)
        bcastSocket = makeUDPSocket(port: NetSession.PORT_BCAST, broadcast: true)
        guard gameSocket >= 0 && bcastSocket >= 0 else { fail(); return }

        // Discovery phase — listen for guest broadcast
        let timeout = timeval(tv_sec: 0, tv_usec: 300_000)
        setsockopt(bcastSocket, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(gameSocket,  SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var buf = [UInt8](repeating:0, count:NetSession.PKT)
        while running && status == .hosting {
            // Check broadcast socket for 'D' (discover)
            var srcAddr = sockaddr_storage()
            var srcLen  = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let n = withUnsafeMutablePointer(to: &srcAddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity:1) {
                    recvfrom(bcastSocket, &buf, NetSession.PKT, 0, $0, &srcLen)
                }
            }
            if n == NetSession.PKT && buf[0] == UInt8(ascii:"D") {
                peerAddr = addrToString(&srcAddr)
                let welcome = makePacket(type:"W", id:0, demo:0, kbd:0, seed:mazeSeed)
                sendTo(gameSocket, data: welcome, addr: &srcAddr, addrLen: srcLen)
            }
            // Check game socket for 'J' (join ack)
            let n2 = withUnsafeMutablePointer(to: &srcAddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity:1) {
                    recvfrom(gameSocket, &buf, NetSession.PKT, 0, $0, &srcLen)
                }
            }
            if n2 == NetSession.PKT && buf[0] == UInt8(ascii:"J") {
                peerAddr = addrToString(&srcAddr)
                status = .connected
                lastPeerTime = Date()
                DispatchQueue.main.async { self.eventListener?.onConnected(asHost:true, seed:self.mazeSeed) }
            }
        }
        if status == .connected { gameLoop() }
        else { fail() }
    }

    // ─────────────────────────────────────────────────────────
    //  GUEST
    // ─────────────────────────────────────────────────────────
    func discover() {
        stop(); role = .guest; myId=1; status = .searching; running=true
        netQueue.async { self.guestLoop() }
    }

    private func guestLoop() {
        gameSocket = makeUDPSocket(port: NetSession.PORT_GAME, broadcast: true)
        guard gameSocket >= 0 else { fail(); return }

        let timeout = timeval(tv_sec: 0, tv_usec: 300_000)
        setsockopt(gameSocket, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        let bcastData = makePacket(type:"D", id:1, demo:0, kbd:0, seed:0)
        let deadline  = Date().addingTimeInterval(30)
        var buf = [UInt8](repeating:0, count:NetSession.PKT)

        while running && status == .searching && Date() < deadline {
            broadcastSend(gameSocket, data: bcastData, port: NetSession.PORT_BCAST)

            var srcAddr = sockaddr_storage()
            var srcLen  = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let n = withUnsafeMutablePointer(to: &srcAddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity:1) {
                    recvfrom(gameSocket, &buf, NetSession.PKT, 0, $0, &srcLen)
                }
            }
            if n == NetSession.PKT && buf[0] == UInt8(ascii:"W") {
                peerAddr = addrToString(&srcAddr)
                mazeSeed = decodeSeed(buf, offset: 12)
                let join = makePacket(type:"J", id:1, demo:0, kbd:0, seed:0)
                sendTo(gameSocket, data: join, addr: &srcAddr, addrLen: srcLen)
                status = .connected
                lastPeerTime = Date()
                DispatchQueue.main.async { self.eventListener?.onConnected(asHost:false, seed:self.mazeSeed) }
            }
        }
        if status == .connected { gameLoop() }
        else { fail() }
    }

    // ─────────────────────────────────────────────────────────
    //  GAME LOOP
    // ─────────────────────────────────────────────────────────
    private func gameLoop() {
        let timeout = timeval(tv_sec: 0, tv_usec: 200_000)
        setsockopt(gameSocket, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var buf = [UInt8](repeating:0, count:NetSession.PKT)

        while running {
            // Drain send queue
            sendLock.lock(); let pending = sendQueue; sendQueue.removeAll(); sendLock.unlock()
            for pkt in pending { sendToPeer(gameSocket, data: pkt) }

            // Receive
            var srcAddr = sockaddr_storage(); var srcLen = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let n = withUnsafeMutablePointer(to: &srcAddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity:1) {
                    recvfrom(gameSocket, &buf, NetSession.PKT, 0, $0, &srcLen)
                }
            }
            if n == NetSession.PKT { lastPeerTime = Date(); handlePacket(buf) }

            // Peer timeout
            if let lp = lastPeerTime, Date().timeIntervalSince(lp) > NetSession.PEER_TIMEOUT {
                fail(); return
            }
        }
    }

    private func handlePacket(_ p: [UInt8]) {
        let type = Character(UnicodeScalar(p[0]))
        switch type {
        case "S":
            let demo = Int(p[2]), kbd = (Int(p[3])<<8) | Int(p[4])
            DispatchQueue.main.async { self.eventListener?.onPeerSync(demo, kbd) }
        case "M":
            let x=Int(p[5]),y=Int(p[6]),dir=Int(p[7]),hp=Int(p[8]),sc=(Int(p[9])<<8)|Int(p[10])
            peerMazeX=x;peerMazeY=y;peerMazeDir=dir;peerMazeHp=hp;peerMazeScore=sc
            DispatchQueue.main.async { self.eventListener?.onPeerMazeState(x,y,dir,hp,sc) }
        case "B":
            let dir=Int(p[11])
            DispatchQueue.main.async { self.eventListener?.onPeerBullet(dir) }
        case "K":
            DispatchQueue.main.async { self.eventListener?.onPeerKilled() }
        case "C":
            let msg = decodeChat(p, offset: 16)
            DispatchQueue.main.async { self.chatListener?.onChatMessage(from:"OPP", msg:msg) }
        case "X":
            fail()
        default: break
        }
    }

    // ─────────────────────────────────────────────────────────
    //  SEND (thread-safe)
    // ─────────────────────────────────────────────────────────
    func sendSync(_ demoIdx: Int, _ keyboard: Int) {
        guard isConnected() else { return }
        var p = [UInt8](repeating:0, count:NetSession.PKT)
        p[0]=UInt8(ascii:"S"); p[1]=UInt8(myId); p[2]=UInt8(demoIdx)
        p[3]=UInt8((keyboard>>8)&0xFF); p[4]=UInt8(keyboard&0xFF)
        enqueue(Data(p))
    }
    func sendMazeState(_ x:Int,_ y:Int,_ dir:Int,_ hp:Int,_ score:Int) {
        guard isConnected() else { return }
        var p = [UInt8](repeating:0, count:NetSession.PKT)
        p[0]=UInt8(ascii:"M"); p[1]=UInt8(myId)
        p[5]=UInt8(x);p[6]=UInt8(y);p[7]=UInt8(dir);p[8]=UInt8(hp)
        p[9]=UInt8((score>>8)&0xFF);p[10]=UInt8(score&0xFF)
        enqueue(Data(p))
    }
    func sendBullet(_ dir: Int) {
        guard isConnected() else { return }
        var p = [UInt8](repeating:0, count:NetSession.PKT)
        p[0]=UInt8(ascii:"B"); p[1]=UInt8(myId); p[11]=UInt8(dir)
        enqueue(Data(p))
    }
    func sendKill() {
        guard isConnected() else { return }
        var p = [UInt8](repeating:0, count:NetSession.PKT)
        p[0]=UInt8(ascii:"K"); p[1]=UInt8(myId)
        enqueue(Data(p))
    }
    func sendChat(_ text: String) {
        guard isConnected() else { return }
        var p = [UInt8](repeating:0, count:NetSession.PKT)
        p[0]=UInt8(ascii:"C"); p[1]=UInt8(myId)
        let bytes = Array(text.utf8.prefix(15))
        for (i,b) in bytes.enumerated() { p[16+i]=b }
        enqueue(Data(p))
        DispatchQueue.main.async { self.chatListener?.onChatMessage(from:"ME", msg:text) }
    }
    private func enqueue(_ d: Data) { sendLock.lock(); sendQueue.append(d); sendLock.unlock() }

    // ─────────────────────────────────────────────────────────
    //  SOCKET UTILS
    // ─────────────────────────────────────────────────────────
    private func makeUDPSocket(port: Int, broadcast: Bool) -> Int32 {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return -1 }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int32>.size))
        if broadcast { setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &on, socklen_t(MemoryLayout<Int32>.size)) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port   = in_port_t(UInt16(port).bigEndian)
        addr.sin_addr   = in_addr(s_addr: INADDR_ANY)
        withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity:1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return fd
    }

    private func sendTo(_ fd: Int32, data: Data, addr: inout sockaddr_storage, addrLen: socklen_t) {
        var d = data
        withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity:1) { sa in
                d.withUnsafeMutableBytes { ptr in
                    sendto(fd, ptr.baseAddress, data.count, 0, sa, addrLen)
                }
            }
        }
    }

    private func sendToPeer(_ fd: Int32, data: Data) {
        guard let peer = peerAddr else { return }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port   = in_port_t(UInt16(NetSession.PORT_GAME).bigEndian)
        addr.sin_addr.s_addr = inet_addr(peer)
        withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity:1) { sa in
                var d = data
                d.withUnsafeMutableBytes { ptr in
                    sendto(fd, ptr.baseAddress, data.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    private func broadcastSend(_ fd: Int32, data: Data, port: Int) {
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port   = in_port_t(UInt16(port).bigEndian)
        addr.sin_addr.s_addr = INADDR_BROADCAST
        withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity:1) { sa in
                var d = data
                d.withUnsafeMutableBytes { ptr in
                    sendto(fd, ptr.baseAddress, data.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    private func addrToString(_ addr: inout sockaddr_storage) -> String {
        var buf = [CChar](repeating:0, count:Int(INET_ADDRSTRLEN))
        withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr_in.self, capacity:1) {
                var a = $0.pointee.sin_addr
                inet_ntop(AF_INET, &a, &buf, socklen_t(INET_ADDRSTRLEN))
            }
        }
        return String(cString: buf)
    }

    private func makePacket(type: String, id: Int, demo: Int, kbd: Int, seed: Int) -> Data {
        var p = [UInt8](repeating:0, count:NetSession.PKT)
        p[0]=type.utf8.first ?? 0; p[1]=UInt8(id); p[2]=UInt8(demo)
        p[3]=UInt8((kbd>>8)&0xFF); p[4]=UInt8(kbd&0xFF)
        p[12]=UInt8((seed>>24)&0xFF); p[13]=UInt8((seed>>16)&0xFF)
        p[14]=UInt8((seed>>8)&0xFF);  p[15]=UInt8(seed&0xFF)
        return Data(p)
    }

    private func decodeSeed(_ p: [UInt8], offset: Int) -> Int {
        (Int(p[offset])<<24)|(Int(p[offset+1])<<16)|(Int(p[offset+2])<<8)|Int(p[offset+3])
    }

    private func decodeChat(_ p: [UInt8], offset: Int) -> String {
        let bytes = p[offset...].prefix(while: { $0 != 0 })
        return String(bytes: bytes, encoding: .utf8) ?? ""
    }

    private func fail() {
        status = .disconnected
        DispatchQueue.main.async { self.eventListener?.onDisconnected() }
        closeAll()
    }

    func stop() {
        running = false; closeAll(); status = .idle; role = .none
    }

    private func closeAll() {
        if gameSocket  >= 0 { Darwin.close(gameSocket);  gameSocket  = -1 }
        if bcastSocket >= 0 { Darwin.close(bcastSocket); bcastSocket = -1 }
    }

    func isConnected() -> Bool { status == .connected }
}
