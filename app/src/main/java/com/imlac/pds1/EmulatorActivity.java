package com.imlac.pds1;

import android.app.Activity;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.View;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.TextView;

/**
 * Main Activity — wires together the Machine, Demos, and CrtView.
 * Runs the Main Processor on a background thread.
 * UI updates (registers) happen at 10Hz on the main thread.
 */
public class EmulatorActivity extends Activity {

    private Machine  machine;
    private Demos    demos;
    private CrtView  crtView;

    private Thread   mpThread;
    private volatile boolean mpRunning = false;

    private final Handler uiHandler = new Handler(Looper.getMainLooper());
    private Runnable regUpdater;

    // ── Lifecycle ────────────────────────────────────────────
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // Full screen immersive
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        getWindow().getDecorView().setSystemUiVisibility(
            View.SYSTEM_UI_FLAG_FULLSCREEN |
            View.SYSTEM_UI_FLAG_HIDE_NAVIGATION |
            View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY);

        setContentView(R.layout.activity_emulator);

        machine = new Machine();
        demos   = new Demos(machine);

        crtView = findViewById(R.id.crt_view);
        crtView.setMachine(machine, demos);

        // Touch → light pen
        crtView.setOnTouchListener((v, ev) -> {
            if (ev.getAction() == MotionEvent.ACTION_DOWN ||
                ev.getAction() == MotionEvent.ACTION_MOVE) {
                int[] pds = crtView.screenToPDS(ev.getX(), ev.getY());
                machine.lpen_x = pds[0];
                machine.lpen_y = pds[1];
                if (ev.getAction() == MotionEvent.ACTION_DOWN)
                    machine.lpen_hit = true;
            } else if (ev.getAction() == MotionEvent.ACTION_UP) {
                machine.lpen_hit = false;
            }
            return true;
        });

        wireButtons();
        startRegUpdater();

