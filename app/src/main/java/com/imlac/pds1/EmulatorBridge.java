package com.imlac.pds1;

import java.util.List;

/**
 * Static bridge between native code (android_main.c's event loop /
 * input_bridge.c / ui_widgets.c) and the Java-side emulation core
 * (Machine, Demos, GameLoader, NetSession, MazeWarGame, ...).
 *
 * This exists because the emulation core intentionally stayed in Java
 * (see stage 1's design note in CrtView.java) while the render loop and
 * UI moved to native SDL2. Every interaction that EmulatorActivity used
 * to wire up directly via Android View listeners — button clicks, dpad,
 * keyboard taps, demo selection, multiplayer host/join, file loading —
 * now happens as an SDL2 event inside android_main.c, which calls one of
 * the static methods below instead.
 *
 * All methods are static and operate on whatever Machine/Demos/etc. was
 * last attach()-ed by PDS1Activity.onCreate(), mirroring the
 * single-Activity, single-emulator-instance assumption the original app
 * already made (one CrtView per process).
 */
public final class EmulatorBridge {

    private static PDS1Activity activity;
    private static Machine    machine;
    private static Demos      demos;
    private static GameLoader gameLoader;

    private EmulatorBridge() { }

    public static void attach(PDS1Activity act, Machine m, Demos d, GameLoader gl) {
        activity   = act;
        machine    = m;
        demos      = d;
        gameLoader = gl;
    }

    public static void detach() {
        activity = null;
        machine = null;
        demos = null;
        gameLoader = null;
    }

    // ── Frame pump (called once per frame from android_main.c) ─────────

    /** Runs one emulation frame's worth of display-list building. Vector
     *  data is then read directly out of Machine's public arrays by
     *  jni_bridge.c's nativeSubmitVectors() call — no copy happens here. */
    public static void pumpFrame() {
        if (machine == null || demos == null) return;
        machine.dlClear();
        demos.runCurrentDemo();
    }

    public static Machine currentMachine() { return machine; }
    public static Demos currentDemos() { return demos; }

    // ── Light pen / touch input (was CrtView.screenToPDS + touch listener) ─

    public static void setLightPen(int pdsX, int pdsY, boolean hit) {
        if (machine == null) return;
        machine.lpen_x = pdsX;
        machine.lpen_y = pdsY;
        machine.lpen_hit = hit;
    }

    // ── Keyboard (was EmulatorActivity.onKeyDown/onKeyUp + virtual kbd) ──

    public static void keyDown(int asciiOrCode) {
        if (machine == null) return;
        machine.keyboard = asciiOrCode | 0x8000;
    }

    public static void keyUp() {
        if (machine == null) return;
        machine.keyboard = 0;
    }

    // ── Virtual controller (was ctrl[] array + K_UP..K_D in EmulatorActivity) ──

    public static void setControllerState(boolean up, boolean down, boolean left,
                                            boolean right, boolean a, boolean b,
                                            boolean c, boolean d) {
        if (machine == null) return;
        int key = 0;
        if (up) key = 'W'; else if (down) key = 'S';
        else if (left) key = 'A'; else if (right) key = 'D';
        else if (a) key = ' '; else if (b) key = 'F';
        else if (c) key = 'E'; else if (d) key = 'Q';
        machine.keyboard = (key != 0) ? (key | 0x8000) : 0;

        MazeWarGame mwg = demos != null ? demos.getMazeWarGame() : null;
        if (mwg != null) {
            mwg.iUp = up; mwg.iDown = down; mwg.iLeft = left; mwg.iRight = right;
            mwg.iFire = a || b;
        }
    }

    // ── Machine control (power/reset/run/halt/step — was btnPwr etc.) ───

    public static void powerOn()  { if (machine != null) machine.powerOn(); }
    public static void reset()    { if (machine != null) { machine.reset(); machine.mp_halt = false; machine.mp_run = true; } }
    public static void run()      { if (machine != null) { machine.mp_halt = false; machine.mp_run = true; } }
    public static void halt()     { if (machine != null) { machine.mp_halt = true;  machine.mp_run = false; } }
    public static void step()     { if (machine != null) { machine.mp_halt = false; machine.mpStep(); machine.mp_halt = true; } }
    public static boolean isHalted() { return machine == null || machine.mp_halt; }

    // ── Demo selection (was wireDemo()/btnSnake/btnMazewar) ─────────────

    public static void selectDemo(int demoTypeOrdinal) {
        if (demos == null || machine == null) return;
        Demos.Type[] types = Demos.Type.values();
        if (demoTypeOrdinal < 0 || demoTypeOrdinal >= types.length) return;
        demos.setDemo(types[demoTypeOrdinal]);
        machine.mp_halt = true;
    }

    public static String[] demoNames() {
        Demos.Type[] types = Demos.Type.values();
        String[] names = new String[types.length];
        for (int i = 0; i < types.length; i++) names[i] = types[i].name();
        return names;
    }

    // ── Register readouts (was tvPC/tvAC/... updater) ───────────────────

