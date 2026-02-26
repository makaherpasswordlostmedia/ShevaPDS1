// Machine.swift — Imlac PDS-1 emulator core
// Ported from Machine.java

import Foundation

final class Machine {

    // ── Constants ──────────────────────────────────────────────
    static let MEM_SIZE  = 4096
    static let WORD_MASK = 0xFFFF
    static let ADDR_MASK = 0x0FFF

    // ── MP registers ──────────────────────────────────────────
    var mp_pc   = 0
    var mp_ac   = 0
    var mp_ir   = 0
    var mp_link = 0
    var mp_halt = true
    var mp_run  = false

    // ── DP registers ──────────────────────────────────────────
    var dp_pc        = 0x100
    var dp_ac        = 0
    var dp_x         = 512
    var dp_y         = 512
    var dp_halt      = false
    var dp_enabled   = true
    var dp_intensity = 7
    var dp_scale     = Float(1.0)
    private var dp_ret_stack = [Int](repeating: 0, count: 16)
    private var dp_ret_top   = 0

    // ── Memory ────────────────────────────────────────────────
    var mem = [Int](repeating: 0, count: MEM_SIZE)

    // ── I/O ───────────────────────────────────────────────────
    var keyboard  = 0
    var lpen_x    = 0
    var lpen_y    = 0
    var lpen_hit  = false

    // ── Display list ──────────────────────────────────────────
    static let MAX_VEC = 32768
    struct Vec {
        var x1, y1, x2, y2: Int
        var isPoint: Bool
        var bright: Float   // 0..1
    }
    var vecs = [Vec](repeating: Vec(x1:0,y1:0,x2:0,y2:0,isPoint:false,bright:0), count: MAX_VEC)
    var nvec = 0

    // ── Console ───────────────────────────────────────────────
    var console = ""
    var cycles  = 0

    // ──────────────────────────────────────────────────────────
    //  RESET
    // ──────────────────────────────────────────────────────────
    func reset() {
        mp_pc=0; mp_ac=0; mp_ir=0; mp_link=0
        mp_halt=true; mp_run=false
        dp_pc=0x100; dp_ac=0; dp_x=512; dp_y=512
        dp_halt=false; dp_enabled=true; dp_intensity=7; dp_scale=1
        dp_ret_top=0; keyboard=0; cycles=0; nvec=0
    }

    func powerOn() { reset(); mp_halt=false; mp_run=true }

    // ── Display list ──────────────────────────────────────────
    func dlLine(_ x1: Int,_ y1: Int,_ x2: Int,_ y2: Int,_ bright: Float) {
        guard nvec < Machine.MAX_VEC else { return }
        vecs[nvec] = Vec(x1:x1,y1:y1,x2:x2,y2:y2,isPoint:false,bright:bright)
        nvec += 1
    }
    func dlPoint(_ x: Int,_ y: Int,_ bright: Float) {
        guard nvec < Machine.MAX_VEC else { return }
        vecs[nvec] = Vec(x1:x,y1:y,x2:0,y2:0,isPoint:true,bright:bright)
        nvec += 1
    }
    func dlClear() { nvec = 0 }

