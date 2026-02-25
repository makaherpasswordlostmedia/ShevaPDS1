package com.imlac.pds1;

/**
 * Imlac PDS-1 Emulator Core
 *
 * Complete emulation of both processors:
 *   - Main Processor (MP): 16-bit, 4096 words RAM
 *   - Display Processor (DP): vector CRT, 1024x1024
 *
 * Instruction set:
 *   LAW JMP DAC XAM ISP ADD AND LDA JMS IOR RAL RAR IOT OPR
 *   Display: DLXA DLYA DSVH DLVH DJMP DJMS DHLT DRJM DEIM DVSF DPTS
 */
public class Machine {

    // ── Constants ──────────────────────────────────────────────
    public static final int MEM_SIZE  = 4096;
    public static final int WORD_MASK = 0xFFFF;
    public static final int ADDR_MASK = 0x0FFF;

    // Directions for display processor
    public static final int DIR_N = 0, DIR_E = 1, DIR_S = 2, DIR_W = 3;

    // ── Main Processor registers ───────────────────────────────
    public int   mp_pc   = 0;
    public int   mp_ac   = 0;
    public int   mp_ir   = 0;
    public int   mp_link = 0;
    public boolean mp_halt = true;
    public boolean mp_run  = false;

    // ── Display Processor registers ───────────────────────────
    public int   dp_pc        = 0x100;
    public int   dp_ac        = 0;
    public int   dp_x         = 512;
    public int   dp_y         = 512;
    public boolean dp_halt    = false;
    public boolean dp_enabled = true;
    public int   dp_intensity = 7;
    public float dp_scale     = 1.0f;

    private final int[] dp_ret_stack = new int[16];
    private int         dp_ret_top   = 0;

    // ── Memory ────────────────────────────────────────────────
    public final int[] mem = new int[MEM_SIZE];

    // ── I/O ───────────────────────────────────────────────────
    public int  keyboard    = 0;
    public int  lpen_x      = 0;
    public int  lpen_y      = 0;
    public boolean lpen_hit = false;

    // ── Display list ──────────────────────────────────────────
    // Each vector: x1,y1,x2,y2,point(0/1),bright(0..255)
    public static final int MAX_VEC = 32768;
    public final int[]   vx1    = new int[MAX_VEC];
    public final int[]   vy1    = new int[MAX_VEC];
    public final int[]   vx2    = new int[MAX_VEC];
    public final int[]   vy2    = new int[MAX_VEC];
    public final boolean[] vpt  = new boolean[MAX_VEC];
    public final int[]   vbr    = new int[MAX_VEC];   // 0-255
    public int           nvec   = 0;

    // ── Console ───────────────────────────────────────────────
    public final StringBuilder console = new StringBuilder();

    // ── Stats ─────────────────────────────────────────────────
    public long cycles = 0;

    // ──────────────────────────────────────────────────────────
    //  RESET
    // ──────────────────────────────────────────────────────────
    public void reset() {
        mp_pc = 0; mp_ac = 0; mp_ir = 0; mp_link = 0;
        mp_halt = true; mp_run = false;
        dp_pc = 0x100; dp_ac = 0;
        dp_x = 512; dp_y = 512;
        dp_halt = false; dp_enabled = true;
        dp_intensity = 7; dp_scale = 1.0f;
        dp_ret_top = 0;
        keyboard = 0;
        cycles = 0;
        nvec = 0;
    }

    public void powerOn() {
        reset();
        mp_halt = false;
        mp_run  = true;
    }

    // ──────────────────────────────────────────────────────────
    //  DISPLAY LIST
    // ──────────────────────────────────────────────────────────
    public void dlLine(int x1, int y1, int x2, int y2, float bright) {
        if (nvec >= MAX_VEC) return;
        vx1[nvec] = x1; vy1[nvec] = y1;
        vx2[nvec] = x2; vy2[nvec] = y2;
        vpt[nvec] = false;
        vbr[nvec] = (int)(bright * 255);
        nvec++;
    }

