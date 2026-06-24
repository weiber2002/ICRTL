# Optical Refraction Landing-Point Calculator — Design Specification

## 1. Overview

This module, called **REFRACT** (top module name `TOP`), simulates light rays refracting through a curved glass block and computes where each ray lands. Imagine a square block of glass whose top is a bulging aspheric surface; light comes straight down from above, bends as it enters the glass (Snell's law), and eventually reaches the flat bottom plane Z=0. For a 16×16 grid of entry points (X and Y each an integer 0…15, so 256 rays total), the module computes each ray's landing coordinate `(zx, zy)` on the Z=0 plane and writes the results into an external SRAM. When all 256 rays are done it raises `DONE`.

The refractive index of the glass, `RI`, is supplied by the host at reset (RI ranges 2…15). The air's index is 1.

---

## 2. What the module must do (functional description)

### 2.1 The surface and the rays

The glass top surface is the aspheric height field

```
Z = 6 − 2·((X−8)/8)^8 − 2·((Y−8)/8)^8
```

defined over the integer grid 0 ≤ X ≤ 15, 0 ≤ Y ≤ 15. Each of the 256 grid points emits one ray traveling straight down, i.e. with incident direction `I = (0, 0, −1)`. At the point where the ray meets the surface it refracts, then travels in a straight line until it crosses the Z=0 plane. The crossing point `(zx, zy)` is the answer for that grid point.

### 2.2 Refraction (vector Snell's law)

Snell's law is `n1·sinθ1 = n2·sinθ2`. To avoid trigonometry in hardware, the problem gives the refraction in pure vector form. With unit incident vector `I`, unit surface normal `N`, and `eta = n1/n2 = 1/RI` (since n1 = 1 for air, n2 = RI for glass):

```
T = eta·I + ( eta·(−N·I) − sqrt( 1 − eta²·(1 − (N·I)²) ) )·N
```

`T` is the unit refracted direction.

### 2.3 Getting the normal from the surface

Write the surface as `f(X,Y,Z) = Z − 6 + 2·((X−8)/8)^8 + 2·((Y−8)/8)^8 = 0`. The (unnormalized) gradient is the normal direction:

```
gx = 2·((X−8)/8)^7
gy = 2·((Y−8)/8)^7
gz = 1
```

so `g = (gx, gy, 1)` and the unit normal is `N = g / sqrt(g·g)`. Let `g² = gx² + gy² + 1`.

Because the incident ray is straight down, `I = (0,0,−1)`, and `N·I = −1/sqrt(g²)`.

### 2.4 The closed-form landing point (this is what you implement)

The problem reduces the refraction + line-plane intersection to a set of algebraic formulas. You may implement these directly without re-deriving them:

```
eta      = 1 / RI
gx       = 2·((X−8)/8)^7
gy       = 2·((Y−8)/8)^7
g²       = gx² + gy² + 1

k        = 1 − eta²·(1 − 1/g²)
sqrt_kgg = sqrt( k · g² )
coef     = ( eta − sqrt_kgg ) / g²
t        = −Z / (−eta + coef)

zx = X + ( −Z / (−eta + coef) )·coef·gx
zy = Y + ( −Z / (−eta + coef) )·coef·gy
```

Here `Z` is the surface height at that (X,Y) from §2.1. Intuitively: the refracted direction vector works out to `T = (coef·gx, coef·gy, −eta + coef)`; you scale it by the parameter `t` needed to drive the Z-component from the surface height down to 0, and add that to the entry (X,Y) to get the landing point. The two outputs per ray are `zx` and `zy`.

### 2.5 Worked intuition for the grid extremes

At the center of the block, X=8 and Y=8, so `(X−8)` and `(Y−8)` are zero, making `gx = gy = 0` and `g² = 1`. The surface there is highest (`Z = 6`) and flat, so the normal points straight up, the ray passes essentially straight through, and the landing point is at (or very near) the entry point (8, 8). Toward the edges, `(X−8)/8` and `(Y−8)/8` approach ±7/8, the eighth-power terms pull the surface height down and the seventh-power gradient terms grow, so the surface tilts steeply and rays bend outward — landing points spread away from the entry grid. (The eighth power makes the top broad and nearly flat in the middle with a fast roll-off near the rim, which is why the projections look like a plateau with rounded shoulders.)

### 2.6 Fixed-point and accuracy

All results are stored in **Q4.12 unsigned-format 16-bit words** (see §5): the top 4 bits are the integer part, the low 12 bits the fraction. A computed landing point is accepted if its Euclidean distance from the golden value is **less than 1/64 of a unit** (the testbench uses a tolerance radius of 64 in units of 1/4096, i.e. 64/4096 = 1/64). So small fixed-point rounding error is tolerated; you do not need bit-exact agreement.

---

## 3. Interface

The port list follows the **authoritative testbench (`tb.sv`)** and the design entry point (`initial.sv`). The top module is **`TOP`**, instantiated in the testbench as `u_REFRACT`. A separate behavioral `SRAM` module (provided in the testbench) holds the results; the design talks to it through the SRAM ports.

| Signal | Dir | Width | Meaning |
|--------|-----|-------|---------|
| `CLK` | In | 1 | Clock. Synchronous design, **positive-edge** triggered. |
| `RST` | In | 1 | **Active-high asynchronous** reset. |
| `RI` | In | 4 | Glass refractive index, 2…15. Latched at start. |
| `DONE` | Out | 1 | Raised high when all 256 landing points have been written to SRAM. |
| `SRAM_A` | Out | 9 | SRAM address (0…511). |
| `SRAM_D` | Out | 16 | SRAM write data (Q4.12). |
| `SRAM_Q` | In | 16 | SRAM read data. Not needed in normal operation. |
| `SRAM_WE` | Out | 1 | SRAM write-enable (active high). |

**Interaction.** At reset the host presents `RI` on the 4-bit bus; the design captures it and begins computing. For each of the 256 grid points the design computes `zx` and `zy`, then writes them to SRAM as two consecutive words using `SRAM_A`, `SRAM_D`, and `SRAM_WE`. `SRAM_Q` is the SRAM's read-data port and is unused by a normal design. After the last write, the design asserts `DONE` and holds it; the testbench is waiting on `DONE === 1` to begin checking. `RI` is the only data input; everything else the design produces.

The instantiated `SRAM` is a simple synchronous memory: on each rising clock, if `WE` is high it writes `D` to address `A`, and it always registers `mem[A]` onto `Q` (one-cycle read latency). The design only ever writes.

---

## 4. Timing / protocol

Clock and reset come from the testbench. The clock period is a `define CYCLE` (default 50.0 ns) the contestant may tune for synthesis; the design must be a positive-edge synchronous design with active-high asynchronous reset, matching `initial.sv`.

**Reset sequence.** The testbench sets `RST = 1` at time 0, runs two clock periods, then on a rising edge (plus a 1 ns delay) drops `RST = 0`, waits two more rising edges, and then simply waits for `DONE`. So the design sees reset asserted high for about two cycles at the start; releasing reset begins the computation. `RI` is stable throughout.

**Write protocol (per ray).** There is no host handshake during computation — the design is free-running. For each grid point it drives `SRAM_A` to the target word address, puts the Q4.12 value on `SRAM_D`, and pulses `SRAM_WE` high for the cycle in which that word should be captured. The two words of one ray (`zx` then `zy`) are written on consecutive write cycles to consecutive addresses. The SRAM captures on the rising edge while `WE` is high.

**Completion.** When the final (X=15, Y=15) ray's second word has been written, the design transitions to a terminal state and asserts `DONE = 1` (held high). The testbench detects `DONE`, then reads all 512 words back out of the SRAM model and compares against the golden file. A watchdog (`MAX_CYCLE`, default 100000 cycles) aborts the simulation if `DONE` never arrives, to guard against a design that loops forever.

---

## 5. SRAM / memory layout

The SRAM is **512 words × 16 bits**. Each word is **Q4.12 unsigned**: bits [15:12] are the integer part, bits [11:0] the fraction. A value `v` in real units is stored as `round(v · 4096)`.

Each ray contributes **two words**: its `zx` first, then its `zy`, in two consecutive addresses. With 256 rays that fills 512 words exactly.

**Addressing.** The grid is scanned with X as the inner (fast) coordinate and Y as the outer (slow) coordinate. The design computes the word address for ray (X, Y) as:

```
addr(zx) = 2·(16·Y + X)
addr(zy) = 2·(16·Y + X) + 1
```

So the base index of a ray is `16·Y + X` (the row-major pixel number, X fastest), doubled because each ray takes two words; the even address holds `zx`, the following odd address holds `zy`.

Sample address map (matching the layout the PDF's memory figure shows, X fastest within a Y row):

| Address | Holds |
|---------|-------|
| 0  | zx of (X=0, Y=0) |
| 1  | zy of (X=0, Y=0) |
| 2  | zx of (X=1, Y=0) |
| 3  | zy of (X=1, Y=0) |
| 4  | zx of (X=2, Y=0) |
| 5  | zy of (X=2, Y=0) |
| …  | … |
| 30 | zx of (X=15, Y=0) |
| 31 | zy of (X=15, Y=0) |
| 32 | zx of (X=0, Y=1) |
| 33 | zy of (X=0, Y=1) |
| …  | … |
| 510 | zx of (X=15, Y=15) |
| 511 | zy of (X=15, Y=15) |

For example, address 482 holds the `zx` of (X=1, Y=15): `2·(16·15 + 1) = 2·241 = 482`.

> **Important verification note (harness quirk).** Although the design writes ray (X,Y) at address `2·(16·Y + X)` as above, the testbench reads each result back using `mem_index = Y·16 + X·2` (not `Y·32 + X·2`). These two index formulas agree for Y=0 but diverge for Y≥1, so the readback walks a different, overlapping set of addresses than the full write map. The practical consequence for a contestant: the addresses your design must populate so that the testbench's readback matches the golden data are exactly the `Y·16 + X·2` (and `+1`) locations the testbench inspects. (Unspecified in source whether this asymmetry is intended; the testbench is authoritative, so target the addresses it actually reads.) The reference design in `initial.sv` writes at `2·(16·Y+X)` per the PDF; treat the testbench's indexing as the final arbiter of which words are checked.

**Golden data.** The testbench loads `00_TB/golden/golden_<RI>.memh` (e.g. `golden_5.memh` for RI=5) into a 512-word array and compares word-by-word over the 16×16 grid, applying the 1/64-unit distance tolerance per ray. RI defaults to 5 if not overridden at compile time; other RI values (the contest checks all of 2…15) are selected by defining `RI`. There may also be per-RI `golden_*_node.txt` files recording intermediate node values for debugging; because Verilog truncates fixed-point values, those debug numbers can differ slightly from a given design's internals.

---

## 6. Reference implementation (from `initial.sv`, `sqrt.v`, `div.v`)

`initial.sv` contains a **complete working reference** for module `TOP`, plus two helper modules it instantiates.

**Algorithm level.** It iterates the 256 grid points one at a time (X inner, Y outer). For each point it forms `X−8` and `Y−8` as a sign plus magnitude, raises the magnitudes to the 7th, 8th and 14th powers, builds the intermediate quantities B, C, D and the square-root term, then divides to get the fractional displacement and adds it to X (for zx) and Y (for zy). The displacement carries the correct sign from the sign of `X−8` / `Y−8`. Each result is written to SRAM in Q4.12, zx then zy.

The reference recasts the §2.4 math into integer-friendly quantities (comments in the file spell these out):

```
B     = 3·2^24 − X^8 − Y^8                          (always > 0, since 8^8 = 2^24)
Dsqrt = sqrt( (X^14 + Y^14 + 2^40)·(RI^2 − 1) + 2^40 )
C     = 2^20·Dsqrt − 2^40                            (> 0)
D     = 2^20·Dsqrt + X^14 + Y^14                     (> 0)
zx    = X − (X^7 · B · C) / (2^43 · D)
zy    = Y − (Y^7 · B · C) / (2^43 · D)
```

where X, Y here mean `X−8`, `Y−8`. The subtraction `X − (…)` plus the stored sign is how the outward bend is applied symmetrically about the center.

**Micro-architecture.** A two-always-block FSM (combinational next-state/datapath + clocked state) with states `IDLE → CONST → SQRT → CONST_2 → DIV → OUTPUT → (loop) → FINISH`:

- `IDLE`: latch `RI`; compute `|X−8|`, `|Y−8|` and their signs; start the power chain (squares, then x^3 and x^4 staged into temp regs).
- `CONST`: finish the powers (x^7 = x^3·x^4, x^8 = (x^4)^2, x^14 = (x^7)^2 for both X and Y); assert the square-root unit's input-valid.
- `SQRT`: wait for the `sqrt` unit; when its output is valid, form B, C, D from the root and the powers.
- `CONST_2`: form the big products `A·B·C` for X and Y (A = X^7 or Y^7) and start the divider with divisor D.
- `DIV`: wait for the divider; when valid, write `zx` to address `2·(16·Y+X)` with `WE`, and stage `zy` for the next cycle.
- `OUTPUT`: write `zy` to address `2·(16·Y+X)+1`; advance X (and Y when X wraps from 15); if both X and Y were 15, go to `FINISH`.
- `FINISH`: assert `DONE`.

`SRAM_D` is built as `(coordinate << 12) ± displacement`, i.e. it places the integer entry coordinate in the Q4.12 integer field and adds or subtracts the fractional displacement, giving the signed landing position in fixed point.

**`sqrt` helper.** A non-restoring integer square-root unit (`sqrt.v`): it takes a 52-bit input and iterates two input bits per cycle, comparing a running remainder against a trial value and building the root bit by bit. It deliberately stops early (after 13 of 26 iterations, then shifts the partial root left) to trade a few low-order bits of precision for speed, since the 1/64-unit tolerance absorbs the error. It signals `sqrt_out_valid` for one cycle when the (early-stopped) root is ready.

**`divider_optics` helper.** A radix-8 (3-bits-per-cycle) fixed-point divider (`div.v`) computing the Q4.12 value of `ABC / (2^43·D)`, implemented as `floor((ABC >> 31) / D)`. The 63-bit dividend is consumed three bits per cycle over 21 iterations; each cycle picks the largest multiple k·D (k = 1…7) that fits and emits octal quotient digit k. The low 16 bits of the quotient are the Q4.12 result; `div_out_valid` pulses when done. Two instances run in parallel for the X and Y displacements, sharing the divisor D.

---

## 7. Differences from the original problem (PDF vs. environment)

- **Top module is `TOP`** (instantiated as `u_REFRACT`), per the testbench; the PDF text names the design `REFRACT` / file `REFRACT.v`.
- **Design is entered via `initial.sv`** (which defines `TOP` plus the `sqrt`/`divider_optics` helpers), not `REFRACT.v` as the PDF appendix states.
- **Testbench file is `tb.sv`** (module `testfixture`), not `tb.v`.
- **Port names follow `tb.sv`/`initial.sv`:** `CLK`, `RST`, `RI`, `SRAM_A`, `SRAM_D`, `SRAM_Q`, `SRAM_WE`, `DONE` — matching the PDF table, with `RST` active-high asynchronous as the PDF states.
- **Golden files** are `00_TB/golden/golden_<RI>.memh`, loaded by `$readmemh`, selected by the `RI` define (default 5). The PDF appendix describes a `golden` directory with `golden_<RI>_node.txt` debug files; the authoritative pass/fail comparison uses the `.memh` arrays.
- **Acceptance is by distance tolerance, not exact match:** a ray passes if within 64/4096 = 1/64 unit of golden (testbench `TOLERANCE_RADIUS = 64`). The PDF's §2.9 states the same 1/64-unit rule.
- **Readback addressing quirk:** the testbench reads `mem[Y·16 + X·2]` while the reference design writes `2·(16·Y + X)`; these differ for Y ≥ 1. The testbench is authoritative for which words are checked (see §5 note).
- **`MAX_CYCLE` watchdog** (default 100000) will end simulation if `DONE` never asserts; not a functional requirement but affects how long a stuck design runs.
- Scoring grades (A/B/C), area/time scoring, submission/FTP steps, EDA tool versions, and report-file format from the PDF are omitted as irrelevant to solving and verifying the RTL.