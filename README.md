# Imlac PDS-1 Emulator — Android

Native Android app emulating the Imlac PDS-1

## What's emulated

**Main Processor (MP)**
- 16-bit word, 4096 words RAM
- Full instruction set: LAW JMP DAC XAM ISP ADD AND LDA JMS IOR RAL RAR IOT OPR
- Skip conditions: SKZ SKP SKL SKK SKD
- IOT devices: keyboard, display control, TTY, light pen, clock

**Display Processor (DP)**
- Separate 16-bit CPU running concurrently
- Registers: PC, AC, X, Y (1024×1024 coordinate space)
- Instructions: DLXA DLYA DSVH DLVH DJMP DJMS DHLT DRJM DEIM DVSF DPTS

**Built-in demos**
- STAR, LINES, LISSAJOUS, TEXT, BOUNCE, MAZE, SPACEWAR, SCOPE

**Rendering**
- Phosphor green CRT simulation (SurfaceView)
- Per-line glow effect (3 layers: core / inner glow / outer glow)
- Phosphor decay between frames
- Scanlines + vignette overlay

---

## How to build

### Option A — GitHub Actions (no PC needed)

1. Fork this repo on GitHub
2. Go to **Actions** tab
3. Click **Build Imlac PDS-1 APK** → **Run workflow**
4. Wait ~3 minutes
5. Download APK from **Artifacts**

### Option B — Android Studio

```
File → Open → select this folder
Build → Build Bundle(s)/APK(s) → Build APK(s)
```
Requires Android Studio Hedgehog or newer.

### Option C — Command line

```bash
# macOS / Linux
./gradlew assembleDebug

# Windows
gradlew.bat assembleDebug
```
Output: `app/build/outputs/apk/debug/app-debug.apk`

Requires: JDK 17+, Android SDK (auto-downloaded by Gradle if ANDROID_HOME not set).

### Option D — Termux on Android

```bash
pkg install openjdk-17 gradle

# Clone or copy project files, then:
cd ImlacPDS1
gradle assembleDebug
```

---

## Project structure

```
ImlacPDS1/
├── app/src/main/
│   ├── java/com/imlac/pds1/
│   │   ├── EmulatorActivity.java   — Main activity, UI, input
│   │   ├── Machine.java            — MP + DP emulator core
│   │   ├── CrtView.java            — SurfaceView phosphor renderer
│   │   └── Demos.java              — Built-in demo programs
│   ├── res/
│   │   ├── layout/activity_emulator.xml
│   │   ├── values/styles.xml
│   │   └── drawable/ic_launcher.xml
│   └── AndroidManifest.xml
├── .github/workflows/build.yml     — GitHub Actions CI
├── build.gradle
├── settings.gradle
└── gradlew
```

## Assembler

The emulator includes a two-pass assembler. Load programs at runtime
via `Machine.assemble(String src)`.

Example program:
```asm
        ORG     0050
START:  CLA             ; Clear accumulator
        LAW     42      ; Load 42
        DAC     RESULT  ; Store to memory
        HLT             ; Halt
RESULT: DATA    0
```

## Controls

| Button | Action |
|--------|--------|
| POWER | Power on, start MP |
| RESET | Reset all registers |
| RUN | Resume execution |
| HALT | Stop MP |
| STEP | Execute one instruction |
| Demo buttons | Load demo program |

Touch the CRT screen = light pen input.
Hardware keyboard maps to PDS-1 ASCII.

---

