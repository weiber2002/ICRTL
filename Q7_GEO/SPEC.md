# Geofence Circuit — Design Specification

## 1. Overview

The geofence module decides whether a target point lies **inside or outside** a virtual fence formed by 6 receivers placed on a plane. Each receiver reports its own (X, Y) coordinate and its straight-line distance R to the target. From these 6 triples the module reconstructs the hexagonal fence and outputs a single bit, `is_inside`, with a `valid` strobe. The top module is named **`TOP`**.

The receivers are *not* delivered in fence (boundary) order, so the design must first sort them into convex-polygon order, then perform a geometric inside/outside test.

---

## 2. What the module must do (functional description)

The work has three conceptual stages: (1) order the 6 receivers around the fence, (2) measure the fence's area and the target's relationship to it, (3) decide inside vs. outside.

### 2.1 Ordering the receivers (cross-product sort)

The 6 receivers arrive in arbitrary order. To form the polygon boundary you must arrange them so consecutive vertices go consistently clockwise (or consistently counter-clockwise) around the fence. The method: pick one receiver as a reference origin, form vectors from it to the other 5, and sort those vectors by angular direction using the **2-D cross product** as the comparison.

For two vectors `A = (Ax, Ay) = (x1−x0, y1−y0)` and `B = (Bx, By) = (x2−x0, y2−y0)`, the cross product is

```
A × B = Ax·By − Bx·Ay
```

If `A × B < 0`, then B lies clockwise of A (the clockwise angle from A to B is < 180°); otherwise B is counter-clockwise of A. Sorting all the spokes by this relation puts the receivers into boundary order.

### 2.2 Inside/outside by area comparison

Once the vertices are in order, use an **area test**. Form 6 triangles, each made of the target point and one edge of the fence (one polygon side). Sum the 6 triangle areas. Then compare that sum to the area of the hexagon itself:

- If the sum of the 6 triangle areas **> hexagon area**, the target is **outside** the fence.
- Otherwise (sum ≤ hexagon area), the target is **inside**.

Intuitively: if the point is inside a convex polygon, the triangles fanned out to each edge exactly tile the polygon (sum = polygon area). If the point is outside, the triangles overhang and their total exceeds the polygon area.

