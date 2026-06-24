# Distance Transform Circuit — Design Specification

## 1. Overview

This module is a **Distance Transform (DT)** accelerator for a binary image. Its input is a 128×128 binary image (each pixel 0 = background, 1 = object) packed into a read-only memory; its output is a 128×128 grayscale image where each object pixel's value is replaced by its distance to the nearest background pixel (using the **Chessboard / Chebyshev distance** metric). The circuit reads the binary image from a host ROM, computes the distance transform with a two-pass (forward then backward) algorithm, writes the result into a host RAM one byte per pixel, and raises `done` when finished so the host can verify the result.

## 2. What the module must do (functional description)

### 2.1 The distance-transform concept

Each pixel is first **labeled**: object pixels (binary value 1) start at a small value to be raised, background pixels (binary value 0) are 0. Conceptually, the transform replaces every object pixel with its Chessboard distance to the nearest background pixel. The Chessboard distance between two points `(x1,y1)` and `(x2,y2)` is `max(|x1-x2|, |y1-y2|)` — diagonal steps count the same as orthogonal steps, so distance grows in square "rings" outward from the background.

This is computed with the classic **two-pass chamfer algorithm** over a 3×3 neighborhood, using two complementary half-windows:

```
Forward window (causal)      Backward window (anti-causal)
 NW  N  NE                        .   .   .
  W  [P] .                        .  [P]  E
  .   .   .                       SW  S  SE
```

`[P]` is the current pixel. The forward window covers the four already-visited neighbors (NW, N, NE, W); the backward window covers the four neighbors visited in the reverse scan (E, SE, S, SW).

### 2.2 Step 1 — Initialization

Label every pixel: `p(x,y) = 1` if the pixel is an object (binary 1), `p(x,y) = 0` if background (binary 0).

### 2.3 Step 2 — Forward pass

Scan the whole image **left-to-right, top-to-bottom**. For each object pixel, take the minimum of the four forward-window neighbors (W, NW, N, NE) and set the pixel to that minimum + 1:

```
if p(x,y) is an object pixel:
    p(x,y) = min(p_W, p_NW, p_N, p_NE) + 1
```

Background pixels are left at 0. Because the scan is top-to-bottom/left-to-right, all four of those neighbors have already been updated this pass when the current pixel is processed.

### 2.4 Step 3 — Backward pass

Scan the whole image **right-to-left, bottom-to-top** over the forward-pass result. For each object pixel, combine its own current value with the four backward-window neighbors (E, SE, S, SW) plus one, taking the minimum:

```
if p(x,y) is an object pixel:
    p(x,y) = min( p(x,y), p_E + 1, p_SE + 1, p_S + 1, p_SW + 1 )
```

After both passes the buffer holds the final distance-transform grayscale image.

### 2.5 Border guarantee

The image is fixed at 128×128. The test data guarantees that **no object region ever touches the outermost one-pixel ring** of the image — the border ring is always background. An object pixel therefore always has all 8 neighbors inside the image, so edge clamping is never exercised by the patterns.

### 2.6 Fully worked example (from the appendix walkthrough)

After labeling, object pixels are 1 and background 0. The **forward pass** turns a solid object region into increasing values as you move away from its top/left edges: a pixel whose W/NW/N/NE neighbors are all `1` becomes `2`, the next becomes `3`, and so on, so an interior region fills with a gradient. The appendix forward fragment

```
0 0 0 0 0 0 0
0 1 1 1 1 1 0
0 1 2 2 2 1 0
0 1 2 3 2 1 0
0 1 2 3 2 1 0   (forward over-counts toward the bottom)
```

after the **backward pass** becomes the corrected distances

```
0 0 0 0 0 0 0
0 1 1 1 1 1 0
0 1 2 2 2 1 0
0 1 2 2 2 1 0
0 1 1 1 1 1 0
```

where every value equals the Chessboard distance to the nearest 0. A worked corner of the contest's TB1 pattern shows a large solid square whose top-left corner fills diagonally `1 2 3 4 5 6 7 8 9 10 11 …` down the leading diagonal, confirming that the value deep inside a big object equals its ring-distance to the nearest background pixel.

## 3. Interface

Port list from the authoritative `TOP` module (`initial.sv`) and its instantiation in `test.sv`. **The top module is named `TOP`** (the PDF calls it `DT`). **Reset is named `rst` and is active-low asynchronous.**