    public void dlPoint(int x, int y, float bright) {
        if (nvec >= MAX_VEC) return;
        vx1[nvec] = x; vy1[nvec] = y;
        vpt[nvec] = true;
        vbr[nvec] = (int)(bright * 255);
        nvec++;
    }

    public void dlClear() { nvec = 0; }

    // ──────────────────────────────────────────────────────────
    //  MAIN PROCESSOR — execute one instruction
    // ──────────────────────────────────────────────────────────
    public void mpStep() {
        if (mp_halt) return;

        int word = mem[mp_pc & ADDR_MASK] & WORD_MASK;
        mp_ir = word;
        mp_pc = (mp_pc + 1) & ADDR_MASK;
        cycles++;

        int op  = (word >> 12) & 0xF;
        int ind = (word >> 11) & 0x1;
        int ea  =  word & ADDR_MASK;

        if (ind != 0) ea = mem[ea] & ADDR_MASK;

        switch (op) {
            case 0x0: break; // NOP

            case 0x1: // LAW — Load Accumulator With immediate
                if (ind != 0)
                    mp_ac = (-(word & 0x7FF)) & WORD_MASK;
                else
                    mp_ac =  (word & 0x7FF);
                break;

            case 0x2: // JMP
                mp_pc = ea;
                break;

            case 0x3: // DAC — Deposit Accumulator
                mem[ea] = mp_ac;
                break;

            case 0x4: // XAM — Exchange Accumulator with Memory
                { int t = mem[ea]; mem[ea] = mp_ac; mp_ac = t; }
                break;

            case 0x5: // ISP — Increment and Skip if Positive
                mem[ea] = (mem[ea] + 1) & WORD_MASK;
                if ((mem[ea] & 0x8000) == 0)
                    mp_pc = (mp_pc + 1) & ADDR_MASK;
                break;

            case 0x6: // ADD
                { int s = mp_ac + mem[ea];
                  mp_link = (s >> 16) & 1;
                  mp_ac   =  s & WORD_MASK; }
                break;

            case 0x7: // AND
                mp_ac &= mem[ea];
                break;

            case 0x8: // LDA
                mp_ac = mem[ea] & WORD_MASK;
                break;

            case 0x9: // JMS — Jump to Subroutine
                mem[ea] = mp_pc;
                mp_pc   = (ea + 1) & ADDR_MASK;
                break;

            case 0xA: // SKP — Skip conditions
                mpSkip(word);
                break;

            case 0xB: // IOR — Inclusive OR
                mp_ac |= mem[ea];
                mp_ac &= WORD_MASK;
                break;

            case 0xC: // RAL n — Rotate Accumulator Left
                { int n = word & 0xFF; if (n == 0) n = 1;
                  for (int i = 0; i < n; i++) {
                      int b = (mp_ac >> 15) & 1;
                      mp_ac = ((mp_ac << 1) | mp_link) & WORD_MASK;
                      mp_link = b;
                  } }
                break;

            case 0xD: // RAR n — Rotate Accumulator Right
                { int n = word & 0xFF; if (n == 0) n = 1;
                  for (int i = 0; i < n; i++) {
                      int b = mp_ac & 1;
                      mp_ac = ((mp_ac >> 1) | (mp_link << 15)) & WORD_MASK;
                      mp_link = b;
                  } }
                break;

            case 0xE: // IOT — I/O Transfer
                mpIOT(word);
                break;

            case 0xF: // OPR — Operate micro-instructions
                mpOPR(word);
                break;
        }
    }

    private void mpSkip(int word) {
        int inv  = (word >> 5) & 1;
        int cond =  word & 0x1F;
        boolean skip = false;
        if ((cond & 0x01) != 0) skip |= (mp_ac == 0);
        if ((cond & 0x02) != 0) skip |= ((mp_ac & 0x8000) == 0);
        if ((cond & 0x04) != 0) skip |= (mp_link == 0);
        if ((cond & 0x08) != 0) skip |= (keyboard != 0);
        if ((cond & 0x10) != 0) skip |= dp_halt;
        if (inv != 0) skip = !skip;
        if (skip) mp_pc = (mp_pc + 1) & ADDR_MASK;
    }