**Triangle area (Heron's formula).** For a triangle with side lengths a, b, c, let `s = (a + b + c)/2`. Then

```
area = √( s(s−a)(s−b)(s−c) )  =  √(s(s−a)) · √((s−b)(s−c))
```

The source deliberately splits the single 4-factor square root into the **product of two smaller square roots**, because one direct 40-bit-wide sqrt costs too much area; two ~20-bit sqrts are smaller, at some cost in precision. (The provided `sqrt` unit is 24-bit-in / 12-bit-out — see §6.)

Here a, b, c are the three side lengths of each target-to-edge triangle: two of them are receiver-to-target distances R (the two endpoints of the edge), and the third is the edge length itself between the two adjacent receivers, `c = √(dx² + dy²)`.

A caution from the source: when three points are nearly collinear, truncation error can make the value under the square root come out **negative**; the design must guard against this (clamp to 0 rather than take a root of a negative number).

**Hexagon area (shoelace formula).** For a polygon with vertices in counter-clockwise order `(x0,y0), (x1,y1), … (x_{n−1},y_{n−1})`, the area is

```
area = ½ · Σ (x_i·y_{i+1} − x_{i+1}·y_i)   (indices wrap; x_n ≡ x_0)
```

For n = 6 specifically:

```
area = ½ · [ (x0·y1 − x1·y0) + (x1·y2 − x2·y1) + (x2·y3 − x3·y2)
           + (x3·y4 − x4·y3) + (x4·y5 − x5·y4) + (x5·y0 − x0·y5) ]
```

If the vertex order happens to be clockwise instead, this sum comes out negative (so its sign also tells you the winding; take the magnitude for area).

### 2.3 Guarantees that simplify the problem

The test patterns are constrained so a designer need not handle the hard cases:
- The receiver coordinates always form a **convex** hexagon — no concave shapes and no three collinear receivers.
- Every target sits **more than 5 distance units** away from the nearest fence edge, reducing borderline numerical decisions.
- R is an integer and therefore carries up to ~1 unit of rounding error versus the true distance; an alternative design must keep that tolerance in mind.

Designs must implement the general algorithm; hard-coding answers for specific known patterns is prohibited.

---

## 3. Interface

Port names, widths, and reset polarity follow the authoritative harness (`tb.sv` / `initial.sv`). The top module is **`TOP`** (the testbench instantiates it under the instance name `u_geofence`).

| Signal | Dir | Width | Meaning |
|--------|-----|-------|---------|
| `clk`        | I | 1  | Clock; synchronous design on the **rising edge**. |
| `reset`      | I | 1  | **Active-high, asynchronous** reset. Testbench holds it High ~2 cycles, then drops it. |
| `X`          | I | 10 | A receiver's x-coordinate. |
| `Y`          | I | 10 | A receiver's y-coordinate. |
| `R`          | I | 11 | Distance from that receiver to the target. |
| `is_inside`  | O | 1  | 1 if the target is inside the fence, 0 if outside. Meaningful only when `valid` is High. |
| `valid`      | O | 1  | Output strobe: when High, `is_inside` is valid this cycle. Must be Low out of reset and must return Low after each result. |

### How the signals interact

The three input ports `X`, `Y`, `R` form one receiver's data per cycle; 6 consecutive cycles deliver one complete target scene (6 receivers). There is no input handshake — the host simply presents the 6 triples in order. After the 6th receiver, the host waits. When the module finishes computing, it raises `valid` High for exactly one cycle and presents `is_inside` in that same cycle, then drops `valid` Low again. The host reads the result on the `valid` cycle and begins streaming the next scene's 6 receivers on the following cycles.

Successive scenes are fully independent: treat each new set of 6 receivers (coordinates and distances) as a brand-new problem with no carry-over.

---

## 4. Timing / protocol

The clock period is 50 ns in the harness, toggling every half period; all design logic is on the **rising edge** of `clk`. Reset is asynchronous active-high (`always @(posedge clk or posedge reset)`).

### Reset

The testbench raises `reset` shortly after a rising edge, holds it High for two clock periods, then drops it after a rising edge. On reset the design must clear its state and force `valid` Low so the host never mistakes stale output for a result.

### Input phase (figure-3 waveform as prose)

Note a subtlety of this harness: **the testbench drives `X`/`Y`/`R` on the falling edge (`negedge clk`)**, while the design samples them on the rising edge. So each receiver's data is set up half a cycle before the rising edge that captures it. After `reset` deasserts, the host presents receiver 1 on the next driving edge, receiver 2 on the following one, and so on, one receiver per cycle for 6 cycles. (The testbench tracks an input counter and only begins waiting for `valid` after the 6th receiver has been presented.)

### Output phase (figure-3 waveform as prose)

When the computation completes, the design raises `valid=1` and drives `is_inside` in the **same** cycle, holding both for one cycle, then returns `valid` to 0 on the next cycle. The testbench samples `valid` on the rising edge; when it sees `valid` High it latches `is_inside`, compares it against the golden inside/outside answer for that object, and then resumes feeding the next scene. After all objects in the pattern file are consumed, the testbench prints a pass/fail tally and finishes. There is a global timeout (the run aborts if `valid` never arrives within the cycle budget), so the design must always converge.

---

## 5. Data layout (pattern / scene format)

There is no addressable memory in this design — data streams in over the ports. The relevant layout is how the testbench's pattern file maps to scenes, and how each scene maps to the 6 receivers.

### Scene/object format

The pattern file (`grad.data`) is a sequence of objects. Each object begins with a header line `object <id> <is_inside_golden>` (the golden answer, 1 = inside, 0 = outside), followed by **6 lines of three integers** `X Y R`, one per receiver, in arbitrary boundary order. Lines beginning with `//` are comments and skipped. Objects are processed in file order; the harness reports each object's id, the golden answer, and the returned answer, then a final `Pass = N, Fail = M` summary.

### Coordinate / distance ranges

X and Y are 10-bit unsigned (0–1023); R is 11-bit unsigned (0–2047, though physically bounded by the playfield diagonal). Coordinates in the sample scenes run roughly 20–1021 in each axis.

### Sample scene values (for a regression sanity-check)

From the source's worked test figures (each scene is one target with 6 receivers; the parenthesized points are the 6 receiver coordinates, the bare "x,y" points are fence corners drawn in the figure):

- Object 16 — receivers near (898,992), (300,910), (220,720), (20,625), (500,675), (1021,680) … — golden answer per the pattern file.
- Object 12 — among the same scene group (test figure one), target O12 at (500,675).
- Object 47 at (130,80), Object 3 at (140,160), Object 20 at (220,320) appear *inside* their fence in test figure one; objects drawn outside the red boundary are *outside*.

(The exact golden inside/outside bit for each of the 50 objects lives in `grad.data`; the figures only show their geometry. The numeric receiver tables are not reproduced in full here because the harness reads them straight from the pattern file.)

The full pattern set contains **50 objects**, numbered 1–50 in simulation order, grouped across four test figures.

---

## 6. Reference implementation

The environment provides a complete, working reference: `TOP` in `initial.sv`, plus a helper `sqrt` module in `sqrt.v`. The contestant may replace `TOP` (and is encouraged to minimize area). Description follows.

### `sqrt` helper (sqrt.v)

A non-restoring/​digit-by-digit integer square-root unit: **24-bit input, 12-bit output** (floor of √, with a final round-up when the remainder exceeds the root). It is a 2-state machine (`IDLE`/`CALC`): assert `sqrt_in_valid` with the radicand on `sqrt_in`, and after ITER = 12 iteration cycles it pulses `sqrt_out_valid` with the result on `sqrt_out`. Reset is asynchronous active-high (the design wires `TOP`'s `reset` into the sqrt's `rst`). The geofence design shares this single sqrt unit across all square-root needs (edge length and both Heron half-roots) to save area.

### `TOP` — algorithm level

The reference reads 6 receivers, bubble-sorts them into convex order by the cross-product comparison, computes the hexagon area via the shoelace sum, then for each of the 6 edges computes the target-to-edge triangle area by Heron's formula (using the shared sqrt three times per edge: once for the edge length, twice for the split Heron roots), accumulates the 6 triangle areas, and finally compares the triangle sum against the polygon area to drive `is_inside`.

### `TOP` — micro-architecture

- **FSM** (`state_t`): `IDLE → INPUT → SORT → POLY → EDGE_REQ → EDGE_WAIT → HERON_REQ1 → HERON_WAIT1 → HERON_REQ2 → HERON_WAIT2 → TRI_ACC → OUTPUT → IDLE`. The EDGE/HERON request/wait pairs hand work to the shared sqrt and spin until `sqrt_out_valid`; `TRI_ACC` loops back to `EDGE_REQ` for the next of the 6 edges (via `cal_count`), and after the 6th edge proceeds to `OUTPUT`.
- **Input capture & reference pick:** `IDLE`/`INPUT` latch the 6 incoming triples into `X_r[0..5]`, `Y_r[0..5]`, `R_r[0..5]`. As they arrive, the design keeps the lowest-Y (tie-break lowest-X) receiver in slot 0 as the sort origin.
- **Sort:** `SORT` is a bubble sort over slots 1..5 using `cross_product(...)` (the `Ax·By − Bx·Ay` sign test) as the ordering predicate, swapping adjacent receivers until they wind consistently around slot 0. Counters `sort_count`/`sort_loop_count` sequence the passes.
- **Polygon area:** `POLY` accumulates the shoelace sum `Σ (x_i·y_{i+1} − x_{i+1}·y_i)` into `poly_area_r` (a signed accumulator that equals 2× the hexagon area; the factor of 2 is kept consistently on both sides of the final comparison so it cancels). The `mult` function computes each `x_i·y_{i+1} − x_{i+1}·y_i` term.
- **Edge length:** `EDGE_REQ`/`EDGE_WAIT` compute `c = √(dx² + dy²)` for the current edge by feeding `dx*dx + dy*dy` to the sqrt; result stored in `edge_c_r`.
- **Heron, split roots:** with `a = R[idx0]`, `b = R[idx1]`, `c = edge_c`, and `s = (a+b+c) >> 1`, the design forms `s(s−a)` and `(s−b)(s−c)`, each **clamped to 0 if negative** (the collinearity guard), takes their square roots in the two HERON request/wait pairs, multiplies the two roots, doubles the product, and accumulates into `tri_sum_r`. (Doubling matches the 2× scaling carried in the polygon area.)
- **Decision:** `OUTPUT` asserts `valid=1` and sets `is_inside = (tri_sum_r > poly_area_r) ? 0 : 1` — triangle sum greater than polygon area means outside. It then clears all accumulators/counters and returns to `IDLE` with `valid` dropping back to 0.
- **Helpers:** `cross_product` returns the sign test `Ax·By > Bx·Ay`; `mult` returns the signed shoelace term. Both treat the 10-bit coordinates as non-negative and widen to signed for the subtraction.
- **Clock/reset:** all state is `posedge clk` with asynchronous `posedge reset`; reset returns the FSM to `IDLE`, zeros the receiver arrays and all accumulators, and (combinationally) holds `valid` Low.

This is one valid area-oriented solution; the problem does not mandate this structure, and the source explicitly invites alternative methods as long as the function is correct.

---

## 7. Differences from the original problem

- **Top module is `TOP`** (instance `u_geofence` in the testbench), not the PDF's `geofence` / `geofence.v`. The environment wins.
- **Design entry point is `initial.sv`**, which defines `module TOP` and contains a complete working reference (described in §6), alongside the provided `sqrt.v` helper.
- **Inputs are driven on the falling edge.** The testbench sets `X`/`Y`/`R` on `negedge clk` while the design samples on `posedge clk`; the PDF's waveform doesn't make the driving edge explicit. Port names and reset polarity otherwise match the PDF (`clk`, `reset` active-high async, `X`/`Y`/`R`, `valid`, `is_inside`).
- **Pattern file is `grad.data`** read by `tb.sv`, with the `object <id> <golden>` + 6×`X Y R` line format and `//` comments; the harness selects nothing at compile time (single pattern file, 50 objects).
- **A shared 24-in/12-out `sqrt` unit is provided** (`sqrt.v`) and instantiated by the reference; the PDF only describes the math, not this exact interface.
- **Omitted:** grading levels (A/B/C/D, the 50ns clock and area targets), submission/FTP steps, EDA tool-version lists, DesignWare-submission notes, and SDF-annotation mechanics from the PDF are intentionally excluded as irrelevant to solving and verifying the RTL.