    // ──────────────────────────────────────────────────────────
    //  MAIN PROCESSOR
    // ──────────────────────────────────────────────────────────
    func mpStep() {
        guard !mp_halt else { return }
        let word = mem[mp_pc & Machine.ADDR_MASK] & Machine.WORD_MASK
        mp_ir = word
        mp_pc = (mp_pc + 1) & Machine.ADDR_MASK
        cycles += 1

        let op  = (word >> 12) & 0xF
        let ind = (word >> 11) & 0x1
        var ea  =  word & Machine.ADDR_MASK
        if ind != 0 { ea = mem[ea] & Machine.ADDR_MASK }

        switch op {
        case 0x0: break
        case 0x1:
            if ind != 0 { mp_ac = (-(word & 0x7FF)) & Machine.WORD_MASK }
            else        { mp_ac =  (word & 0x7FF) }
        case 0x2: mp_pc = ea
        case 0x3: mem[ea] = mp_ac
        case 0x4: let t = mem[ea]; mem[ea] = mp_ac; mp_ac = t
        case 0x5:
            mem[ea] = (mem[ea] + 1) & Machine.WORD_MASK
            if (mem[ea] & 0x8000) == 0 { mp_pc = (mp_pc + 1) & Machine.ADDR_MASK }
        case 0x6:
            let s = mp_ac + mem[ea]
            mp_link = (s >> 16) & 1; mp_ac = s & Machine.WORD_MASK
        case 0x7: mp_ac &= mem[ea]
        case 0x8: mp_ac = mem[ea] & Machine.WORD_MASK
        case 0x9: mem[ea] = mp_pc; mp_pc = (ea + 1) & Machine.ADDR_MASK
        case 0xA: mpSkip(word)
        case 0xB: mp_ac |= mem[ea]; mp_ac &= Machine.WORD_MASK
        case 0xC:
            var n = word & 0xFF; if n == 0 { n = 1 }
            for _ in 0..<n {
                let b = (mp_ac >> 15) & 1
                mp_ac = ((mp_ac << 1) | mp_link) & Machine.WORD_MASK; mp_link = b
            }
        case 0xD:
            var n = word & 0xFF; if n == 0 { n = 1 }
            for _ in 0..<n {
                let b = mp_ac & 1
                mp_ac = ((mp_ac >> 1) | (mp_link << 15)) & Machine.WORD_MASK; mp_link = b
            }
        case 0xE: mpIOT(word)
        case 0xF: mpOPR(word)
        default: break
        }
    }

    private func mpSkip(_ word: Int) {
        let inv  = (word >> 5) & 1
        let cond =  word & 0x1F
        var skip = false
        if (cond & 0x01) != 0 { skip = skip || (mp_ac == 0) }
        if (cond & 0x02) != 0 { skip = skip || ((mp_ac & 0x8000) == 0) }
        if (cond & 0x04) != 0 { skip = skip || (mp_link == 0) }
        if (cond & 0x08) != 0 { skip = skip || (keyboard != 0) }
        if (cond & 0x10) != 0 { skip = skip || dp_halt }
        if inv != 0 { skip = !skip }
        if skip { mp_pc = (mp_pc + 1) & Machine.ADDR_MASK }
    }

    private func mpOPR(_ word: Int) {
        if (word & 0x800) != 0 {
            mp_halt = true; mp_run = false
            console += "[HALT PC=\(String(mp_pc, radix:16).uppercased()) AC=\(String(mp_ac, radix:16).uppercased())]\n"
            return
        }
        if (word & 0x400) != 0 { mp_ac = 0 }
        if (word & 0x200) != 0 { mp_link = 0 }
        if (word & 0x100) != 0 { mp_ac = (~mp_ac) & Machine.WORD_MASK }
        if (word & 0x080) != 0 { mp_link ^= 1 }
        if (word & 0x040) != 0 { let s = mp_ac + 1; mp_link = (s>>16)&1; mp_ac = s & Machine.WORD_MASK }
        if (word & 0x020) != 0 { mp_link = 1 }
        if (word & 0x010) != 0 { let t = mp_ac; mp_ac = dp_ac; dp_ac = t }
        if (word & 0x008) != 0 { let b=(mp_ac>>15)&1; mp_ac=((mp_ac<<1)|mp_link)&Machine.WORD_MASK; mp_link=b }
        if (word & 0x004) != 0 { let b=mp_ac&1; mp_ac=((mp_ac>>1)|(mp_link<<15))&Machine.WORD_MASK; mp_link=b }
    }

