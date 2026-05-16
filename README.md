# 🕹️ VGA Pong — Altera DE2 FPGA

A fully hardware-implemented, two-player Pong game running on the **Altera DE2 development board** (Cyclone II FPGA). Written in synthesisable Verilog, it drives a **640×480 @ 60 Hz VGA display** with zero CPU or soft-processor involvement — all game logic, VGA timing, pixel rendering, and scorekeeping are done entirely in RTL.

---

## 📋 Table of Contents

- [Overview](#overview)
- [Hardware Requirements](#hardware-requirements)
- [Project Structure](#project-structure)
- [Architecture](#architecture)
  - [1. Pixel Clock Generation](#1-pixel-clock-generation)
  - [2. VGA Timing Controller](#2-vga-timing-controller)
  - [3. Frame Tick Generator](#3-frame-tick-generator)
  - [4. Input Debounce Logic](#4-input-debounce-logic)
  - [5. Game Logic FSM](#5-game-logic-fsm)
  - [6. Pixel Renderer](#6-pixel-renderer)
  - [7. Colour Mixer](#7-colour-mixer)
- [I/O Pin Mapping](#io-pin-mapping)
- [Controls](#controls)
- [Game Rules](#game-rules)
- [Building & Flashing](#building--flashing)
- [Design Notes](#design-notes)

---

## Overview

| Parameter | Value |
|-----------|-------|
| **Target Device** | Altera DE2 — Cyclone II `EP2C35F672C6` |
| **EDA Tool** | Intel Quartus II 13.0 SP1 (64-bit) |
| **System Clock** | 50 MHz (`CLOCK_50`) |
| **VGA Resolution** | 640 × 480 @ 60 Hz |
| **Pixel Clock** | 25 MHz (derived by clock-enable toggle) |
| **HDL** | Verilog (single-file, fully synthesisable) |
| **Top-Level Module** | `vga_pong` |
| **Win Condition** | First to **7 points** |

---

## Hardware Requirements

- **Altera DE2 Development Board** (Cyclone II EP2C35F672C6N)
- VGA monitor with a 15-pin D-Sub connector
- VGA cable
- USB-Blaster or compatible JTAG programmer
- Intel/Altera **Quartus II 13.x** (Web Edition is sufficient)

---

## Project Structure

```
miniproject/
├── vga_pong.v          # Top-level RTL — entire design in one file
├── vga_pong.qpf        # Quartus Project File
├── vga_pong.qsf        # Quartus Settings File (pin assignments, device)
├── output_files/       # Compilation outputs (.sof, .pof, reports)
├── db/                 # Quartus incremental compilation database
└── incremental_db/     # Quartus incremental compilation cache
```

---

## Architecture

The entire design lives in **`vga_pong.v`** and is structured into eleven clearly commented sections:

```
┌─────────────────────────────────────────────────────┐
│                   vga_pong (Top)                    │
│                                                     │
│  50 MHz ──► Pixel Clk ──► VGA Timing (H/V Counters)│
│                  │                                  │
│             Frame Tick (~60 Hz)                     │
│                  │                                  │
│  KEY[3:0] ──► Debounce ──► Game Logic FSM           │
│  SW[0]    ──►             (Paddle / Ball / Score)   │
│                  │                                  │
│             Pixel Renderer ──► Colour Mixer         │
│                                    │                │
│                              VGA_R/G/B + Sync       │
└─────────────────────────────────────────────────────┘
```

### 1. Pixel Clock Generation

The 50 MHz system clock is divided by 2 using a toggle register (`pix_clk_en`) to produce a **25 MHz pixel clock enable** signal, which gates all VGA-domain updates and drives `VGA_CLK` directly.

### 2. VGA Timing Controller

Implements standard **640×480 @ 60 Hz** timing with 10-bit horizontal and vertical counters:

| Parameter | Value |
|-----------|-------|
| H Visible | 640 px |
| H Front Porch | 16 px |
| H Sync Pulse | 96 px |
| H Back Porch | 48 px |
| H Total | 800 px |
| V Visible | 480 ln |
| V Front Porch | 10 ln |
| V Sync Pulse | 2 ln |
| V Back Porch | 33 ln |
| V Total | 525 ln |

`VGA_HS` and `VGA_VS` are active-low sync signals generated combinatorially from the counters. `VGA_BLANK_N` gates pixel output.

### 3. Frame Tick Generator

A 20-bit counter fires a single-cycle `frame_tick` pulse every **833 333 clock cycles** (≈ 60 Hz), used to update all game objects at a fixed frame rate independent of the VGA pixel clock.

### 4. Input Debounce Logic

Each push-button (`KEY[0]`–`KEY[3]`) and the reset switch (`SW[0]`) passes through a **20-bit saturating counter** debouncer. The stable state register is updated only when the counter saturates (all bits = 1), filtering out contact bounce typical of mechanical switches.

> **Note:** DE2 push-buttons are **active-low** (pressed = `0`).

### 5. Game Logic FSM

Runs synchronously with the 50 MHz clock, but updates only on `frame_tick`:

- **Paddle movement** — both paddles are clamped between `PAD_YMIN` (8) and `PAD_YMAX` (400) and move at `PAD_SPD = 5` pixels/frame.
- **Ball physics** — the ball moves at `BSX = 5 px/frame` horizontally and `BSY = 4 px/frame` vertically; direction bits (`bxd`, `byd`) flip on collision.
- **Collision detection** — AABB (Axis-Aligned Bounding Box) checks for walls, top/bottom, and paddle faces.
- **Serve delay** — after each point, a `serve_cnt` counter holds the ball at centre for **90 frames** (~1.5 s) before serving.
- **Scoring & win** — first player to reach `WIN_SCORE = 7` sets `gover = 1`, freezing the game and displaying a win banner.
- **Reset** — toggling `SW[0]` synchronously resets all registers to their initial state.

#### Game Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `PAD_W` | 12 px | Paddle width |
| `PAD_H` | 72 px | Paddle height |
| `BALL_S` | 10 px | Ball size (square) |
| `LPAD_X` | 24 | Left paddle X position |
| `RPAD_X` | 604 | Right paddle X position |
| `PAD_SPD` | 5 px/frame | Paddle speed |
| `BSX` | 5 px/frame | Ball horizontal speed |
| `BSY` | 4 px/frame | Ball vertical speed |
| `WALL_T` | 8 px | Top/bottom wall thickness |
| `WIN_SCORE` | 7 | Points needed to win |

### 6. Pixel Renderer

For every pixel clock cycle, eight combinatorial `wire` signals determine what object occupies that pixel:

| Signal | Object |
|--------|--------|
| `wall_on` | Top & bottom boundary walls |
| `cline_on` | Centre dashed dividing line |
| `lpad_on` | Player 1 (left) paddle |
| `rpad_on` | Player 2 (right) paddle |
| `ball_on` | Ball |
| `ldig_px` | Player 1 score digit (2× scaled bitmap font) |
| `rdig_px` | Player 2 score digit (2× scaled bitmap font) |
| `ban_px / ban_bg` | "P1 WINS" / "P2 WINS" end-game banner |

**Bitmap font** — digits 0–9 and letters P, W, I, N, S are encoded as 7-row × 8-column bitmaps in the `dig_row` and `chr_row` Verilog functions, rendered at 1× or 2× scale.

### 7. Colour Mixer

A priority-encoded combinatorial block assigns 24-bit RGB colours:

| Object | Colour |
|--------|--------|
| Background | `#0B1120` (deep navy) |
| Walls | `#38BDF8` (sky blue) |
| Ball | `#FFFFFF` (white) |
| P1 Paddle / Score | `#00E5FF` (cyan) |
| P2 Paddle / Score | `#FF6B00` (orange) |
| Centre line | `#1E293B` (slate) |
| Win banner (P1) | `#004455` bg / white text |
| Win banner (P2) | `#552200` bg / white text |

---

## I/O Pin Mapping

| Signal | DE2 Pin | Description |
|--------|---------|-------------|
| `CLOCK_50` | `PIN_N2` | 50 MHz system clock |
| `KEY[0]` | `PIN_G26` | P1 Paddle DOWN |
| `KEY[1]` | `PIN_N23` | P1 Paddle UP |
| `KEY[2]` | `PIN_P23` | P2 Paddle DOWN |
| `KEY[3]` | `PIN_W26` | P2 Paddle UP |
| `SW[0]` | `PIN_N25` | Reset game |
| `VGA_CLK` | `PIN_B8` | VGA pixel clock |
| `VGA_HS` | `PIN_A7` | Horizontal sync |
| `VGA_VS` | `PIN_D8` | Vertical sync |
| `VGA_BLANK_N` | `PIN_D6` | Blank signal |
| `VGA_SYNC_N` | `PIN_B7` | Composite sync (tied low) |
| `VGA_R[7:0]` | `PIN_H12` – `PIN_C8` | Red channel |
| `VGA_G[7:0]` | `PIN_D11` – `PIN_B9` | Green channel |
| `VGA_B[7:0]` | `PIN_B11` – `PIN_J13` | Blue channel |

> All pin assignments are stored in `vga_pong.qsf` and are applied automatically when the project is opened in Quartus.

---

## Controls

| Button / Switch | Action |
|-----------------|--------|
| `KEY[1]` (hold) | **P1** Move paddle **UP** |
| `KEY[0]` (hold) | **P1** Move paddle **DOWN** |
| `KEY[3]` (hold) | **P2** Move paddle **UP** |
| `KEY[2]` (hold) | **P2** Move paddle **DOWN** |
| `SW[0]` → **ON** | **Reset** game (all scores & positions) |
| `SW[0]` → **OFF** | Resume / start |

> Buttons are active-low on the DE2 board — hold the button to keep the paddle moving.

---

## Game Rules

1. The ball spawns at the centre of the screen and is served after a ~1.5 s delay.
2. A player scores a point when the ball crosses the **opponent's** side wall.
3. After each point, the ball resets to centre with a fresh serve delay.
4. The **first player to reach 7 points** wins.
5. A coloured banner (`P1 WINS` or `P2 WINS`) is displayed and the game freezes.
6. Toggle `SW[0]` ON then OFF to reset and start a new match.

---

## Building & Flashing

### Prerequisites

- **Intel Quartus II 13.0 SP1** (or later, Web Edition works)
- USB-Blaster driver installed

### Steps

1. **Open the project**
   ```
   File → Open Project → vga_pong.qpf
   ```

2. **Compile**
   ```
   Processing → Start Compilation   (Ctrl+L)
   ```
   Output files (`.sof`, `.pof`, reports) are written to `output_files/`.

3. **Program the FPGA**
   - Connect DE2 via USB-Blaster
   - `Tools → Programmer`
   - Add `output_files/vga_pong.sof`
   - Click **Start**

4. **Connect VGA** and power on the DE2. The game starts immediately.

---

## Design Notes

- **Single-file RTL** — the entire design (`vga_pong.v`, 438 lines) is intentionally kept in one file for portability and ease of review.
- **No PLL used** — the 25 MHz pixel clock is derived via a clock-enable toggle to avoid requiring a PLL megafunction, keeping the design tool-agnostic.
- **Fully synchronous** — all flip-flops are clocked on `posedge CLOCK_50`; no latches or asynchronous resets are used.
- **Debounce depth** — 20-bit counters at 50 MHz provide ~20 ms of debounce time, well within mechanical switch specifications.
- **Bitmap font ROM** — digit and letter bitmaps are implemented as Verilog `function` blocks (pure combinatorial ROM), synthesising to LUT-based lookup tables.

---

*Created: April 29, 2026 | Target: Altera DE2 (Cyclone II EP2C35F672C6N) | Tool: Quartus II 13.0 SP1*
“This README was generated with AI assistance. If you find any mistakes or conflicts, please let me know — I’ll review and resolve them.”