    private void mpOPR(int word) {
        if ((word & 0x800) != 0) {
            // HLT
            mp_halt = true; mp_run = false;
            console.append("[HALT PC=").append(Integer.toHexString(mp_pc).toUpperCase())
                   .append(" AC=").append(Integer.toHexString(mp_ac).toUpperCase())
                   .append("]\n");
            return;
        }
        if ((word & 0x400) != 0) mp_ac   = 0;               // CLA
        if ((word & 0x200) != 0) mp_link = 0;               // CLL
        if ((word & 0x100) != 0) mp_ac   = (~mp_ac) & WORD_MASK; // CMA
        if ((word & 0x080) != 0) mp_link ^= 1;              // CML
        if ((word & 0x040) != 0) {                           // IAC
            int s = mp_ac + 1;
            mp_link = (s >> 16) & 1;
            mp_ac   =  s & WORD_MASK;
        }
        if ((word & 0x020) != 0) mp_link = 1;               // STL
        if ((word & 0x010) != 0) {                           // SAM — swap with DP AC
            int t = mp_ac; mp_ac = dp_ac; dp_ac = t;
        }
        if ((word & 0x008) != 0) {                           // RAL 1
            int b = (mp_ac >> 15) & 1;
            mp_ac = ((mp_ac << 1) | mp_link) & WORD_MASK;
            mp_link = b;
        }
        if ((word & 0x004) != 0) {                           // RAR 1
            int b = mp_ac & 1;
            mp_ac = ((mp_ac >> 1) | (mp_link << 15)) & WORD_MASK;
            mp_link = b;
        }
    }

    private void mpIOT(int word) {
        int dev = (word >> 6) & 0x3F;
        int fn  =  word       & 0x3F;
        switch (dev) {
            case 0x01: // Keyboard
                if ((fn & 1) != 0) mp_ac = keyboard & WORD_MASK;
                if ((fn & 2) != 0) keyboard = 0;
                if ((fn & 4) != 0 && keyboard != 0)
                    mp_pc = (mp_pc + 1) & ADDR_MASK;
                break;
            case 0x02: // Display Processor control
                if ((fn & 1) != 0) dp_enabled = !dp_enabled;
                if ((fn & 2) != 0) { dp_halt = false; dp_pc = mp_ac & ADDR_MASK; }
                if ((fn & 4) != 0) dp_halt = true;
                break;
            case 0x04: // TTY output
                { char c = (char)(mp_ac & 0x7F);
                  if (c >= 32 || c == '\n') console.append(c); }
                break;
            case 0x10: // Light pen
                if ((fn & 1) != 0) mp_ac = lpen_x;
                if ((fn & 2) != 0) mp_ac = lpen_y;
                if ((fn & 4) != 0 && lpen_hit)
                    mp_pc = (mp_pc + 1) & ADDR_MASK;
                break;
            case 0x20: // Clock
                mp_ac = (int)(cycles & WORD_MASK);
                break;
        }
    }