    private func mpIOT(_ word: Int) {
        let dev = (word >> 6) & 0x3F
        let fn  =  word       & 0x3F
        switch dev {
        case 0x01:
            if (fn & 1) != 0 { mp_ac = keyboard & Machine.WORD_MASK }
            if (fn & 2) != 0 { keyboard = 0 }
            if (fn & 4) != 0 && keyboard != 0 { mp_pc = (mp_pc+1) & Machine.ADDR_MASK }
        case 0x02:
            if (fn & 1) != 0 { dp_enabled = !dp_enabled }
            if (fn & 2) != 0 { dp_halt = false; dp_pc = mp_ac & Machine.ADDR_MASK }
            if (fn & 4) != 0 { dp_halt = true }
        case 0x04:
            let c = Character(UnicodeScalar(mp_ac & 0x7F)!)
            if c.asciiValue! >= 32 || c == "\n" { console.append(c) }
        case 0x10:
            if (fn & 1) != 0 { mp_ac = lpen_x }
            if (fn & 2) != 0 { mp_ac = lpen_y }
            if (fn & 4) != 0 && lpen_hit { mp_pc = (mp_pc+1) & Machine.ADDR_MASK }
        case 0x20: mp_ac = cycles & Machine.WORD_MASK
        default: break
        }
    }

    // ──────────────────────────────────────────────────────────
    //  DISPLAY PROCESSOR
    // ──────────────────────────────────────────────────────────
    func dpStep() {
        guard dp_enabled && !dp_halt else { return }
        let word = mem[dp_pc & Machine.ADDR_MASK] & Machine.WORD_MASK
        dp_pc = (dp_pc + 1) & Machine.ADDR_MASK
        let op   = (word >> 12) & 0xF
        let addr =  word & Machine.ADDR_MASK
        let bright = max(Float(dp_intensity) / 7.0, 0.05)

        switch op {
        case 0x0:
            if (word & 0x0E00) == 0x0E00 { dp_intensity = word & 0x7 }
        case 0x1: dp_x = addr
        case 0x2: dp_y = addr
        case 0x3:
            var dx = (word >> 6) & 0x1F; var dy = word & 0x1F
            if (word & 0x0800) != 0 { dx = -dx }
            if (word & 0x0020) != 0 { dy = -dy }
            let nx=(dp_x+dx)&1023; let ny=(dp_y+dy)&1023
            dlLine(dp_x,dp_y,nx,ny,bright); dp_x=nx; dp_y=ny
        case 0x4:
            var dx = ((word >> 6) & 0x3F) * 8; var dy = (word & 0x3F) * 8
            if (word & 0x0800) != 0 { dx = -dx }
            if (word & 0x0020) != 0 { dy = -dy }
            let nx=(dp_x+dx)&1023; let ny=(dp_y+dy)&1023
            dlLine(dp_x,dp_y,nx,ny,bright); dp_x=nx; dp_y=ny
        case 0x5: dp_pc = addr
        case 0x6:
            if dp_ret_top < 15 { dp_ret_stack[dp_ret_top] = dp_pc; dp_ret_top += 1 }
            dp_pc = addr
        case 0x7:
            if (word & 0x0800) != 0 { dlPoint(dp_x,dp_y,bright) }
            else if (word & 0x0010) != 0 { dp_intensity = word & 0x7 }
        case 0x8:
            if (word & 0x0800) != 0 && dp_ret_top > 0 { dp_ret_top -= 1; dp_pc = dp_ret_stack[dp_ret_top] }
            else { dp_halt = true }
        case 0x9: dp_intensity = word & 0x7
        case 0xA:
            let sf = word & 0x3
            let sc: [Float] = [0.25,0.5,1.0,2.0]; dp_scale = sc[sf]
        case 0xB:
            if dp_ret_top > 0 { dp_ret_top -= 1; dp_pc = dp_ret_stack[dp_ret_top] }
            else { dp_halt = true }
        case 0xC: dp_x = addr
        case 0xD: dp_y = addr
        case 0xE: dp_x = (word >> 6) & 0x1F; dp_y = word & 0x1F
        case 0xF: dp_halt = true
        default: break
        }
    }

