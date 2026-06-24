# Circle-Coverage Set-Operation Counter Circuit — Design Specification

## 1. Overview

This module counts how many integer lattice points in an 8×8 grid are covered by a set-theoretic combination of up to three circles. Each circle is given by an integer center (x, y) and integer radius r; the set it defines is every grid point lying on or inside that circle. A 2-bit `mode` selects which set operation to evaluate (one circle, an intersection, a symmetric difference, or a three-circle inclusion-exclusion), and the module outputs the resulting element count on `candidate`. The top module is named **`TOP`**.

---

## 2. What the module must do (functional description)

### The grid and a single set

The coordinate space is an 8×8 integer grid: x and y each run from **1 to 8** inclusive (not 0-based). A circle with center (x1, y1) and radius r1 defines the set of all grid points (x, y) satisfying

```
(x − x1)² + (y − y1)² ≤ r1²,   with 1 ≤ x ≤ 8, 1 ≤ y ≤ 8, all integers.
```

That is, every lattice point on or inside the circle belongs to the set. `|A|` denotes the number of such points. The comparison uses `≤ r²` (squared, so no square roots are needed and points exactly on the circle count).

Up to three circles A, B, C are provided per operation, with centers (x1,y1), (x2,y2), (x3,y3) and radii r1, r2, r3.

### The four modes

`mode` is 2 bits and selects one of four computations:

**mode = 2'b00 — |A|.** Count the points covered by circle A alone. Only (x1, y1) and r1 are valid inputs.

*Worked example (from the source):* center A = (5, 5), r = 3. Sweeping the 8×8 grid and keeping points with `(x−5)²+(y−5)² ≤ 9` gives these 29 points:
(2,5), (3,3), (3,4), (3,5), (3,6), (3,7), (4,3), (4,4), (4,5), (4,6), (4,7), (5,2), (5,3), (5,4), (5,5), (5,6), (5,7), (5,8), (6,3), (6,4), (6,5), (6,6), (6,7), (7,3), (7,4), (7,5), (7,6), (7,7), (8,5). So **|A| = 29**.

**mode = 2'b01 — |A ∩ B|.** Count points covered by **both** A and B. Inputs (x1,y1,r1) and (x2,y2,r2) are valid.

*Worked example:* A = (5,5) r=3, B = (3,3) r=3. The intersection points are
(2,5), (3,3), (3,4), (3,5), (3,6), (4,3), (4,4), (4,5), (5,2), (5,3), (5,4), (5,5), (6,3) — so **|A ∩ B| = 13**.

**mode = 2'b10 — |(A ∪ B) − (A ∩ B)|** (the symmetric difference). Count points in exactly one of A or B, i.e. the union minus the intersection. Inputs (x1,y1,r1) and (x2,y2,r2) are valid.

*Worked example:* A = (5,5) r=3, B = (3,3) r=3. The symmetric-difference points are
(3,7), (4,6), (4,7), (5,6), (5,7), (5,8), (6,4), (6,5), (6,6), (6,7), (7,3), (7,4), (7,5), (7,6), (7,7), (8,5), (1,1), (1,2), (1,3), (1,4), (1,5), (2,1), (2,2), (2,3), (2,4), (3,1), (3,2), (4,1), (4,2), (5,1) — so the result is **30**.

Equivalently this equals |A| + |B| − 2·|A ∩ B|. (The reference computes it as |A| + |B| with intersection points subtracted twice; see §6.)

**mode = 2'b11 — |A∩B| + |B∩C| + |A∩C| − (A∩B∩C)·… ** the three-circle pairwise-overlap count. The exact expression the source gives is

```
(A∩B) + (B∩C) + (A∩C) − (A∩B∩C)
```

counted over grid points: add the three pairwise-intersection counts, then remove the triple-intersection contribution. Inputs for all three circles are valid.

*Worked example:* A = (5,5) r=3, B = (3,3) r=3, C = (6,2) r=2. The covered points are
(3,3), (4,3), (3,4), (2,5), (4,4), (3,5), (5,4), (4,5), (3,6), (5,5), (6,4), (7,3), (4,2), (5,1) — so the result is **14**.

A practical way to see mode 3: a grid point is counted exactly when it lies in **exactly two** of the three circles. (A point in only one circle contributes to no pairwise intersection; a point in all three is added three times by the pairwise sums and the −(A∩B∩C) term nets it to two… — the reference instead directly counts "in exactly two of the three," which yields the same 14; see §6 for the exact predicate used.)

### Bit-field packing of the inputs

The `central` input (24 bits) packs all three centers as nibbles, and `radius` (12 bits) packs the three radii:

```
central[23:20] = x1 (A.x)     radius[11:8] = r1 (A radius)
central[19:16] = y1 (A.y)     radius[7:4]  = r2 (B radius)
central[15:12] = x2 (B.x)     radius[3:0]  = r3 (C radius)
central[11:8]  = y2 (B.y)
central[7:4]   = x3 (C.x)
central[3:0]   = y3 (C.y)
```

