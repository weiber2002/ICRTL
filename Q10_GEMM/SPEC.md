# 4×4 Systolic Tile Multiplier  — Design Specification

## 1. Overview

`TOP` is a 4×4 systolic processing-element (PE) array that computes the matrix product of one 4×4 tile of A by one 4×4 tile of B, accumulating across however many tile-loads it is fed, and emitting a 4×4 result tile. It is the inner compute engine of a larger tiled matrix-multiply system: a surrounding controller (`TOP_Control`, supplied by the environment) handles instruction decode, full-matrix storage, tiling, and output readback, and drives `TOP` one 4-row strip at a time. The arithmetic is **signed fixed-point with saturation**, not a plain integer product — this is the single most important thing to get right and is detailed in §2.

The module the contestant writes is **`TOP`**. The testbench does **not** instantiate `TOP` directly; it instantiates `TOP_Control`, which instantiates `TOP` internally and connects exactly the flattened ports listed in §3.

---

## 2. What the module must do (functional description)

### The computation, intuitively

`TOP` holds a 4×4 array of multiply-accumulate PEs, indexed `PE[r][c]` for `r,c ∈ {0..3}`. PE `[r][c]` is responsible for output element O[r][c]. Over the course of one tile computation, each PE receives a stream of (a, b) pairs, forms the product `a·b`, and **adds it into a running accumulator**. After the stream ends, every PE holds the dot product of one row of A with one column of B.

A single "tile" is loaded over **four consecutive cycles** with `tile_en=1`. Each of those four cycles delivers:
- one row of the A-tile: `tileA_data_0..3` = A[k][0..3] on load-cycle k (k = 0..3), and
- one row of the B-tile: `tileB_data_0..3` = B[k][0..3] on load-cycle k.

So after four load cycles the module has the full 4×4 A-tile and 4×4 B-tile. It then multiplies them (`O += A · B`) and produces the 4×4 result. Because the accumulator is not cleared between successive tile computations until the result is read out, feeding multiple tiles in sequence accumulates their partial products — this is how the controller builds larger (8×8, 16×16) products out of 4×4 tiles, by streaming the K-dimension tiles one after another into the same array before reading O.

### The arithmetic — signed, fixed-point, saturating

Each PE accumulates in a **36-bit signed** accumulator:

```
acc ← acc + a · b        (a, b are signed 16-bit; product is signed 32-bit; accumulated in 36 bits)
```

On output, the accumulator is **rescaled and saturated** into a signed 16-bit result — it is *not* simply truncated to the low 16 bits. The reference behavior is:

- Treat the operands as a signed **Q-format** fixed-point: the output keeps bits `[29:15]` of the accumulator (an effective arithmetic right shift by 15), prepended with the sign bit.
- Saturation bounds: let `POS_MAX = 2^30 − 1` and `NEG_MAX = −2^30`.
  - If `acc > 0` and `acc ≥ POS_MAX` → output `0x7FFF` (max positive).
  - If `acc > 0` and `acc < POS_MAX` → output `{1'b0, acc[29:15]}` (sign bit 0, then 15 magnitude bits).
  - If `acc ≤ 0` and `acc ≤ NEG_MAX` → output `0x8000` (max negative).
  - If `acc ≤ 0` and `acc > NEG_MAX` → output `{1'b1, acc[29:15]}` (sign bit 1, then bits 29..15).

In words: the 16-bit output is the sign bit concatenated with accumulator bits 29 down to 15, clamped to `0x7FFF` / `0x8000` when the magnitude reaches `2^30`. A correct design must reproduce this rescale-and-saturate exactly, because the golden vectors are generated from it.

### Output tile mapping

The 16 output ports carry the 4×4 result in **row-major** order:

```
tileO_data_(4*r + c)  =  O[r][c],   r,c ∈ {0..3}
```

So `tileO_data_0..3` is output row 0, `tileO_data_4..7` is row 1, `tileO_data_8..11` is row 2, `tileO_data_12..15` is row 3.

### Input tile mapping (per load cycle)

On each `tile_en` cycle, the four A inputs are one **row** of the A-tile and the four B inputs are one **row** of the B-tile. Over load cycles 0→3:

```
load cycle 0:  tileA_data_0..3 = A row 0 ;  tileB_data_0..3 = B row 0
load cycle 1:  tileA_data_0..3 = A row 1 ;  tileB_data_0..3 = B row 1
load cycle 2:  tileA_data_0..3 = A row 2 ;  tileB_data_0..3 = B row 2
load cycle 3:  tileA_data_0..3 = A row 3 ;  tileB_data_0..3 = B row 3
```

(Internally a systolic array consumes A by rows and B by columns; mapping the loaded rows to the correct PE feed order is part of the design. The reference implementation stores the loaded data into skewed buffers and then plays it into the array over several cycles — see §6.)

---

## 3. Interface

The `TOP` port list is taken from the authoritative `initial.sv` / the `TOP_Control` instantiation in the harness. All data ports are 16 bits; control ports are 1 bit. Note that the harness connects the multi-dimensional tile signals as **flattened scalar ports** (no packed arrays on the port list).

| Signal | Dir | Width | Meaning |
|--------|-----|-------|---------|
| `clk`            | I | 1  | System clock. All logic is on the **rising edge**. |
| `rst`            | I | 1  | **Active-high, asynchronous** reset. Clears state; `o_valid` goes 0. (See Differences: the draft called this synchronous.) |
| `tile_en`        | I | 1  | Tile-load enable. Asserted **four consecutive cycles** to load one complete tile (one A row + one B row sampled each cycle). |
| `tileA_data_0..3`| I | 16 | One row of the A-tile (signed). Sampled on each `tile_en` cycle. |
| `tileB_data_0..3`| I | 16 | One row of the B-tile (signed). Sampled on each `tile_en` cycle. |
| `tileO_data_0..15`| O | 16 | The 4×4 result tile, row-major (`tileO_data_(4r+c) = O[r][c]`), signed/saturated. Valid when `o_valid=1`. |
| `o_valid`        | O | 1  | Output-valid. When High, all 16 `tileO_data_*` are valid and stable in that cycle. |

### How the signals interact

The controller drives `tile_en` High for four cycles to load a tile; `TOP` samples `tileA_data_*`/`tileB_data_*` on each of those rising edges. After enough tiles have been loaded and the array has finished propagating, `TOP` raises `o_valid` and presents the 4×4 result on `tileO_data_*`. There is no input back-pressure and no ready/valid handshake beyond `tile_en` (input) and `o_valid` (output): the controller is responsible for timing, and `TOP` must meet the propagation latency described in §4.

The accumulator inside the array is cleared in conjunction with output (the reference clears each PE accumulator in the same state that asserts `o_valid`). Practically: read the result on the `o_valid` cycle; a fresh accumulation begins for the next tile group afterward.

---

## 4. Timing / protocol

Clock toggles every half-period; the harness cycle period is 4.4 ns. All sequential logic in `TOP` and `TOP_Control` is on `posedge clk`, with `posedge rst` for asynchronous reset. The controller drives `TOP`'s inputs from its own state machine; the testbench changes controller-facing stimulus on `negedge clk`.

### Reset

`rst` is asserted High briefly at the start of simulation (the clock generator drives `rst=1` for half a reset-delay window, then `rst=0`). On reset, `TOP` clears its state machine to its initial (loading) state, zeros its input buffers and PE accumulators, and drives `o_valid=0`. Reset is asynchronous: the reset branch is in an `always @(posedge clk or posedge rst)` block.

### Load phase (`tile_en`)

1. The controller asserts `tile_en=1` and presents A row 0 / B row 0; `TOP` samples them on the rising edge.
2. `tile_en` stays High for three more cycles, presenting rows 1, 2, 3. After the fourth load cycle the full 4×4 A-tile and B-tile are captured.
3. A complete tile is therefore **exactly four consecutive `tile_en=1` cycles** (32 sampled 16-bit values total).

### Compute / propagation latency

After the four loads, the array enters a compute phase during which operands propagate through the systolic mesh and each PE multiply-accumulates. The reference array uses a fixed propagation schedule: it feeds skewed operands for several cycles and reaches its terminal propagation count at internal step 11 before producing output, i.e. there is a multi-cycle latency (on the order of ~8 propagation cycles plus the load cycles) between the last load and `o_valid`. A correct design need not match the exact cycle count, but it must hold `o_valid` low until its result is fully formed and stable, then assert it.

### Output phase (`o_valid`)

1. When the result tile is ready, `TOP` raises `o_valid=1` and drives all 16 `tileO_data_*` with the row-major result. The values are valid and stable in the cycle(s) `o_valid` is High.
2. Outside the `o_valid` window, `tileO_data_*` are don't-care.
3. The PE accumulators are cleared in the same phase that emits the output, so the array returns to its loading state ready for the next tile group.

