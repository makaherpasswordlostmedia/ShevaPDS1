package com.imlac.pds1;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.*;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.*;
import android.view.inputmethod.EditorInfo;
import android.widget.EditText;
import android.widget.Toast;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.util.Arrays;
import java.util.ArrayDeque;
import java.util.Deque;
import android.view.ViewGroup;
import android.widget.*;
import java.util.List;

public class EmulatorActivity extends Activity {

    private Machine    machine;
    private Demos      demos;
    private CrtView    crtView;
    private GameLoader gameLoader;

    private Thread   mpThread;
    private volatile boolean mpRunning = false;

    private final Handler uiHandler = new Handler(Looper.getMainLooper());
    private TextView tvPC, tvAC, tvIR, tvLink, tvDPX, tvDPY, tvStatus, tvFps;
    private SeekBar  sbFps;
    private int      targetFps = 30;
    private boolean  keyboardVisible = false;
    private NetSession netSession = null;
    private final Deque<String> chatLines = new ArrayDeque<>();
    private static final int CHAT_MAX = 6;
    private int  lastPeerDemo = -1;  // for demo sync detection
    private int  syncSendCd   = 0;
    private boolean  kbdKeyHeld = false;  // for auto-release

    // Virtual controller
    private final boolean[] ctrl = new boolean[8];
    private static final int K_UP=0,K_DN=1,K_LT=2,K_RT=3,K_A=4,K_B=5,K_C=6,K_D=7;