| Signal | Dir | Width | Meaning |
|---|---|---|---|
| `clk` | In | 1 | System clock. |
| `rst` | In | 1 | **Active-low, asynchronous** reset (`!rst` clears state). |
| `done` | Out | 1 | Raised High when the whole transform is complete; the host then compares `res_RAM` against the golden image. |
| `sti_rd` | Out | 1 | Read-enable for the input ROM (`sti_ROM`). High means "fetch the addressed word." |
| `sti_addr` | Out | 10 | Word address into `sti_ROM` (0..1023). |
| `sti_di` | In | 16 | 16-bit word read from `sti_ROM` (16 packed binary pixels). |
| `res_wr` | Out | 1 | Write-enable for the result RAM (`res_RAM`). |
| `res_rd` | Out | 1 | Read-enable for the result RAM. |
| `res_addr` | Out | 14 | Byte address into `res_RAM` (0..16383). |
| `res_do` | Out | 8 | Data written to `res_RAM` (one grayscale pixel). |
| `res_di` | In | 8 | Data read back from `res_RAM` (one grayscale pixel). |

**How the signals interact.** Two memory interfaces sit on the host side. `sti_ROM` is read-only: drive `sti_rd` High with an address on `sti_addr`, and the 16-bit word comes back on `sti_di`. `res_RAM` is read/write: with `res_rd` High and `res_addr` set, a byte returns on `res_di`; with `res_wr` High, the byte on `res_do` is stored at `res_addr`. The design may read and write `res_RAM` as many times as needed during processing — there is no access limit, and only one address may be accessed per cycle on each interface. When the entire result image is written, the design asserts `done` and holds it.

(Note: the testbench also references a `fwpass_finish` wire to know when the forward pass is done. In the reference design this is exposed only as an internal `fw_finish = flag_fb` assignment and is **not** a port of `TOP`; see Differences.)

## 4. Timing / protocol

All sequential logic clocks on the **rising edge** of `clk`; reset is **asynchronous active-low**.

### 4.1 Reset sequence (as the harness actually drives it)

In `test.sv`: `rst` is set High at start, then on a falling edge dropped Low (asserting reset), held Low for three cycles, then on a falling edge raised High again to release. So reset is **active-low**, asserted by driving `rst=0`, and the design begins once `rst` returns to 1. The input ROM loads its pattern at `@(negedge rst)` — right as reset is asserted.

### 4.2 Input ROM read (`sti_rd`, `sti_addr` → `sti_di`)

The ROM model updates on the **falling edge** of `clk`: if `sti_rd` is High at a negedge, `sti_di` is loaded with `sti_M[sti_addr]`. Present the address with `sti_rd` High, and the word is available after the following falling edge; no extra read latency need be modeled. If `sti_rd` is Low, the ROM does nothing.

### 4.3 Result RAM read (`res_rd`, `res_addr` → `res_di`)

The RAM model also reads on the **falling edge**: if `res_rd` is High at a negedge, `res_di` is loaded from `res_M[res_addr]`. No additional read latency need be modeled.

### 4.4 Result RAM write (`res_wr`, `res_addr`, `res_do`)

The RAM writes on the **rising edge**: if `res_wr` is High at a posedge, `res_do` is stored into `res_M[res_addr]`. No write latency need be modeled. `res_RAM` powers up initialized to all zeros, so background pixels that are never written already read as 0.

### 4.5 Completion

After the entire result image has been written, raise `done` High and keep it High. The host watches `done`; once it sees `done`, it compares the RAM contents against the golden result and ends the simulation. The bench separately checks the forward-pass result the moment its internal forward-finish condition is met, then the final result when `done` rises.

## 5. Memory layout

### 5.1 Input ROM (`sti_ROM`): packed 1-bit pixels

The 128×128 binary image is 16384 pixels, scanned **row-major, left-to-right then top-to-bottom**, packed 16 pixels per 16-bit ROM word. The ROM has 1024 words (addresses 0..1023):

- Pixels 0..15 → ROM address 0
- Pixels 16..31 → ROM address 1
- Pixels 32..47 → ROM address 2, and so on
- Pixels 112..127 (end of image row 0) → ROM address 7
- …
- Pixels 16368..16383 (last 16 pixels) → ROM address 1023

The linear pixel index is `idx = row·128 + col`; it lives in ROM word `idx >> 4`. The reference design fetches each 16-bit word and **bit-reverses it** when buffering (it copies `sti_di[i]` into `idata_buf[15-i]`), then writes the 16 unpacked bits out as 16 separate bytes — so be careful which bit of the word maps to which pixel column. *(The exact MSB/LSB-to-pixel-column convention is fixed by this bit-reversal in the reference design; a fresh implementation must match whatever the golden data expects.)*

### 5.2 Result RAM (`res_RAM`): one byte per pixel

The output grayscale image is 128×128 = 16384 pixels, each an **8-bit** value, stored **row-major, left-to-right then top-to-bottom**, one pixel per address (addresses 0..16383). Address = `row·128 + col`. The reference design forms result addresses by concatenating the 7-bit row `y` and 7-bit column `x`: `res_addr = {y, x}`.

Sample address ↔ value correspondence (row-major, width 128):