### What the controller does with the output

(For context — the controller is part of the environment, not something the contestant writes.) After `TOP` asserts its readiness up the chain, `TOP_Control` raises `ap_done`, then reads the assembled full-matrix result out element-by-element over `addr_O = 0..255` with `en_O`, presenting each on `data_O`/`out_valid` for the testbench to compare against the golden `matrix*_O.hex`. A full output matrix is 256 elements (16×16), assembled from the 4×4 tiles `TOP` produced.

---

## 5. Memory / data layout

`TOP` itself is memoryless from the system's point of view — it holds only the current tile(s) and accumulators. The data layout that matters is how tiles map to elements, and how the surrounding system assembles full matrices. (The full-matrix storage lives in the controller; described here so the tile semantics are unambiguous.)

### Tile element order

- A-tile and B-tile are each 4×4, delivered one row per `tile_en` cycle (§2).
- The output tile is 4×4, row-major on `tileO_data_0..15` (`index = 4·row + col`).

### Full-matrix assembly (controller side, for context)

The system processes three test matrices per run, selected by an instruction stream:

- Instruction memory `inst.hex` holds up to four 6-bit instruction codes; a code of **0** terminates the run.
- The instruction value encodes the matrix size / tile count: the controller branches on instruction values **4**, **8**, and **16** (a 4×4 single tile, a 8×8 = 2×2 tiles, and a 16×16 = 4×4 tiles, respectively), walking `tile_row_num`/`tile_col_num` across the tile grid and accumulating K-dimension tiles into each output tile before reading it out.
- A full A or B matrix is stored as 64 entries (`matrix*_A.hex`, `matrix*_B.hex`), addressed `0..63`. A full output matrix is 256 entries (`matrix*_O.hex`), addressed `0..255`, row-major over a 16×16 grid (`addr_O = 16·row + col`).
- Output element O[r][c] of the full matrix is written from tile output via
  `matrixO[(4·tile_row + i)·16 + 4·tile_col + j] = tileO_data[4·i + j]`,
  which is the row-major placement of each 4×4 tile into the 16×16 result.

### Sample data files (for regression)

The harness loads, per the three tests: `matrix{1,2,3}_A.hex`, `matrix{1,2,3}_B.hex` (64 signed 16-bit values each), and compares the computed output against `matrix{1,2,3}_O.hex` (256 signed 16-bit values each). `inst.hex` supplies the per-test instruction codes. (Specific element values are not reproduced here; they live in those `.hex` files and are the golden reference for `data_O` comparison.)

---

## 6. Reference implementation

`initial.sv` contains a **working reference** of both `TOP` (the systolic array) and `TOP_Control` (the wrapper). The contestant replaces/optimizes `TOP`; `TOP_Control` is environment.

### `TOP` — algorithm level

`TOP` is a 4×4 mesh of `PE` cells implementing a weight/data-propagating systolic multiply-accumulate. It loads a tile over four `tile_en` cycles into skewed internal buffers (`tileA_r[0:27]`, `tileB_r[0:27]` — 28 entries, sized for the diagonal skew), then plays the operands into the mesh over a fixed propagation schedule, accumulating products in each PE. When propagation completes it asserts `o_valid` and exposes each PE's saturated accumulator on the corresponding `tileO_data_*`.

### `TOP` — micro-architecture