Each coordinate and radius is a 4-bit unsigned value. Centers and radii are positive integers. (The grid is 1..8, so coordinates fit in 4 bits.)

---

## 3. Interface

Port names, widths, and reset polarity follow the authoritative harness (`tb.sv` / `initial.sv`). The top module is **`TOP`** (instantiated in the testbench as `u_set`).

| Signal | Dir | Width | Meaning |
|--------|-----|-------|---------|
| `clk`       | I | 1  | Clock; synchronous design, rising-edge triggered. |
| `rst`       | I | 1  | **Asynchronous** reset, active high (1 = reset). |
| `en`        | I | 1  | Input-valid. When 1, `central`/`radius`/`mode` are valid and a new operation should be latched. |
| `central`   | I | 24 | Three packed centers {x1,y1,x2,y2,x3,y3}, 4 bits each (see §2). |
| `radius`    | I | 12 | Three packed radii {r1,r2,r3}, 4 bits each. |
| `mode`      | I | 2  | Operation selector (00 = |A|, 01 = A∩B, 10 = symmetric difference, 11 = three-circle expression). |
| `busy`      | O | 1  | High while the module is computing; the host must wait for `busy=0` before issuing the next input. |
| `valid`     | O | 1  | High when `candidate` holds the valid result of the current operation. |
| `candidate` | O | 8  | The computed element count. |

### How the signals interact

The handshake is gated by `busy`. When the module is idle it holds `busy=0`. The host, seeing `busy=0`, presents `en=1` together with `central`, `radius`, and `mode`; on the next rising clock edge with `en=1` those inputs are latched and the module begins computing, raising `busy=1`. While busy, it sweeps the grid and accumulates the count for the selected mode. When finished, it raises `valid=1` and drives the count on `candidate` in the same cycle, then returns `busy` to 0 so the host can issue the next operation. `mode` is held fixed across a whole simulation run by the harness (one mode per run, selected at compile time), but the design reads it per operation.

---

## 4. Timing / protocol

The clock period is 10 ns in the harness, 50% duty. All design logic is on the **rising edge** of `clk`; reset is **asynchronous active-high** (`always @(posedge clk or posedge rst)`). Per the source's timing parameters, the reset pulse and each new-parameter pulse are each one clock period wide (`Treset = Tnt = Tcycle`).

### Reset

The testbench drives `rst=0` initially, then `rst=1` for ~3 cycles, then back to 0. On reset the module must clear its state, set `busy`/`valid` appropriately (the reference forces `busy=0` only in IDLE; during reset the count and coordinates are cleared and state returns to IDLE), and be ready to accept the first operation.

### Input handshake (figure-7 waveform as prose)

The testbench, on a falling clock edge, waits for `busy==0`, then asserts `en=1` and drives `central`/`radius` (and the fixed `mode`); it holds `en` for one clock period and then deasserts it. So: the host changes inputs around the negative edge while `busy` is low, and the design samples `en`/`central`/`radius`/`mode` on the rising edge. After issuing, the host waits for `valid==1`.

Concretely the reference latches inputs in its IDLE state when `en` is seen: it unpacks the nibbles into A/B/C center and radius registers, copies `mode`, and initializes the sweep's starting coordinate, then transitions to the compute state and raises `busy`.

### Output / completion (figure-7 waveform as prose)

When the sweep completes, the module enters its DONE state, asserts `valid=1`, and presents the accumulated count on `candidate` that cycle, then drops back to IDLE (clearing the counter) with `busy=0`. The testbench, after seeing `valid==1`, waits one falling edge and compares `candidate` against the expected value for that pattern, then proceeds to the next of the 64 patterns. A global timeout aborts the run if `valid` never arrives, and the run also stops early if 10 mismatches accumulate.

---

## 5. Data layout (patterns and expected results)

There is no addressable memory inside the design — operands arrive packed on `central`/`radius`. The relevant layout is the testbench's pattern/result files.

### Pattern files

The harness preloads 64 entries each from a `central` pattern file and a `radius` pattern file (hex), indexed 0..63. For each index k it drives `central_pat_mem[k]` and `radius_pat_mem[k]`, waits for the result, and compares `candidate` against `expected_mem[k]`. There is a separate expected-result file per mode, selected by the compile define:

| Mode (define) | mode value | Operation | Expected-result file |
|---------------|-----------|-----------|----------------------|
| MD1 | 2'b00 | |A| | candidate_result_Length |
| MD2 | 2'b01 | A ∩ B | candidate_united_result_Length |
| MD3 | 2'b10 | symmetric difference | candidate_diff_result_Length |
| MD4 | 2'b11 | three-circle expression | candidate_intersect_result_Length |

Exactly one mode is compiled per run (`+define+MD1`, etc.); the testbench sets `mode` accordingly and loads the matching expected file.

### Sample operation → result values (for a regression sanity-check)