    // ──────────────────────────────────────────────────────────
    //  DISPLAY PROCESSOR — execute one instruction
    // ──────────────────────────────────────────────────────────
    public void dpStep() {
        if (!dp_enabled || dp_halt) return;

        int word = mem[dp_pc & ADDR_MASK] & WORD_MASK;
        dp_pc = (dp_pc + 1) & ADDR_MASK;

        int op   = (word >> 12) & 0xF;
        int addr =  word & ADDR_MASK;

        float bright = dp_intensity / 7.0f;
        if (bright < 0.05f) bright = 0.05f;

        switch (op) {
            case 0x0: // NOP or intensity
                if ((word & 0x0E00) == 0x0E00)
                    dp_intensity = word & 0x7;
                break;

            case 0x1: // DLXA — Load X
                dp_x = addr;
                break;

            case 0x2: // DLYA — Load Y
                dp_y = addr;
                break;

            case 0x3: // DSVH — Short Vector (signed 5-bit dx,dy)
                { int dx = (word >> 6) & 0x1F;
                  int dy =  word       & 0x1F;
                  if ((word & 0x0800) != 0) dx = -dx;
                  if ((word & 0x0020) != 0) dy = -dy;
                  int nx = (dp_x + dx) & 1023;
                  int ny = (dp_y + dy) & 1023;
                  dlLine(dp_x, dp_y, nx, ny, bright);
                  dp_x = nx; dp_y = ny; }
                break;

            case 0x4: // DLVH — Long Vector (signed 6-bit × 8)
                { int dx = ((word >> 6) & 0x3F) * 8;
                  int dy =  (word       & 0x3F) * 8;
                  if ((word & 0x0800) != 0) dx = -dx;
                  if ((word & 0x0020) != 0) dy = -dy;
                  int nx = (dp_x + dx) & 1023;
                  int ny = (dp_y + dy) & 1023;
                  dlLine(dp_x, dp_y, nx, ny, bright);
                  dp_x = nx; dp_y = ny; }
                break;

            case 0x5: // DJMP
                dp_pc = addr;
                break;

            case 0x6: // DJMS — Jump to Subroutine
                if (dp_ret_top < 15)
                    dp_ret_stack[dp_ret_top++] = dp_pc;
                dp_pc = addr;
                break;

            case 0x7: // DPTS / DSTS
                if ((word & 0x0800) != 0)
                    dlPoint(dp_x, dp_y, bright);
                else if ((word & 0x0010) != 0)
                    dp_intensity = word & 0x7;
                break;

            case 0x8: // DHLT
                if ((word & 0x0800) != 0 && dp_ret_top > 0)
                    dp_pc = dp_ret_stack[--dp_ret_top];
                else
                    dp_halt = true;
                break;

            case 0x9: // DEIM — intensity
                dp_intensity = word & 0x7;
                break;

            case 0xA: // DVSF — scale
                { int sf = word & 0x3;
                  float[] sc = {0.25f, 0.5f, 1.0f, 2.0f};
                  dp_scale = sc[sf]; }
                break;

            case 0xB: // DRJM — Return from subroutine
                if (dp_ret_top > 0)
                    dp_pc = dp_ret_stack[--dp_ret_top];
                else
                    dp_halt = true;
                break;

            case 0xC: dp_x = addr; break;
            case 0xD: dp_y = addr; break;

            case 0xE: // DXYA — load X and Y packed
                dp_x = (word >> 6) & 0x1F;
                dp_y =  word       & 0x1F;
                break;

            case 0xF:
                dp_halt = true;
                break;
        }
    }

    // ──────────────────────────────────────────────────────────
    //  ASSEMBLER — two-pass, PDS-1 mnemonics
    // ──────────────────────────────────────────────────────────
    private final String[] MNEM_NAMES = {
        "LAW","JMP","DAC","XAM","ISP","ADD","AND","LDA","JMS","IOR",
        "RAL","RAR","IOT","HLT","CLA","CLL","CMA","CML","IAC","STL",
        "SAM","NOP","SKZ","SKP","SKL","SKK","SKD",
        "DLXA","DLYA","DSVH","DLVH","DJMP","DJMS","DPTS","DHLT","DRJM",
        "DEIM","DVSF","RAL1","RAR1"
    };
    private final int[] MNEM_OPC = {
        0x1000,0x2000,0x3000,0x4000,0x5000,0x6000,0x7000,0x8000,0x9000,0xB000,
        0xC000,0xD000,0xE000,0xF800,0xF400,0xF200,0xF100,0xF080,0xF040,0xF020,
        0xF010,0xF000,0xA001,0xA002,0xA004,0xA008,0xA010,
        0x1000,0x2000,0x3000,0x4000,0x5000,0x6000,0x7800,0x8000,0xB000,
        0x9000,0xA000,0xC001,0xD001
    };
    private final boolean[] MNEM_HAS_ADDR = {
        true,true,true,true,true,true,true,true,true,true,
        true,true,true,false,false,false,false,false,false,false,
        false,false,false,false,false,false,false,
        true,true,true,true,true,true,false,false,false,
        true,true,false,false
    };

    private final String[] asmLabelNames = new String[512];
    private final int[]    asmLabelAddrs = new int[512];
    private int            asmNLabels    = 0;

    private void asmClearLabels() { asmNLabels = 0; }