        // Boot: load star demo immediately
        demos.setDemo(Demos.Type.STAR);
    }

    @Override
    protected void onResume() {
        super.onResume();
        // Re-hide nav on resume
        getWindow().getDecorView().setSystemUiVisibility(
            View.SYSTEM_UI_FLAG_FULLSCREEN |
            View.SYSTEM_UI_FLAG_HIDE_NAVIGATION |
            View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY);
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        stopMP();
        uiHandler.removeCallbacks(regUpdater);
    }

    // ── Main Processor thread ─────────────────────────────────
    private void startMP() {
        stopMP();
        mpRunning = true;
        mpThread = new Thread(() -> {
            while (mpRunning) {
                if (!machine.mp_halt && machine.mp_run) {
                    // Run ~10000 cycles per burst, then yield
                    for (int i = 0; i < 10000 && !machine.mp_halt; i++) {
                        machine.mpStep();
                    }
                }
                try { Thread.sleep(1); } catch (InterruptedException e) { break; }
            }
        }, "imlac-mp");
        mpThread.setDaemon(true);
        mpThread.start();
    }

    private void stopMP() {
        mpRunning = false;
        if (mpThread != null) {
            try { mpThread.join(300); } catch (InterruptedException ignored) {}
        }
    }

    // ── Register display updater (10Hz) ───────────────────────
    private void startRegUpdater() {
        TextView regPC   = findViewById(R.id.reg_pc);
        TextView regAC   = findViewById(R.id.reg_ac);
        TextView regIR   = findViewById(R.id.reg_ir);
        TextView regLink = findViewById(R.id.reg_link);
        TextView regDPX  = findViewById(R.id.reg_dpx);
        TextView regDPY  = findViewById(R.id.reg_dpy);
        TextView status  = findViewById(R.id.status_text);

        regUpdater = new Runnable() {
            @Override public void run() {
                regPC  .setText(String.format("PC:%04X",  machine.mp_pc));
                regAC  .setText(String.format("AC:%04X",  machine.mp_ac));
                regIR  .setText(String.format("IR:%04X",  machine.mp_ir));
                regLink.setText(String.format("L:%d",     machine.mp_link));
                regDPX .setText(String.format("DX:%03X",  machine.dp_x));
                regDPY .setText(String.format("DY:%03X",  machine.dp_y));

                if (machine.mp_halt) {
                    status.setText("HALT");
                    status.setTextColor(0xFFFF3300);
                } else {
                    status.setText("RUN");
                    status.setTextColor(0xFF00FF41);
                }

                uiHandler.postDelayed(this, 100); // 10 Hz
            }
        };
        uiHandler.post(regUpdater);
    }

    // ── Button wiring ─────────────────────────────────────────
    private void wireButtons() {
        // Control buttons
        Button btnPower = findViewById(R.id.btn_power);
        Button btnReset = findViewById(R.id.btn_reset);
        Button btnRun   = findViewById(R.id.btn_run);
        Button btnHalt  = findViewById(R.id.btn_halt);
        Button btnStep  = findViewById(R.id.btn_step);

        btnPower.setOnClickListener(v -> {
            machine.powerOn();
            startMP();
        });

        btnReset.setOnClickListener(v -> {
            machine.reset();
            machine.mp_halt = false;
            machine.mp_run  = true;
        });

        btnRun.setOnClickListener(v -> {
            machine.mp_halt = false;
            machine.mp_run  = true;
            startMP();
        });

        btnHalt.setOnClickListener(v -> {
            machine.mp_halt = true;
            machine.mp_run  = false;
        });

        btnStep.setOnClickListener(v -> {
            machine.mp_halt = false;
            machine.mpStep();
            machine.mp_halt = true;
        });

        // Demo buttons
        wireDemo(R.id.btn_demo_star,       Demos.Type.STAR);
        wireDemo(R.id.btn_demo_lines,      Demos.Type.LINES);
        wireDemo(R.id.btn_demo_lissajous,  Demos.Type.LISSAJOUS);
        wireDemo(R.id.btn_demo_bounce,     Demos.Type.BOUNCE);
        wireDemo(R.id.btn_demo_maze,       Demos.Type.MAZE);
        wireDemo(R.id.btn_demo_spacewar,   Demos.Type.SPACEWAR);
    }

    private void wireDemo(int btnId, Demos.Type type) {
        Button b = findViewById(btnId);
        if (b == null) return;
        b.setOnClickListener(v -> {
            demos.setDemo(type);
            machine.mp_halt = true; // demos run independently
        });
    }

    // ── Hardware keyboard ─────────────────────────────────────
    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        // Map Android key codes to PDS-1 6-bit ASCII
        int ascii = 0;
        switch (keyCode) {
            case KeyEvent.KEYCODE_A: ascii = 'A'; break;
            case KeyEvent.KEYCODE_B: ascii = 'B'; break;
            case KeyEvent.KEYCODE_C: ascii = 'C'; break;
            case KeyEvent.KEYCODE_D: ascii = 'D'; break;
            case KeyEvent.KEYCODE_E: ascii = 'E'; break;
            case KeyEvent.KEYCODE_F: ascii = 'F'; break;
            case KeyEvent.KEYCODE_G: ascii = 'G'; break;
            case KeyEvent.KEYCODE_H: ascii = 'H'; break;
            case KeyEvent.KEYCODE_I: ascii = 'I'; break;
            case KeyEvent.KEYCODE_J: ascii = 'J'; break;
            case KeyEvent.KEYCODE_K: ascii = 'K'; break;
            case KeyEvent.KEYCODE_L: ascii = 'L'; break;
            case KeyEvent.KEYCODE_M: ascii = 'M'; break;
            case KeyEvent.KEYCODE_N: ascii = 'N'; break;
            case KeyEvent.KEYCODE_O: ascii = 'O'; break;
            case KeyEvent.KEYCODE_P: ascii = 'P'; break;
            case KeyEvent.KEYCODE_Q: ascii = 'Q'; break;
            case KeyEvent.KEYCODE_R: ascii = 'R'; break;
            case KeyEvent.KEYCODE_S: ascii = 'S'; break;
            case KeyEvent.KEYCODE_T: ascii = 'T'; break;
            case KeyEvent.KEYCODE_U: ascii = 'U'; break;
            case KeyEvent.KEYCODE_V: ascii = 'V'; break;
            case KeyEvent.KEYCODE_W: ascii = 'W'; break;
            case KeyEvent.KEYCODE_X: ascii = 'X'; break;
            case KeyEvent.KEYCODE_Y: ascii = 'Y'; break;
            case KeyEvent.KEYCODE_Z: ascii = 'Z'; break;
            case KeyEvent.KEYCODE_0: ascii = '0'; break;
            case KeyEvent.KEYCODE_1: ascii = '1'; break;
            case KeyEvent.KEYCODE_2: ascii = '2'; break;
            case KeyEvent.KEYCODE_3: ascii = '3'; break;
            case KeyEvent.KEYCODE_4: ascii = '4'; break;
            case KeyEvent.KEYCODE_5: ascii = '5'; break;
            case KeyEvent.KEYCODE_6: ascii = '6'; break;
            case KeyEvent.KEYCODE_7: ascii = '7'; break;
            case KeyEvent.KEYCODE_8: ascii = '8'; break;
            case KeyEvent.KEYCODE_9: ascii = '9'; break;
            case KeyEvent.KEYCODE_SPACE:     ascii = ' ';  break;
            case KeyEvent.KEYCODE_ENTER:     ascii = '\r'; break;
            case KeyEvent.KEYCODE_DEL:       ascii = 0x08; break;
            case KeyEvent.KEYCODE_ESCAPE:    ascii = 0x1B; break;
            default:
                return super.onKeyDown(keyCode, event);
        }
        machine.keyboard = ascii | 0x8000; // flag: key ready
        return true;
    }

    @Override
    public boolean onKeyUp(int keyCode, KeyEvent event) {
        machine.keyboard = 0;
        return super.onKeyUp(keyCode, event);
    }
}
