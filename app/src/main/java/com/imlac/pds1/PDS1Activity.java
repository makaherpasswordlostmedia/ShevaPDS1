package com.imlac.pds1;

import org.libsdl.app.SDLActivity;

/**
 * Entry point Activity — replaces EmulatorActivity.
 *
 * Extends SDL2's SDLActivity, which handles all the native-window/surface
 * plumbing and invokes SDL_main() (see app/src/main/cpp/android_main.c) on
 * a dedicated thread once the surface is ready. All rendering — both the
 * PDS-1 CRT vector display and the on-screen control panel/dpad/keyboard/
 * chat UI — happens inside that native SDL2 loop now (ui_widgets.c),
 * instead of as a tree of Android Views.
 *
 * This class's only Java-side job is to own the long-lived emulation
 * objects (Machine, Demos, GameLoader, NetSession) exactly like
 * EmulatorActivity used to, and expose them to native code via JNI static
 * methods (see EmulatorBridge.java) so android_main.c's event loop can
 * call into them once per frame and on input events.
 */
public class PDS1Activity extends SDLActivity {

    private Machine    machine;
    private Demos      demos;
    private GameLoader gameLoader;
    private NetSession netSession;

    @Override
    protected String[] getLibraries() {
        // Order matters: SDL2 first, then our native lib that depends on it.
        return new String[] { "SDL2", "pds1native" };
    }

    @Override
    protected void onCreate(android.os.Bundle savedInstanceState) {
        // Construct the emulation core before SDL's native thread starts
        // asking for frames — mirrors EmulatorActivity.onCreate()'s
        // ordering (machine/demos created before crtView.setMachine()).
        machine    = new Machine();
        demos      = new Demos(machine);
        gameLoader = new GameLoader(this);

        EmulatorBridge.attach(this, machine, demos, gameLoader);

        super.onCreate(savedInstanceState);

        demos.setDemo(Demos.Type.STAR);
    }

    @Override
    protected void onDestroy() {
        EmulatorBridge.detach();
        if (netSession != null) netSession.stop();
        super.onDestroy();
    }

    public Machine getMachine() { return machine; }
    public Demos getDemos() { return demos; }
    public GameLoader getGameLoader() { return gameLoader; }

    public NetSession getOrCreateNetSession() {
        if (netSession == null) netSession = new NetSession(this);
        return netSession;
    }

    public void clearNetSession() {
        netSession = null;
    }

    // ── File picker (was EmulatorActivity.openFilePicker/onActivityResult) ──

    private static final int REQ_OPEN_FILE = 42;

    /** Called from EmulatorBridge.requestOpenFile(), itself invoked by the
     *  native "Load file" UI button. Runs on the UI thread. */
    public void launchFilePickerFromBridge() {
        android.content.Intent intent = new android.content.Intent(android.content.Intent.ACTION_GET_CONTENT);
        intent.setType("*/*");
        intent.addCategory(android.content.Intent.CATEGORY_OPENABLE);
        String[] mimeTypes = {"application/octet-stream", "text/plain", "text/x-asm"};
        intent.putExtra(android.content.Intent.EXTRA_MIME_TYPES, mimeTypes);
        startActivityForResult(
            android.content.Intent.createChooser(intent, "Open Imlac program (.rim .bin .hex .asm)"),
            REQ_OPEN_FILE);
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, android.content.Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode != REQ_OPEN_FILE || resultCode != RESULT_OK || data == null) return;

        android.net.Uri uri = data.getData();
        if (uri == null) return;

        byte[] bytes = readUri(uri);
        if (bytes == null) return;

        String filename = "unknown.bin";
        android.database.Cursor cursor = getContentResolver().query(uri, null, null, null, null);
        if (cursor != null) {
            int nameCol = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME);
            if (cursor.moveToFirst() && nameCol >= 0) filename = cursor.getString(nameCol);
            cursor.close();
        }

        EmulatorBridge.loadFileBytes(filename, bytes);
    }

    private byte[] readUri(android.net.Uri uri) {
        try {
            java.io.InputStream is = getContentResolver().openInputStream(uri);
            if (is == null) return null;
            java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream();
            byte[] buf = new byte[4096];
            int n;
            while ((n = is.read(buf)) != -1) out.write(buf, 0, n);
            is.close();
            return out.toByteArray();
        } catch (Exception e) {
            return null;
        }
    }
}