- **FSM:** three states `LOADING → COMPUTE → DONE → LOADING`. `LOADING` captures the four tile rows (counter `load_num_r` 0→3, advancing on `tile_en`); transition to `COMPUTE` happens when `tile_en && load_num_r==3`. `COMPUTE` advances a `propagate_num_r` counter and feeds skewed operands until `propagate_num_r==11`, then goes to `DONE`. `DONE` raises `o_valid`, clears the PE accumulators, and returns to `LOADING`.
- **Skewed buffers:** during `LOADING`, the four A inputs of load-cycle k are written to `tileA_w[8k .. 8k+3]` and the four B inputs to a strided pattern (`tileB_w[k], [8+k], [16+k], [24+k]`), arranging the data for diagonal injection. During `COMPUTE`, for propagation steps 0..6 the array reads `tileA_r[i*7 + step]` and `tileB_r[i*7 + step]` for row `i`, gating `PE_en` so each PE accumulates one product per step.
- **PE cell:** each `PE` has a signed 16-bit `a` and `b` register pair that propagate to neighbors (`next_a`, `next_b`), and a signed **36-bit** accumulator `o_r`. On `PE_en` it does `o_r ← o_r + a*b`; on `PE_clear` it zeros the accumulator; on `PE_out` it drives the saturated 16-bit result `o` per the rescale/saturate rule in §2 (`o_r[29:15]` with sign bit, clamped to `0x7FFF`/`0x8000` at ±2^30). Input registers update only when `PE_input_gate` (active in LOADING/COMPUTE with `PE_en`) is set.
- **Array wiring:** the 16 PEs are connected in the classic 4×4 systolic pattern — A operands propagate left-to-right along each row (`next_a` of one PE feeds `a` of the next), B operands propagate top-to-bottom down each column (`next_b` feeds the PE below). Top-row PEs take `tileB_in[c]`; left-column PEs take `tileA_in[r]`.
- **Clock/reset:** all registers are `posedge clk` with asynchronous `posedge rst`; reset returns the FSM to `LOADING`, zeros buffers, counters, and accumulators.

### `TOP_Control` — wrapper (environment, descriptive only)

`TOP_Control` decodes the instruction stream, stores full A/B matrices (`matrixA_r[0:63]`, `matrixB_r[0:63]`) and the output matrix (`matrixO1_r[0:255]`), and drives `TOP` tile-by-tile. Its own FSM (`IDLE → LOADING → FILLING → COMPUTE → DONE → FINISH`) loads matrices during `LOADING`, asserts `tile_en` for four cycles during `FILLING` (feeding the appropriate A-row-block and B-column-block slices to `TOP`), waits for `TOP`'s `o_valid` in `COMPUTE` to capture the 4×4 tile into the full output matrix, advances `tile_row_num`/`tile_col_num` according to the instruction (4/8/16), and in `DONE` streams the 256-element result out over `addr_O`/`en_O`/`data_O`/`out_valid`. `ap_done` is asserted while in `DONE`; a zero instruction sends it to `FINISH`.

---

## 7. Differences from the original draft / problem

- **Device under test is `TOP`, instantiated inside `TOP_Control`.** The testbench instantiates `TOP_Control` (provided in `initial.sv`), which instantiates the contestant's `TOP`. The draft described `TOP` in isolation, which is correct for the port contract but omitted that the harness exercises it only through the wrapper.
- **Reset is asynchronous active-high, not synchronous.** The draft stated "Synchronous, active-high"; both `TOP` and `TOP_Control` use `always @(posedge clk or posedge rst)`. The environment wins: reset is asynchronous.
- **Data is signed; output is rescaled-and-saturated, not a raw product.** The draft's I/O contract implied plain 16-bit values with no arithmetic semantics. The reference `PE` is signed, accumulates in 36 bits, and outputs `acc[29:15]` with sign bit and saturation to `0x7FFF`/`0x8000` at ±2^30. This is essential to match the golden vectors and was absent from the draft.
- **Accumulation across tile-loads.** The draft treated one tile as one independent multiply. In reality the array accumulates across successively loaded tiles (the K-dimension) and only clears on output, which is how 8×8/16×16 products are built from 4×4 tiles.
- **Compute/propagation latency exists between load and `o_valid`.** The draft's timing section jumped straight from load to a one-cycle output pulse. The real array has a multi-cycle systolic propagation phase (reference: through internal step 11) before `o_valid`.
- **"Critical rule after completion" (draft §4) is not a `TOP`-level contract.** Back-to-back tile acceptance is managed by `TOP_Control`'s FSM, not by a `tile_en`-in-the-cycle-after-`o_valid` rule on `TOP`. Described as controller behavior instead.
- **Clock period is 4.4 ns** (`CYCLE = 4.4`) in this harness, and the runtime guard is `MAX_CYCLE` = 5000 cycles.
- **Verification path:** results are checked by `TOP_Control` reading 256 elements per test over `addr_O`/`data_O`/`out_valid` against `matrix{1,2,3}_O.hex`, across up to three instruction-selected tests; a zero instruction ends the run. The contestant's `TOP` is judged indirectly through these comparisons.
- **Omitted:** any scoring/area/timing-grading and submission/tooling metadata are not part of this spec, as they don't help solve or verify the RTL.