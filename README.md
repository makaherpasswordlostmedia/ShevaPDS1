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