    private static final int REQ_OPEN_FILE = 42;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        requestWindowFeature(Window.FEATURE_NO_TITLE);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON |
                             WindowManager.LayoutParams.FLAG_FULLSCREEN);
        hideSystemUI();
        setContentView(R.layout.activity_emulator);

        machine    = new Machine();
        demos      = new Demos(machine);
        gameLoader = new GameLoader(this);

        crtView = findViewById(R.id.crt_view);
        crtView.setMachine(machine, demos);
        crtView.setMaxFps(30);

        findViews();
        wireControlPanel();
        wireVirtualController();
        wireGameMenu();
        wireKeyboard();
        wireToggleInput();
        wireMultiplayer();
        wireChat();
        startRegUpdater();

        crtView.setOnTouchListener((v, ev) -> {
            int[] p = crtView.screenToPDS(ev.getX(), ev.getY());
            machine.lpen_x = p[0]; machine.lpen_y = p[1];
            machine.lpen_hit = (ev.getAction() != MotionEvent.ACTION_UP);
            return true;
        });

        demos.setDemo(Demos.Type.STAR);
    }

    @Override protected void onResume()  { super.onResume(); hideSystemUI(); }
    @Override protected void onDestroy() { super.onDestroy(); stopMP(); uiHandler.removeCallbacksAndMessages(null); }

    private void hideSystemUI() {
        getWindow().getDecorView().setSystemUiVisibility(
            View.SYSTEM_UI_FLAG_FULLSCREEN         |
            View.SYSTEM_UI_FLAG_HIDE_NAVIGATION    |
            View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY   |
            View.SYSTEM_UI_FLAG_LAYOUT_STABLE      |
            View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN  |
            View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION);
    }

    private void findViews() {
        tvPC   = findViewById(R.id.reg_pc);
        tvAC   = findViewById(R.id.reg_ac);
        tvIR   = findViewById(R.id.reg_ir);
        tvLink = findViewById(R.id.reg_link);
        tvDPX  = findViewById(R.id.reg_dpx);
        tvDPY  = findViewById(R.id.reg_dpy);
        tvStatus = findViewById(R.id.status_text);
        tvFps  = findViewById(R.id.tv_fps);
        sbFps  = findViewById(R.id.sb_fps);
    }

    private void startRegUpdater() {
        uiHandler.postDelayed(new Runnable() {
            @Override public void run() {
                if (tvPC == null) return;
                tvPC  .setText(String.format("PC:%04X", machine.mp_pc));
                tvAC  .setText(String.format("AC:%04X", machine.mp_ac));
                tvIR  .setText(String.format("IR:%04X", machine.mp_ir));
                tvLink.setText(String.format("L:%d",    machine.mp_link));
                tvDPX .setText(String.format("DX:%03X", machine.dp_x));
                tvDPY .setText(String.format("DY:%03X", machine.dp_y));
                tvStatus.setText(machine.mp_halt ? "HALT" : "RUN ");
                tvStatus.setTextColor(machine.mp_halt ? 0xFFFF3300 : 0xFF00FF41);
                if (tvFps != null) tvFps.setText(String.format("%.0f/"+targetFps+"fps", crtView.getActualFps()));
                uiHandler.postDelayed(this, 100);
            }
        }, 100);
    }

    private void startMP() {
        stopMP();
        mpRunning = true;
        mpThread = new Thread(() -> {
            while (mpRunning) {
                // ALWAYS update keyboard from controller (even when MP halted)
                int key = 0;
                if (ctrl[K_UP]) key='W'; else if (ctrl[K_DN]) key='S';
                else if (ctrl[K_LT]) key='A'; else if (ctrl[K_RT]) key='D';
                else if (ctrl[K_A])  key=' '; else if (ctrl[K_B])  key='F';
                else if (ctrl[K_C])  key='E'; else if (ctrl[K_D])  key='Q';
                machine.keyboard = (key!=0) ? (key|0x8000) : 0;
                // Send sync to peer every ~10 frames
                if (netSession != null && netSession.isConnected()) {
                    if (syncSendCd <= 0) {
                        int demoIdx = demos == null ? 0 : demos.currentDemoIndex();
                        netSession.sendSync(demoIdx, machine.keyboard);
                        syncSendCd = 10;
                    } else syncSendCd--;
                }
                // Also push directly into MazeWarGame input fields
                if (demos != null) {
                    MazeWarGame mwg = demos.getMazeWarGame();
                    if (mwg != null) {
                        mwg.iUp    = ctrl[K_UP];
                        mwg.iDown  = ctrl[K_DN];
                        mwg.iLeft  = ctrl[K_LT];
                        mwg.iRight = ctrl[K_RT];
                        mwg.iFire  = ctrl[K_A] || ctrl[K_B];
                    }
                }

                // Run MP only when not halted
                if (!machine.mp_halt && machine.mp_run) {
                    for (int i = 0; i < 10000 && !machine.mp_halt; i++)
                        machine.mpStep();
                }
                try { Thread.sleep(16); } catch (InterruptedException e) { break; }
            }
        }, "imlac-mp");
        mpThread.setDaemon(true);
        mpThread.start();
    }

    private void stopMP() {
        mpRunning = false;
        if (mpThread != null) try { mpThread.join(300); } catch (InterruptedException ignored) {}
    }

    private void wireControlPanel() {
        Button btnPwr  = findViewById(R.id.btn_power);
        Button btnRst  = findViewById(R.id.btn_reset);
        Button btnRun  = findViewById(R.id.btn_run);
        Button btnHalt = findViewById(R.id.btn_halt);
        Button btnStep = findViewById(R.id.btn_step);

        if (btnPwr  != null) btnPwr .setOnClickListener(v -> { machine.powerOn(); startMP(); });
        if (btnRst  != null) btnRst .setOnClickListener(v -> { machine.reset(); machine.mp_halt=false; machine.mp_run=true; });
        if (btnRun  != null) btnRun .setOnClickListener(v -> { machine.mp_halt=false; machine.mp_run=true; startMP(); });
        if (btnHalt != null) btnHalt.setOnClickListener(v -> { machine.mp_halt=true; machine.mp_run=false; });
        if (btnStep != null) btnStep.setOnClickListener(v -> { machine.mp_halt=false; machine.mpStep(); machine.mp_halt=true; });

        if (sbFps != null) {
            sbFps.setMax(59);
            sbFps.setProgress(29);
            sbFps.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
                public void onProgressChanged(SeekBar s, int p, boolean u) {
                    targetFps = p+1;
                    crtView.setMaxFps(targetFps);
                }
                public void onStartTrackingTouch(SeekBar s) {}
                public void onStopTrackingTouch(SeekBar s)  {}
            });
        }

        wireDemo(R.id.btn_demo_star,      Demos.Type.STAR);
        wireDemo(R.id.btn_demo_lines,     Demos.Type.LINES);
        wireDemo(R.id.btn_demo_lissajous, Demos.Type.LISSAJOUS);
        wireDemo(R.id.btn_demo_bounce,    Demos.Type.BOUNCE);
        wireDemo(R.id.btn_demo_maze,      Demos.Type.MAZE);
        wireDemo(R.id.btn_demo_spacewar,  Demos.Type.SPACEWAR);
        Button btnSnake = findViewById(R.id.btn_snake);
        if (btnSnake != null) btnSnake.setOnClickListener(v -> {
            demos.setDemo(Demos.Type.SNAKE);
            machine.mp_halt = true;
            machine.mp_run  = false;
            startMP();
        });
        Button btnMW = findViewById(R.id.btn_mazewar);
        if (btnMW != null) btnMW.setOnClickListener(v -> {
            demos.setDemo(Demos.Type.MAZEWAR);
            machine.mp_halt = true;   // MP doesn't execute user code
            machine.mp_run  = false;
            startMP();                // but thread must run to pump keyboard
        });
    }

    private void wireDemo(int id, Demos.Type type) {
        Button b = findViewById(id);
        if (b!=null) b.setOnClickListener(v -> { demos.setDemo(type); machine.mp_halt=true; });
    }

    @SuppressWarnings("ClickableViewAccessibility")
    private void wireVirtualController() {
        wireDpad(R.id.dp_up,    K_UP);
        wireDpad(R.id.dp_down,  K_DN);
        wireDpad(R.id.dp_left,  K_LT);
        wireDpad(R.id.dp_right, K_RT);
        wireDpad(R.id.btn_a,    K_A);
        wireDpad(R.id.btn_b,    K_B);
        wireDpad(R.id.btn_c,    K_C);
        wireDpad(R.id.btn_d,    K_D);
    }

    @SuppressWarnings("ClickableViewAccessibility")
    private void wireDpad(int id, int ki) {
        View v = findViewById(id);
        if (v == null) return;
        v.setOnTouchListener((vv, ev) -> {
            switch (ev.getActionMasked()) {
                case MotionEvent.ACTION_DOWN:
                case MotionEvent.ACTION_MOVE:
                    ctrl[ki] = true;
                    vv.setAlpha(0.45f);
                    break;
                case MotionEvent.ACTION_UP:
                case MotionEvent.ACTION_POINTER_UP:
                case MotionEvent.ACTION_CANCEL:
                default:
                    ctrl[ki] = false;
                    vv.setAlpha(1.0f);
                    break;
            }
            return true;
        });
    }

    private void wireGameMenu() {
        Button b = findViewById(R.id.btn_games);
        if (b!=null) b.setOnClickListener(v -> showGameMenu());
    }

    private void showGameMenu() {
        List<GameLoader.Game> list = gameLoader.getGames();
        String[] items = new String[list.size() + 4];
        items[0] = "📂 Load file (.rim/.bin/.hex/.asm)";
        items[1] = "+ New game (assembly editor)";
        items[2] = "Example: Counter";
        items[3] = "Example: Draw Box";
        for (int i = 0; i < list.size(); i++) items[i + 4] = list.get(i).name;

        new AlertDialog.Builder(this)
            .setTitle("Games / Programs")
            .setItems(items, (d, w) -> {
                if      (w == 0) openFilePicker();
                else if (w == 1) showEditorDialog(null);
                else if (w == 2) showEditorDialog(new GameLoader.Game("counter", GameLoader.EXAMPLE_COUNTER, "Binary counter"));
                else if (w == 3) showEditorDialog(new GameLoader.Game("drawbox", GameLoader.EXAMPLE_DRAW_BOX, "Draw a box"));
                else showGameOptions(list.get(w - 4));
            })
            .setNegativeButton("Close", null).show();
    }

    private void openFilePicker() {
        Intent intent = new Intent(Intent.ACTION_GET_CONTENT);
        intent.setType("*/*");
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        // Show common Imlac file types in description
        String[] mimeTypes = {"application/octet-stream", "text/plain", "text/x-asm"};
        intent.putExtra(Intent.EXTRA_MIME_TYPES, mimeTypes);
        startActivityForResult(Intent.createChooser(intent, "Open Imlac program (.rim .bin .hex .asm)"), REQ_OPEN_FILE);
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode != REQ_OPEN_FILE || resultCode != RESULT_OK || data == null) return;

        Uri uri = data.getData();
        if (uri == null) return;

        // Read file bytes
        byte[] bytes = readUri(uri);
        if (bytes == null) {
            Toast.makeText(this, "Cannot read file", Toast.LENGTH_SHORT).show();
            return;
        }

        // Get filename for format detection
        String filename = "unknown.bin";
        android.database.Cursor cursor = getContentResolver().query(uri, null, null, null, null);
        if (cursor != null) {
            int nameCol = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME);
            if (cursor.moveToFirst() && nameCol >= 0) filename = cursor.getString(nameCol);
            cursor.close();
        }

        loadFileIntoMachine(filename, bytes);
    }

    private byte[] readUri(Uri uri) {
        try {
            InputStream is = getContentResolver().openInputStream(uri);
            if (is == null) return null;
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] buf = new byte[4096];
            int n;
            while ((n = is.read(buf)) != -1) out.write(buf, 0, n);
            is.close();
            return out.toByteArray();
        } catch (Exception e) {
            return null;
        }
    }

    private void loadFileIntoMachine(String filename, byte[] bytes) {
        machine.reset();
        // Clear memory completely before loading
        java.util.Arrays.fill(machine.mem, 0);

        int startAddr = machine.loadAuto(filename, bytes);

        if (startAddr < 0) {
            Toast.makeText(this, "Unknown format: " + filename, Toast.LENGTH_LONG).show();
            return;
        }

        // Find DP program start: first non-zero address >= 0x100 with DP opcode
        int dpStart = 0x100;
        for (int a = 0x100; a < 0x200; a++) {
            int w = machine.mem[a] & 0xFFFF;
            int op = (w >> 12) & 0xF;
            if (w != 0 && (op == 1 || op == 2 || op == 4 || op == 3 || op == 8)) {
                dpStart = a; break;
            }
        }
        machine.dp_start = dpStart;
        machine.dp_pc    = dpStart;
        machine.dp_halt  = false;

        // MP: only start if there's a real MP program (not just DP code at 0x050)
        int word50 = machine.mem[0x050] & 0xFFFF;
        int opc50  = (word50 >> 12) & 0xF;
        boolean hasMP = word50 != 0 && opc50 != 1 && opc50 != 2 && opc50 != 4;
        if (hasMP) {
            machine.mp_pc   = startAddr;
            machine.mp_halt = false;
            machine.mp_run  = true;
            startMP();
        } else {
            machine.mp_halt = true;
            machine.mp_run  = false;
        }

        demos.setDemo(Demos.Type.USER_ASM);

        String name = filename.length() > 20 ? filename.substring(0, 20) : filename;
        Toast.makeText(this,
            "Loaded: " + name + "\nDP:" + String.format("%04X", dpStart)
            + (hasMP ? "  MP:" + String.format("%04X", startAddr) : "  (DP only)")
            + "  " + bytes.length + "b",
            Toast.LENGTH_LONG).show();
    }

    private void showGameOptions(GameLoader.Game g) {
        new AlertDialog.Builder(this)
            .setTitle(g.name)
            .setMessage(g.desc.isEmpty() ? "(no description)" : g.desc)
            .setPositiveButton("Run",    (d,w) -> runGame(g))
            .setNeutralButton ("Edit",   (d,w) -> showEditorDialog(g))
            .setNegativeButton("Delete", (d,w) -> { gameLoader.deleteGame(g.name); })
            .show();
    }

    private void showEditorDialog(GameLoader.Game existing) {
        View dlgView = getLayoutInflater().inflate(R.layout.dialog_editor, null);
        EditText etName   = dlgView.findViewById(R.id.et_name);
        EditText etDesc   = dlgView.findViewById(R.id.et_desc);
        EditText etSource = dlgView.findViewById(R.id.et_source);

        if (existing!=null) {
            etName  .setText(existing.name);
            etDesc  .setText(existing.desc);
            etSource.setText(existing.source);
        } else {
            etSource.setText("; Imlac PDS-1 Assembly\n; WASD=move  SPACE=fire\n\n        ORG 0050\nSTART:  NOP\n        JMP START\n");
        }

        new AlertDialog.Builder(this)
            .setTitle(existing==null ? "New Game" : "Edit: "+existing.name)
            .setView(dlgView)
            .setPositiveButton("Save & Run", (d,w) -> {
                String name = etName.getText().toString().trim();
                if (name.isEmpty()) name="untitled";
                gameLoader.saveGame(name, etSource.getText().toString(), etDesc.getText().toString());
                GameLoader.Game saved = gameLoader.findGame(name);
                if (saved!=null) runGame(saved);
            })
            .setNeutralButton("Save only", (d,w) -> {
                String name = etName.getText().toString().trim();
                if (name.isEmpty()) name="untitled";
                gameLoader.saveGame(name, etSource.getText().toString(), etDesc.getText().toString());
                Toast.makeText(this,"Saved",Toast.LENGTH_SHORT).show();
            })
            .setNegativeButton("Cancel",null).show();
    }

    private void runGame(GameLoader.Game g) {
        machine.reset();
        int words = machine.assemble(g.source);
        machine.mp_pc = 0x050;
        machine.mp_halt = false;
        machine.mp_run  = true;
        demos.setDemo(Demos.Type.USER_ASM);
        startMP();
        Toast.makeText(this, g.name+" ("+words+" words)", Toast.LENGTH_SHORT).show();
    }

    // ── Multiplayer buttons ───────────────────────────────────
    private void wireMultiplayer() {
        Button btnHost   = findViewById(R.id.btn_host);
        Button btnJoin   = findViewById(R.id.btn_join);
        Button btnCancel = findViewById(R.id.btn_netcancel);

        if (btnHost != null) btnHost.setOnClickListener(v -> startHost());
        if (btnJoin != null) btnJoin.setOnClickListener(v -> startJoin());
        if (btnCancel != null) btnCancel.setOnClickListener(v -> stopNet());
    }

    private void startHost() {
        if (netSession != null) netSession.stop();
        netSession = new NetSession(this);
        netSession.setChatListener((from, msg) -> runOnUiThread(() -> addChat(from+": "+msg)));
        netSession.setEventListener(makeEventListener());
        demos.setDemo(Demos.Type.MAZEWAR);
        machine.mp_halt = true; machine.mp_run = false; startMP();
        demos.initMazeWar();
        long seed = (long)(Math.random() * 0xFFFFFFFFL);
        demos.getMazeWarGame().hostMulti(netSession);  // sets listener
        netSession.host(seed);  // starts network, onConnected will fire with seed
        setNetStatus("⚡ HOSTING — waiting for guest...");
        showChatPanel(true);
        addChat("SYS: hosting on port " + NetSession.PORT_GAME);
        Toast.makeText(this, "Hosting — waiting for guest", Toast.LENGTH_SHORT).show();
    }

    private void startJoin() {
        if (netSession != null) netSession.stop();
        netSession = new NetSession(this);
        netSession.setChatListener((from, msg) -> runOnUiThread(() -> addChat(from+": "+msg)));
        netSession.setEventListener(makeEventListener());
        demos.setDemo(Demos.Type.MAZEWAR);
        machine.mp_halt = true; machine.mp_run = false; startMP();
        demos.initMazeWar();
        demos.getMazeWarGame().joinMulti(netSession);  // sets listener
        netSession.discover();  // starts searching
        setNetStatus("🔍 SEARCHING for host...");
        showChatPanel(true);
        addChat("SYS: searching for host...");
        Toast.makeText(this, "Searching for host...", Toast.LENGTH_SHORT).show();
    }

    private void stopNet() {
        if (netSession != null) { netSession.stop(); netSession = null; }
        MazeWarGame mwg = demos.getMazeWarGame();
        if (mwg != null) mwg.stopNet();
        setNetStatus("● OFFLINE");
        showChatPanel(false);
        addChat("SYS: disconnected");
    }

    private NetSession.EventListener makeEventListener() {
        return new NetSession.EventListener() {
            @Override public void onConnected(boolean asHost, long seed) {
                runOnUiThread(() -> {
                    setNetStatus(asHost ? "✓ CONNECTED — you are HOST" : "✓ CONNECTED — you are GUEST");
                    addChat("SYS: connected! " + (asHost?"you=HOST":"you=GUEST"));
                });
            }
            @Override public void onPeerSync(int demoIdx, int keyboard) {
                // Show what demo peer is running (optional future: mirror it)
                if (demoIdx != lastPeerDemo) {
                    lastPeerDemo = demoIdx;
                    runOnUiThread(() -> addChat("OPP switched demo: " + demoIdx));
                }
            }
            @Override public void onPeerMazeState(int x,int y,int dir,int hp,int sc) {
                // handled inside MazeWarGame
            }
            @Override public void onPeerBullet(int dir) { /* handled in MazeWarGame */ }
            @Override public void onPeerKilled()        { /* handled in MazeWarGame */ }
            @Override public void onDisconnected() {
                runOnUiThread(() -> {
                    setNetStatus("✕ DISCONNECTED");
                    addChat("SYS: peer disconnected");
                    Toast.makeText(EmulatorActivity.this, "Peer disconnected", Toast.LENGTH_SHORT).show();
                });
            }
        };
    }

    // ── Chat ──────────────────────────────────────────────────
    private void wireChat() {
        Button btnSend = findViewById(R.id.btn_chat_send);
        EditText etChat = findViewById(R.id.et_chat);
        if (btnSend == null || etChat == null) return;

        Runnable doSend = () -> {
            String txt = etChat.getText().toString().trim();
            if (!txt.isEmpty() && netSession != null && netSession.isConnected()) {
                netSession.sendChat(txt);
                etChat.setText("");
            } else if (!txt.isEmpty()) {
                addChat("SYS: not connected");
                etChat.setText("");
            }
        };

        btnSend.setOnClickListener(v -> doSend.run());
        etChat.setOnEditorActionListener((v, actionId, event) -> {
            if (actionId == EditorInfo.IME_ACTION_SEND
                    || actionId == EditorInfo.IME_ACTION_DONE) {
                doSend.run(); return true;
            }
            return false;
        });
    }

    private void addChat(String line) {
        chatLines.addLast(line);
        while (chatLines.size() > CHAT_MAX) chatLines.removeFirst();
        TextView tv = findViewById(R.id.tv_chat_log);
        if (tv == null) return;
        StringBuilder sb = new StringBuilder();
        for (String l : chatLines) { if (sb.length()>0) sb.append("\n"); sb.append(l); }
        tv.setText(sb.toString());
    }

    private void setNetStatus(String s) {
        runOnUiThread(() -> {
            TextView tv = findViewById(R.id.tv_net_status);
            if (tv != null) tv.setText(s);
        });
    }

    private void showChatPanel(boolean show) {
        runOnUiThread(() -> {
            View p = findViewById(R.id.panel_chat);
            if (p != null) p.setVisibility(show ? View.VISIBLE : View.GONE);
        });
    }

    // ── Toggle Controller / Keyboard ─────────────────────────
    private void wireToggleInput() {
        Button btn = findViewById(R.id.btn_toggle_input);
        if (btn == null) return;
        btn.setOnClickListener(v -> {
            keyboardVisible = !keyboardVisible;
            View panelCtrl = findViewById(R.id.panel_controller);
            View panelKbd  = findViewById(R.id.panel_keyboard);
            TextView tvMode = findViewById(R.id.tv_input_mode);
            TextView tvHint = findViewById(R.id.tv_input_hint);
            if (keyboardVisible) {
                panelCtrl.setVisibility(View.GONE);
                panelKbd .setVisibility(View.VISIBLE);
                btn.setText("🕹 PAD");
                if (tvMode != null) tvMode.setText("KEYBOARD");
                if (tvHint != null) tvHint.setText("tap key → sent to machine  |  auto-release 150ms");
            } else {
                panelCtrl.setVisibility(View.VISIBLE);
                panelKbd .setVisibility(View.GONE);
                btn.setText("⌨ KBD");
                if (tvMode != null) tvMode.setText("CONTROLLER");
                if (tvHint != null) tvHint.setText("A=SPACE  B=F  C=E  D=Q  |  ▲▼◀▶=WASD");
            }
        });
    }

    // ── Virtual Keyboard ──────────────────────────────────────
    // Maps view id → ASCII character sent to machine.keyboard
    private static final int[][] KBD_MAP = {
        {R.id.k_1,'1'},{R.id.k_2,'2'},{R.id.k_3,'3'},{R.id.k_4,'4'},{R.id.k_5,'5'},
        {R.id.k_6,'6'},{R.id.k_7,'7'},{R.id.k_8,'8'},{R.id.k_9,'9'},{R.id.k_0,'0'},
        {R.id.k_q,'Q'},{R.id.k_w,'W'},{R.id.k_e,'E'},{R.id.k_r,'R'},{R.id.k_t,'T'},
        {R.id.k_y,'Y'},{R.id.k_u,'U'},{R.id.k_i,'I'},{R.id.k_o,'O'},{R.id.k_p,'P'},
        {R.id.k_a,'A'},{R.id.k_s,'S'},{R.id.k_d,'D'},{R.id.k_f,'F'},{R.id.k_g,'G'},
        {R.id.k_h,'H'},{R.id.k_j,'J'},{R.id.k_k,'K'},{R.id.k_l,'L'},
        {R.id.k_z,'Z'},{R.id.k_x,'X'},{R.id.k_c,'C'},{R.id.k_v,'V'},{R.id.k_b,'B'},
        {R.id.k_n,'N'},{R.id.k_m,'M'},
        {R.id.k_sp,' '},{R.id.k_ent,13},{R.id.k_bs,8},{R.id.k_esc,27},
    };

    @SuppressWarnings("ClickableViewAccessibility")
    private void wireKeyboard() {
        for (int[] pair : KBD_MAP) {
            int id = pair[0];
            int ascii = pair[1];
            View v = findViewById(id);
            if (v == null) continue;
            v.setOnTouchListener((vv, ev) -> {
                if (ev.getAction() == MotionEvent.ACTION_DOWN) {
                    machine.keyboard = ascii | 0x8000;
                    vv.setAlpha(0.4f);
                    // Auto-release after 150ms
                    uiHandler.postDelayed(() -> {
                        machine.keyboard = 0;
                        vv.setAlpha(1.0f);
                    }, 150);
                }
                return true;
            });
        }
    }

    @Override public boolean onKeyDown(int kc, KeyEvent ev) {
        int a = keyToAscii(kc);
        if (a!=0) { machine.keyboard=a|0x8000; return true; }
        return super.onKeyDown(kc,ev);
    }
    @Override public boolean onKeyUp(int kc, KeyEvent ev) {
        machine.keyboard=0; return super.onKeyUp(kc,ev);
    }
    private int keyToAscii(int kc) {
        if (kc>=KeyEvent.KEYCODE_A&&kc<=KeyEvent.KEYCODE_Z) return 'A'+(kc-KeyEvent.KEYCODE_A);
        if (kc>=KeyEvent.KEYCODE_0&&kc<=KeyEvent.KEYCODE_9) return '0'+(kc-KeyEvent.KEYCODE_0);
        switch(kc){
            case KeyEvent.KEYCODE_SPACE: return ' ';
            case KeyEvent.KEYCODE_ENTER: return '\r';
            case KeyEvent.KEYCODE_DEL:   return 8;
            case KeyEvent.KEYCODE_DPAD_UP:    return 'W';
            case KeyEvent.KEYCODE_DPAD_DOWN:  return 'S';
            case KeyEvent.KEYCODE_DPAD_LEFT:  return 'A';
            case KeyEvent.KEYCODE_DPAD_RIGHT: return 'D';
        }
        return 0;
    }
}