    // ──────────────────────────────────────────────────────────
    //  ASSEMBLER
    // ──────────────────────────────────────────────────────────
    private let MNEM_NAMES = ["LAW","JMP","DAC","XAM","ISP","ADD","AND","LDA","JMS","IOR",
        "RAL","RAR","IOT","HLT","CLA","CLL","CMA","CML","IAC","STL","SAM","NOP",
        "SKZ","SKP","SKL","SKK","SKD","DLXA","DLYA","DSVH","DLVH","DJMP","DJMS",
        "DPTS","DHLT","DRJM","DEIM","DVSF","RAL1","RAR1"]
    private let MNEM_OPC  = [0x1000,0x2000,0x3000,0x4000,0x5000,0x6000,0x7000,0x8000,0x9000,0xB000,
        0xC000,0xD000,0xE000,0xF800,0xF400,0xF200,0xF100,0xF080,0xF040,0xF020,0xF010,0xF000,
        0xA001,0xA002,0xA004,0xA008,0xA010,0x1000,0x2000,0x3000,0x4000,0x5000,0x6000,
        0x7800,0x8000,0xB000,0x9000,0xA000,0xC001,0xD001]
    private let MNEM_HAS_ADDR = [true,true,true,true,true,true,true,true,true,true,
        true,true,true,false,false,false,false,false,false,false,false,false,
        false,false,false,false,false,true,true,true,true,true,true,
        false,false,false,true,true,false,false]

    private var asmLabels = [String: Int]()

    private func asmParseVal(_ tok: String) -> Int {
        let t = tok.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("0x") || t.hasPrefix("0X") {
            return Int(t.dropFirst(2), radix: 16) ?? 0
        }
        if let lv = asmLabels[t.uppercased()] { return lv }
        return Int(t) ?? 0
    }

    @discardableResult
    func assemble(_ src: String) -> Int {
        asmLabels = [:]
        let lines = src.components(separatedBy: "\n")
        var baseAddr = 0x050

        // Pass 1: labels
        var addr = baseAddr
        for rawLine in lines {
            let line = (rawLine.components(separatedBy: ";").first ?? "").trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            var tok = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if tok.isEmpty { continue }
            let up = tok[0].uppercased()
            if up == ".ORG" || up == "ORG" { if tok.count > 1 { addr = asmParseVal(tok[1]) }; continue }
            if up == ".DP" || up == ".MP" { continue }
            if tok[0].hasSuffix(":") {
                let lbl = String(tok[0].dropLast()).uppercased()
                asmLabels[lbl] = addr
                tok.removeFirst(); if tok.isEmpty { continue }
            }
            if tok[0].uppercased() == ".WORD" || tok[0].uppercased() == "DATA" { addr += tok.count - 1; continue }
            addr += 1
        }

        // Pass 2: emit
        addr = baseAddr
        for rawLine in lines {
            let line = (rawLine.components(separatedBy: ";").first ?? "").trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            var tok = line.components(separatedBy: CharacterSet(charactersIn: " \t,")).filter { !$0.isEmpty }
            if tok.isEmpty { continue }
            let up0 = tok[0].uppercased()
            if up0 == ".ORG" || up0 == "ORG" { if tok.count > 1 { addr = asmParseVal(tok[1]) }; continue }
            if up0 == ".DP" || up0 == ".MP" { continue }
            if tok[0].hasSuffix(":") { tok.removeFirst(); if tok.isEmpty { continue } }
            let mnUp = tok[0].uppercased()
            if mnUp == ".WORD" || mnUp == "DATA" {
                for i in 1..<tok.count { if addr < Machine.MEM_SIZE { mem[addr] = asmParseVal(tok[i]); addr += 1 } }
                continue
            }
            guard let mi = MNEM_NAMES.firstIndex(of: mnUp) else { continue }
            var word = MNEM_OPC[mi]
            if MNEM_HAS_ADDR[mi] && tok.count > 1 {
                let val = asmParseVal(tok[1])
                if (word & 0xF000) == 0x1000 { word |= (val & 0x7FF) }
                else { word |= (val & Machine.ADDR_MASK) }
            }
            if addr < Machine.MEM_SIZE { mem[addr] = word; addr += 1 }
        }
        return addr - baseAddr
    }
}