    private void asmAddLabel(String name, int addr) {
        if (asmNLabels >= 512) return;
        asmLabelNames[asmNLabels] = name.toUpperCase();
        asmLabelAddrs[asmNLabels] = addr;
        asmNLabels++;
    }

    private int asmFindLabel(String name) {
        String upper = name.toUpperCase();
        for (int i = 0; i < asmNLabels; i++)
            if (asmLabelNames[i].equals(upper)) return asmLabelAddrs[i];
        return -1;
    }

    private int asmFindMnem(String name) {
        String upper = name.toUpperCase();
        for (int i = 0; i < MNEM_NAMES.length; i++)
            if (MNEM_NAMES[i].equals(upper)) return i;
        return -1;
    }

    private int asmParseVal(String tok) {
        if (tok == null || tok.isEmpty()) return 0;
        tok = tok.trim();
        if (tok.startsWith("0x") || tok.startsWith("0X"))
            return Integer.parseInt(tok.substring(2), 16) & WORD_MASK;
        if (tok.startsWith("0") && tok.length() > 1)
            return Integer.parseInt(tok.substring(1), 8) & WORD_MASK;
        int lv = asmFindLabel(tok);
        if (lv >= 0) return lv;
        try { return Integer.parseInt(tok) & WORD_MASK; }
        catch (NumberFormatException e) { return 0; }
    }

    /** Assemble source into mem[], returns number of words emitted */
    public int assemble(String src) {
        asmClearLabels();
        String[] lines = src.split("\n");
        int baseAddr = 0x050;

        // Pass 1: collect labels
        int addr = baseAddr;
        for (String rawLine : lines) {
            String line = rawLine.split(";")[0].trim();
            if (line.isEmpty()) continue;
            String[] tok = line.split("\\s+");
            if (tok.length == 0) continue;
            if (tok[0].equalsIgnoreCase(".ORG") || tok[0].equalsIgnoreCase("ORG")) {
                if (tok.length > 1) addr = asmParseVal(tok[1]);
                continue;
            }
            if (tok[0].equalsIgnoreCase(".DP") || tok[0].equalsIgnoreCase(".MP")) continue;
            String first = tok[0];
            if (first.endsWith(":")) {
                asmAddLabel(first.substring(0, first.length()-1), addr);
                if (tok.length == 1) continue;
            }
            if (tok[0].equalsIgnoreCase(".WORD") || tok[0].equalsIgnoreCase("DATA")) {
                addr += tok.length - 1; continue;
            }
            // Count as 1 instruction word
            addr++;
        }

        // Pass 2: emit
        addr = baseAddr;
        for (String rawLine : lines) {
            String line = rawLine.split(";")[0].trim();
            if (line.isEmpty()) continue;
            String[] tok = line.split("[\\s,]+");
            if (tok.length == 0) continue;

            if (tok[0].equalsIgnoreCase(".ORG") || tok[0].equalsIgnoreCase("ORG")) {
                if (tok.length > 1) addr = asmParseVal(tok[1]);
                continue;
            }
            if (tok[0].equalsIgnoreCase(".DP") || tok[0].equalsIgnoreCase(".MP")) continue;

            int ti = 0;
            if (tok[ti].endsWith(":")) { ti++; if (ti >= tok.length) continue; }

            if (tok[ti].equalsIgnoreCase(".WORD") || tok[ti].equalsIgnoreCase("DATA")) {
                for (int i = ti+1; i < tok.length; i++)
                    if (addr < MEM_SIZE) mem[addr++] = asmParseVal(tok[i]);
                continue;
            }

            int mi = asmFindMnem(tok[ti]);
            if (mi < 0) continue;

            int word = MNEM_OPC[mi];
            if (MNEM_HAS_ADDR[mi] && tok.length > ti+1) {
                int val = asmParseVal(tok[ti+1]);
                if ((word & 0xF000) == 0x1000) // LAW — immediate
                    word |= (val & 0x7FF);
                else
                    word |= (val & ADDR_MASK);
            }
            if (addr < MEM_SIZE) mem[addr++] = word;
        }

        return addr - baseAddr;
    }
}
