# Local Binary Patterns (LBP) Hardware Accelerator — Design Specification

## 1. Overview

This module computes the **Local Binary Pattern (LBP)** of a 128×128, 8-bit grayscale image. The image lives in a memory on the Host side (`gray_mem`); the module must request pixel data from the Host, compute an 8-bit LBP code for each pixel, and write each result back to a second Host memory (`lbp_mem`). When every pixel has been processed, the module raises a `finish` signal, after which the Host automatically verifies the results against a golden image.

The top module is named **`TOP`** and is the design entry point. It has no parameters and communicates with the Host purely through the ports described below.

---

## 2. What the module must do (functional description)

### The LBP algorithm, intuitively

LBP describes local texture by comparing each pixel to its immediate neighbors. For a center pixel, you look at the 3×3 square of pixels surrounding it (the center plus its 8 nearest neighbors). Each of the 8 neighbors is compared against the center value: if the neighbor is greater than or equal to the center, it contributes a `1`; otherwise it contributes a `0`. Each neighbor position is assigned a fixed weight that is a distinct power of two (2⁰ through 2⁷). The final LBP code for that center pixel is the sum of (threshold bit × weight) over all 8 neighbors — a single 8-bit number in the range 0–255.

Formally, for a center pixel `g_c` at coordinate (x, y) with neighbors `g_p` (p = 0…7):

```
            7
LBP(x,y) =  Σ  s(g_p − g_c) · 2^p ,   where   s(z) = 1 if z ≥ 0, else 0
           p=0
```

Note the threshold is **≥** (greater-than-or-equal), not strictly greater than — a neighbor exactly equal to the center counts as `1`.

### Neighbor numbering and bit positions

The source defines the 3×3 region with the center `g_c` in the middle and the 8 neighbors labeled `g0…g7`. The spatial layout of the labels (from Figure 3 of the source) is:

```
 g0  g1  g2
 g3  g_c g4
 g5  g6  g7
```

The weight assigned to each neighbor `g_p` is `2^p`. The critical question a designer needs answered is *which spatial position maps to which weight/bit*. The worked example below fixes this convention exactly.

### Fully worked example (from the source's Figure 4)

The source gives a concrete 3×3 neighborhood. The center pixel value is **5** (shown circled). The full grid of grayscale values is:

```
  7   1  12
  2  [5]  5
  5   3   0
```

**Step 1 — Threshold** each of the 8 neighbors against the center (5), using `s(z)=1 if neighbor ≥ 5`:

| Position | Neighbor value | ≥ 5 ? | Threshold bit |
|----------|---------------|-------|---------------|
| top-left      |  7 | yes | 1 |
| top-middle    |  1 | no  | 0 |
| top-right     | 12 | yes | 1 |
| middle-left   |  2 | no  | 0 |
| middle-right  |  5 | yes | 1 |
| bottom-left   |  5 | yes | 1 |
| bottom-middle |  3 | no  | 0 |
| bottom-right  |  0 | no  | 0 |

Arranged spatially, the threshold grid is:

```
 1  0  1
 0  .  1
 1  0  0
```

**Step 2 — Weights.** The source's "Multiply" grid assigns the powers of two to spatial positions in this order:

```
 2^0  2^1  2^2
 2^3   .   2^4
 2^5  2^6  2^7
```

i.e. row-major over the 8 neighbor positions (skipping the center): top row left→right gets 2⁰,2¹,2²; the two middle cells get 2³ (left), 2⁴ (right); the bottom row left→right gets 2⁵,2⁶,2⁷.

**Step 3 — Multiply and sum.** Multiplying each threshold bit by its weight gives the source's purple result grid:

```
 1   0   4
 0   .  16
32   0   0
```

(Only the positions whose threshold bit was 1 survive: top-left = 1·2⁰ = 1, top-right = 1·2² = 4, middle-right = 1·2⁴ = 16, bottom-left = 1·2⁵ = 32.)

**Final code:** LBP = 1 + 4 + 16 + 32 = **53**.

This worked example is the authoritative definition of the bit-ordering convention. A correct implementation must reproduce LBP = 53 for this exact neighborhood.

### Border handling

The outermost ring of the image (the first and last rows, and the first and last columns) has no complete 3×3 neighborhood and is **not** computed. The LBP result for every border pixel must be **0**. To simplify the design, the Host pre-initializes the entire `lbp_mem` to 0, so the design only needs to ensure it writes correct values for interior pixels (rows/columns 1…126) and may leave the border untouched, though writing 0 there is also acceptable.

So only the 126×126 interior pixels receive a computed LBP value; the surrounding one-pixel border stays 0.

---

## 3. Interface

The port list below is taken from the authoritative testbench (`test.sv`) and design entry point (`initial.sv`). The top module is **`TOP`**. All ports are 1 bit unless a width is given.