From the worked examples in §2 (gold for a quick check):

| Mode | A | B | C | Result |
|------|---|---|---|--------|
| 00 (|A|) | (5,5) r3 | — | — | 29 |
| 01 (A∩B) | (5,5) r3 | (3,3) r3 | — | 13 |
| 10 (sym. diff) | (5,5) r3 | (3,3) r3 | — | 30 |
| 11 (3-circle) | (5,5) r3 | (3,3) r3 | (6,2) r2 | 14 |

---

## 6. Reference implementation

`initial.sv` contains a **working reference** implementation of `TOP`. Description follows.

### Algorithm level

The reference evaluates each mode by **brute-force grid sweep**: it walks integer coordinates over the relevant bounding region and, at each point, tests membership in the circles via the squared-distance comparison `(x−cx)² + (y−cy)² ≤ r²`, accumulating a count according to the mode's predicate. To save cycles it restricts the sweep to each circle's bounding box (clamped to the 1..8 grid) rather than always scanning the full grid, except mode 3 which scans the full 8×8.

### Micro-architecture

- **FSM:** three states `IDLE → CALC → DONE → IDLE`. `IDLE` holds `busy=0` and, on `en`, latches inputs and sets up the sweep. `CALC` performs the per-point sweep and accumulation. `DONE` asserts `valid`, outputs the count, and clears it.
- **Input unpack:** on `en` in IDLE, `central`/`radius` nibbles are unpacked into `Ax,Ay,Ar / Bx,By,Br / Cx,Cy,Cr` and `mode` is captured into `mode_r`.
- **Membership tests:** combinational `cmp1 = (distA² ≤ rA²)`, `cmp2 = (distB² ≤ rB²)`, `cmp3 = (distC² ≤ rC²)`, where `distA² = abs(Ax−x)² + abs(Ay−y)²`, etc. The `abs` function gives |a−b| on 4-bit operands.
- **Sweep bounds:** helper functions `start(center, r) = max(center − r, 1)` and `finish(center, r) = min(center + r, 8)` clamp each circle's bounding box to the grid. The sweep increments `x_coor` until it reaches the `finish` x, then resets to `start` x and increments `y_coor`, until the `finish` y is passed.
- **Per-mode accumulation:**
  - *mode 0:* sweep A's bounding box; `if(cmp1) count++`. Result = |A|.
  - *mode 1:* sweep the bounding box of the **smaller** circle (whichever of A,B has smaller radius); `if(cmp1 && cmp2) count++`. Result = |A∩B|.
  - *mode 2 (symmetric difference):* done in three stages via a `stage_r` counter — stage 0 sweeps A's box adding `cmp1` points (|A|), stage 1 sweeps B's box adding `cmp2` points (|B|), stage 2 sweeps the smaller circle's box and **subtracts 2** for each point in both (`cmp1 && cmp2`). Net result = |A| + |B| − 2|A∩B|, the symmetric difference.
  - *mode 3:* sweep the full 8×8 grid; increment when the point is in **exactly two** of the three circles (`cmp1&&cmp2&&!cmp3`, or `cmp1&&!cmp2&&cmp3`, or `!cmp1&&cmp2&&cmp3`). Result = the three-circle expression value.
- **Output:** `DONE` sets `valid=1`, `candidate = count_r`, then `count_w=0`, `stage_w=0`, and returns to IDLE.
- **Clock/reset:** all registers are `posedge clk` with asynchronous `posedge rst`; reset returns the FSM to IDLE, zeros the circle registers and `count`, sets the sweep coordinate to (1,1), and clears `stage`.

This is one valid solution (multi-cycle, bounding-box-optimized); the problem does not mandate this structure.

---

## 7. Differences from the original problem

- **Top module is `TOP`** (instance `u_set`), not the PDF's `SET` / `SET.v`. The environment wins.
- **Design entry point is `initial.sv`**, which defines `module TOP` and contains a complete working reference (described in §6).
- **Reset port is `rst`, active-high asynchronous** — matches the PDF's signal table; clock `clk`, and the data ports `en`/`central`/`radius`/`mode`/`busy`/`valid`/`candidate` all match the PDF as well.
- **Testbench file is `tb.sv`** (PDF appendix refers to `testfixture.v`), reading hex pattern/result files under `00_TB/dat/`, with one mode selected per run via `+define+MD1..MD4` and 64 patterns per run.
- **Cover-figure vs. example discrepancy (in the PDF itself):** the opening figure 1 describes A as center (3,3) r=2 and B as (5,5) r=3, but every worked example in §2.3 instead uses A=(5,5) r=3 (and B=(3,3) r=3). The examples are internally consistent and are what the counts derive from; figure 1 is just an illustrative picture with different numbers.
- **Omitted:** grading levels (A/B/C/D, cell-area and clock targets), submission/FTP steps, EDA tool-version lists, and SDF-annotation contest mechanics from the PDF are intentionally excluded as irrelevant to solving and verifying the RTL.