    public static int regPC()   { return machine == null ? 0 : machine.mp_pc; }
    public static int regAC()   { return machine == null ? 0 : machine.mp_ac; }
    public static int regIR()   { return machine == null ? 0 : machine.mp_ir; }
    public static int regLink() { return machine == null ? 0 : machine.mp_link; }
    public static int regDPX()  { return machine == null ? 0 : machine.dp_x; }
    public static int regDPY()  { return machine == null ? 0 : machine.dp_y; }

    // ── Game library (was GameLoader + showGameMenu()/showEditorDialog()) ─

    public static String[] gameNames() {
        if (gameLoader == null) return new String[0];
        List<GameLoader.Game> list = gameLoader.getGames();
        String[] names = new String[list.size()];
        for (int i = 0; i < list.size(); i++) names[i] = list.get(i).name;
        return names;
    }

    public static void runGameByName(String name) {
        if (gameLoader == null || machine == null || demos == null) return;
        GameLoader.Game g = gameLoader.findGame(name);
        if (g == null) return;
        machine.reset();
        machine.assemble(g.source);
        machine.mp_pc = 0x050;
        machine.mp_halt = false;
        machine.mp_run = true;
        demos.setDemo(Demos.Type.USER_ASM);
    }

    public static void saveGame(String name, String source, String desc) {
        if (gameLoader == null) return;
        gameLoader.saveGame(name, source, desc);
    }

    public static void deleteGame(String name) {
        if (gameLoader == null) return;
        gameLoader.deleteGame(name);
    }

    /** File-loading (was openFilePicker()/onActivityResult()). Native UI
     *  triggers the platform file picker via this call; result comes back
     *  through loadFileBytes() once the user picks something. */
    public static void requestOpenFile() {
        if (activity == null) return;
        activity.runOnUiThread(activity::launchFilePickerFromBridge);
    }

    public static void loadFileBytes(String filename, byte[] bytes) {
        if (machine == null || demos == null || bytes == null) return;
        machine.reset();
        java.util.Arrays.fill(machine.mem, 0);

        int startAddr = machine.loadAuto(filename, bytes);
        if (startAddr < 0) return;

        int dpStart = 0x100;
        if ((machine.mem[0x100] & 0xFFFF) == 0) {
            for (int a = 0x100; a < 0x400; a++) {
                if (machine.mem[a] != 0) { dpStart = a; break; }
            }
        }
        machine.dp_start = dpStart;
        machine.dp_pc = dpStart;
        machine.dp_halt = false;

        machine.dlClear();
        for (int i = 0; i < 8192 && !machine.dp_halt; i++) machine.dpStep();

        int word50 = machine.mem[0x050] & 0xFFFF;
        int opc50 = (word50 >> 12) & 0xF;
        boolean hasMP = word50 != 0 && opc50 != 1 && opc50 != 2 && opc50 != 4;
        if (hasMP) {
            machine.mp_pc = startAddr;
            machine.mp_halt = false;
            machine.mp_run = true;
        } else {
            machine.mp_halt = true;
            machine.mp_run = false;
        }
        demos.setDemo(Demos.Type.USER_ASM);
    }

    // ── Multiplayer (was wireMultiplayer()/startHost()/startJoin()/stopNet()) ─

    public static void netHost() {
        if (activity == null || demos == null || machine == null) return;
        NetSession ns = activity.getOrCreateNetSession();
        demos.setDemo(Demos.Type.MAZEWAR);
        machine.mp_halt = true; machine.mp_run = false;
        demos.initMazeWar();
        // hostMulti() registers itself as ns's EventListener.
        demos.getMazeWarGame().hostMulti(ns);
        long seed = (long)(Math.random() * 0xFFFFFFFFL);
        ns.host(seed);
    }

    public static void netJoin() {
        if (activity == null || demos == null || machine == null) return;
        NetSession ns = activity.getOrCreateNetSession();
        demos.setDemo(Demos.Type.MAZEWAR);
        machine.mp_halt = true; machine.mp_run = false;
        demos.initMazeWar();
        demos.getMazeWarGame().joinMulti(ns);
        ns.discover();
    }

    public static void netStop() {
        if (activity == null) return;
        // MazeWarGame.stopNet() already calls net.stop() internally.
        MazeWarGame mwg = demos != null ? demos.getMazeWarGame() : null;
        if (mwg != null) mwg.stopNet();
        activity.clearNetSession();
    }

    public static void netSendChat(String text) {
        if (activity == null) return;
        NetSession ns = activity.getOrCreateNetSession();
        if (ns.isConnected()) ns.sendChat(text);
    }

    /** Status string for the native chat/status panel, polled once per
     *  frame (native side has no push-callback mechanism from NetSession's
     *  background threads, so ui_widgets.c just reads this each frame). */
    public static String netStatusText() {
        if (activity == null) return "OFFLINE";
        NetSession ns = activity.getOrCreateNetSession();
        switch (ns.status) {
            case HOSTING:      return "HOSTING - waiting for guest...";
            case SEARCHING:    return "SEARCHING for host...";
            case CONNECTED:    return "CONNECTED - you are " + (ns.role == NetSession.Role.HOST ? "HOST" : "GUEST");
            case DISCONNECTED: return "DISCONNECTED";
            default:           return "OFFLINE";
        }
    }

    public static boolean netIsConnected() {
        if (activity == null) return false;
        return activity.getOrCreateNetSession().isConnected();
    }
}