| Signal | Dir | Width | Meaning |
|--------|-----|-------|---------|
| `clk`        | I | 1  | System clock. The design is synchronous to the **rising edge**. |
| `rst`        | I | 1  | **Active-high, asynchronous** reset. (See note: the PDF calls this `reset`; the environment names it `rst`.) |
| `gray_addr`  | O | 14 | Grayscale image address bus. The design drives this to request the pixel at a given address from `gray_mem`. One address per cycle. |
| `gray_req`   | O | 1  | Grayscale request enable. When High, the design is requesting grayscale data from the Host. |
| `gray_ready` | I | 1  | Grayscale ready indicator. When High, the Host has finished preparing `gray_mem`; the design may only begin issuing requests after observing this High. |
| `gray_data`  | I | 8  | Grayscale data bus. The Host returns the pixel value at the requested address on this bus. |
| `lbp_addr`   | O | 14 | LBP result address bus. Selects which `lbp_mem` location the result is written to. |
| `lbp_valid`  | O | 1  | LBP write enable. When High, the `lbp_data`/`lbp_addr` currently on the buses are valid and should be written. |
| `lbp_data`   | O | 8  | LBP result data bus — the 8-bit computed code to store. |
| `finish`     | O | 1  | Completion flag. Raised High once all pixels have been computed and written, signaling the Host to begin verification. |

### How the signals interact

After reset deasserts, the Host raises `gray_ready` to announce the image memory is ready. Only then may the design start. To read a pixel, the design raises `gray_req` and puts the desired address on `gray_addr`; the Host responds with that address's value on `gray_data`. Reads can be issued back-to-back by holding `gray_req` High and changing `gray_addr` every cycle (a streaming/pipelined read).

To write a result, the design raises `lbp_valid` and places the destination address on `lbp_addr` and the value on `lbp_data`; the Host commits the write. Writes can also be streamed by holding `lbp_valid` High and changing the address/data each cycle. When the whole image is done, the design raises `finish`.

---

## 4. Timing / protocol

The clock toggles every half-cycle; the cycle period in the harness is 10 ns. The design logic is clocked on the **rising edge** of `clk`. **Crucially, the Host samples and responds on the *falling* (negative) edge of `clk`** for both the read and write handshakes. This means there is effectively a half-cycle/one-cycle pipeline relationship between when the design drives an address and when valid data appears or is committed — the design must account for this read latency.

### Read handshake (request grayscale data)

Cycle by cycle, following the source's first timing diagram:

1. Reset is asserted and held for two cycles, then deasserted; the design's initialization completes.
2. The Host raises `gray_ready` High to signal readiness.
3. Once the design sees `gray_ready` High, it raises `gray_req` High and simultaneously drives the first desired address onto `gray_addr`.
4. On the following **falling clock edge**, if the Host sees `gray_req` High and `finish` Low, it places the value at `gray_addr` onto `gray_data`. The design therefore receives the requested pixel after this edge — i.e. there is a read latency the design must pipeline around (the data for an address issued in one cycle is available in the next).
5. For continuous reads, hold `gray_req` High and change `gray_addr` each cycle; `gray_data` streams out the corresponding values.
6. To stop requesting, drive `gray_req` Low; on the next sampling edge the Host stops driving `gray_data` (it goes to high-impedance `z` in the harness).

In the harness, the Host's read loop is: on each falling clock edge, if `gray_req` is High it drives `gray_data = gray_mem[gray_addr]`, otherwise it drives `z`. This loop runs while `finish == 0`.

### Write handshake (store LBP results)

Following the source's second timing diagram:

1. When the design has a result ready, it raises `lbp_valid` High and places the destination address on `lbp_addr` and the 8-bit result on `lbp_data`.
2. On the next **falling clock edge**, the Host (if `lbp_valid` is High) writes `lbp_data` into `lbp_mem[lbp_addr]`.
3. For continuous writes, hold `lbp_valid` High and change `lbp_addr`/`lbp_data` each cycle.
4. To stop writing, drive `lbp_valid` Low.
5. Once all pixels are processed, raise `finish` High. The Host then begins verification; the simulation ends shortly after verification completes.

In the harness, the Host's write logic is: `always @(negedge clk) if (lbp_valid) LBP_M[lbp_addr] <= lbp_data;`.

### Reset behavior

Reset (`rst`) is **active-high and asynchronous**: the design's reset branch is triggered on a rising edge of either `clk` or `rst`. In the harness, `rst` is asserted on a falling clock edge, held for two cycles, then deasserted on a falling edge, after which `gray_ready` is raised on the next falling edge.

---

## 5. Memory layout

Both memories are 16384 entries of 8 bits each (128×128 pixels). Addressing is **row-major**: a pixel at row r (0…127) and column c (0…127) lives at

```
address = r · 128 + c
```

So address 0 is the top-left pixel, address 127 ends the first row, address 128 begins the second row, and address 16383 is the bottom-right pixel.

**Result placement:** the LBP result for the pixel read from `gray_mem` address *k* is written to `lbp_mem` address *k* (same index, k = 0…16383). The border pixels (first/last row, first/last column) map to results of 0 in `lbp_mem`.

### Grayscale memory addressing (Figure 5)

The image-to-memory mapping, row by row:

| Pixel row | Addresses |
|-----------|-----------|
| Row 0 | 0, 1, 2, …, 127 |
| Row 1 | 128, 129, …, 255 |
| Row 2 | 256, 257, …, 383 |
| Row 3 | 384, 385, …, 511 |
| … | … |
| Row 126 | 16128, 16129, …, 16255 |
| Row 127 | 16256, 16257, …, 16383 |

### Sample LBP result values (from Figure 6)

The source's result figure shows specific `lbp_mem` address → value pairs, useful as a regression spot-check. The first row (addresses 0–127) is all 0 (border). Sampled entries:

| Address | Value |
|---------|-------|
| 0   | 0 (border) |
| 1   | 0 (border) |
| 127 | 0 (border) |
| 128 | 0 (border, start of row 1) |
| 129 | 31 |
| 130 | 3 |
| 131 | 255 |
| 254 | 6 |
| 255 | 0 (border, end of row 1) |
| 256 | 0 (border, start of row 2) |
| 257 | 255 |
| 16382 | 0 (border) |
| 16383 | 0 (border) |

The figure additionally shows a block of interior result values (reading along rows): 31, 3, 255, 231, 255, 6 / 255, 3, 41, 250, 105, 47 / 157, 206, 255, 255, 107, 223 / 255, 211, 208, 104, 107, 165, and elsewhere 151, 150, 150, 148, 2, 240. These are illustrative interior outputs, not a contiguous address range, but confirm results span the full 0–255 range.

---

## 6. Current / reference implementation

`initial.sv` contains a **working reference implementation** of `TOP`. This section describes what it does.

### Algorithm level

The design streams through the image computing one pixel's LBP per outer iteration using a 4-state machine and a 9-entry shift buffer. Rather than re-reading all 9 neighbors for every pixel, it reuses overlapping columns: as it advances horizontally, it keeps the previous two columns of the 3×3 window in a buffer and fetches only the one new column (3 pixels) needed for the next pixel. This is why it reads 3 new values (states `DATA1`, `DATA2`, `DATA3`) and then writes one result (state `WRITE_DATA`) per pixel.

### Micro-architecture

- **State machine:** four states `DATA1 → DATA2 → DATA3 → WRITE_DATA → DATA1 …`, advancing every clock. `state_r` is the registered state; `state_w` is the next-state combinational logic.
- **Buffer:** `reg [7:0] buffer[8:0]` holds the 3×3 window. New pixels are captured into `buffer[2]`, `buffer[5]`, `buffer[8]` during the three read states, and the buffer is shifted left by one column during `WRITE_DATA` so the two right columns become the two left columns for the next pixel.
- **Address generation:** `gray_addr` is updated using two precomputed offsets — `plus = gray_addr + 128` (move down one row, same column) and `minus = gray_addr − 255` (move up two rows and right one column, repositioning to the top of the next column). These walk the 3×3 fetch pattern.
- **Center pixel:** `buffer[4]` holds the center; the eight comparisons `buffer[i] >= buffer[4]` produce the eight `lbp_data` bits directly. The bit assignment used is: `lbp_data[0..7]` from `buffer[0],buffer[1],buffer[2],buffer[3],buffer[5],buffer[6],buffer[7],buffer[8]` respectively (buffer[4], the center, is skipped).
- **Result address / valid:** `lbp_addr` is initialized to 126 at reset and increments as pixels are produced. `lbp_valid` is suppressed (held 0) when `lbp_addr[6:0]` is `0000000` or `1111111` — i.e. on the first/last column of a row — implementing border suppression so those positions keep their pre-initialized 0.
- **Finish:** `finish` is raised when `lbp_addr` reaches `14'd16254`, marking the last interior pixel processed.
- **Reset:** asynchronous active-high; on reset, `state_r←DATA1`, `gray_addr←0`, `lbp_addr←126`, `finish←0`.
- **Clocking:** all sequential logic is on `posedge clk` (with `posedge rst` for async reset).

This is descriptive of the provided code; treat it as one valid solution rather than the only acceptable architecture.

---

## 7. Differences from the original problem

- **Top module name:** the design module is `TOP`, not the PDF's `LBP`. (`test.sv` instantiates `TOP`.)
- **Design entry point:** the design is written in `initial.sv` (which defines `module TOP`), not the PDF's `LBP.v`.
- **Reset port name:** the environment names the reset `rst`; the PDF table calls it `reset`. Polarity and behavior (active-high, asynchronous) are unchanged.
- **Reference implementation provided:** unlike a greenfield problem, `initial.sv` already contains a working implementation (described in §6).
- **Pattern/golden file names:** the harness reads `./00_TB/pattern1.dat` and `./00_TB/golden1.dat`; the PDF appendix referred to `./pattern1.dat` / `./golden1.dat` and `testfixture.v`. The actual testbench file here is `test.sv`.
- **Result memory module:** verification is done by an `lbp_mem` module inside `test.sv` whose internal array is `LBP_M[0:16383]`, compared against `exp_mem` loaded from the golden file.
- **Omitted PDF content:** the scoring/grading rules (A/B/C/D grades, Time×Area), submission/FTP procedures, EDA tool-version lists, and contest logistics from the PDF are intentionally excluded as irrelevant to solving and verifying the RTL problem.