| Address | (row, col) | Example value |
|---|---|---|
| 0 | (0, 0) | 0 (border is background) |
| 1 | (0, 1) | 0 |
| 1675 | (13, 11) | 1 (first object ring) |
| 1933 | (15, 13) | 3 (deeper interior) |
| 16383 | (127, 127) | 0 (border) |

The host loads two golden files for comparison: a forward-pass-only expected image (`*_fwexp.dat`) checked when the forward pass finishes, and the final expected image (`*_bcexp.dat`) checked when `done` rises. The stimulus image is loaded from `*_sti.dat`. Two test patterns are provided (selected by `` `define TB1 ``/`` `define TB2 `` in the testbench; the default is TB1, `Geometry_*`).

## 6. Reference implementation (from `initial.sv`)

**Algorithm level.** The reference `TOP` first unpacks the ROM into `res_RAM`: it reads all 1024 ROM words, bit-reverses each 16-bit word, and writes the 16 bits out as 16 individual bytes (the labeled image, object=1/background=0). Then it runs the forward pass scanning `(x,y)` increasing, and the backward pass scanning `(x,y)` decreasing, each time reading the four window neighbors out of `res_RAM`, taking the running minimum, and writing back `min+1` (forward) or `min(self, neighbors+1)` (backward). When the backward pass reaches address 0 it asserts `done`.

**Micro-architecture.** An 8-state FSM (`IDLE, INPUT, COMP, OUTPUT, READMEM, DELAY, COPY, FINISH`):

- `INPUT`/`COPY`: `INPUT` asserts `sti_rd` and latches a ROM word into `idata_buf` (bit-reversed); `COPY` then writes the 16 unpacked bits to `res_RAM` one per cycle, addressing `res_addr = {sti_addr, dup_cnt}` with `dup_cnt` 0..15. `sti_addr` increments after each group of 16. When `sti_addr` reaches 1023, unpacking is done → `READMEM`.
- `READMEM`: reads the current pixel `{y,x}` from `res_RAM`; if it is an object pixel (`res_di != 0`) it proceeds to `COMP`, otherwise advances to the next pixel. `flag_fb` distinguishes forward (0) vs backward (1) phase; the phase flips to backward when `res_addr` hits 16383, and the whole thing finishes when, in the backward phase, `res_addr` returns to 0.
- `COMP`: walks the four neighbor addresses (`addr_forw[0..3]`, formed from `{y±1,x±1}` etc., offset +1 forward / −1 backward as the design indexes them), reading each neighbor and keeping the running `mini`.
- `OUTPUT`: writes the result byte — `mini+1` in the forward phase; `min(res_input_buf, mini+1)` in the backward phase (so the backward pass never increases a pixel).
- `DELAY`: turn-around state between the two passes, re-seating `(x,y)` to `(127,127)` and `res_addr` to 16383 for the backward scan.
- `done` is raised in `FINISH`.
- Coordinate registers: `x, y` are 7-bit, incrementing in forward, decrementing in backward; `cnt_calc` (0..4) sequences the four neighbor reads; `dup_cnt` (0..15) sequences the 16-bit unpack.
- All sequential blocks are `always @(posedge clk or negedge rst)` with active-low async reset, matching the harness.

## 7. Differences from the original problem

- **Module name:** the design module is `TOP`, not the PDF's `DT`. (From `test.sv`/`initial.sv`.)
- **Design entry point:** the design is written in `initial.sv`, which already declares the `TOP` port list.
- **Reset name/sequence:** the reset port is `rst` (PDF calls it `reset`); polarity is active-low asynchronous as in the PDF, but the harness asserts it for ~3 cycles around negedges rather than the PDF's stated "2 cycles."
- **Host memory models live in the testbench:** `sti_ROM` and `res_RAM` are instantiated inside `test.sv` (reads on negedge, RAM writes on posedge, RAM pre-initialized to 0); the design talks to them only through the ports above.
- **Forward-pass checkpoint:** the bench waits on a `fwpass_finish` wire and compares an intermediate forward-pass golden image (`*_fwexp.dat`) before the final `*_bcexp.dat` check. In the reference design this finish indication is an internal signal (`fw_finish = flag_fb`), not a declared port of `TOP`. (Unspecified in source: how `fwpass_finish` is meant to connect; the provided reference does not wire it to a `TOP` port.)
- **Data file names/paths:** the harness reads `./00_TB/dat/Geometry_sti.dat`, `Geometry_fwexp.dat`, `Geometry_bcexp.dat` for TB1 (and `ICC17_*` for TB2); the PDF's Appendix B lists generic `./dat/*_sti.dat`/`*_bcexp.dat`. The SDF path is `../02_SYN/Netlist/top_syn.sdf` annotated onto `TOP`.
- **Omitted as irrelevant to solving the problem:** contest scoring tiers (A/B/C/D, area/time thresholds, `Score = Time × Area`), submission/FTP/`report.000` procedures, and EDA tool-version lists from the PDF appendices.