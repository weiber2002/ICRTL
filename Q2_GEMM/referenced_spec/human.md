
---

# Human-Readable I/O-Only Spec — `systolic`

## 1) Module

* **Name**: `TOP`
* **Clock**: `clk`, rising-edge.
* **Reset**: `rst`, **asynchronous, active-high**.

  * While `rst=1`: internal state is cleared; `o_valid=0`;
  * On `rst` deassert (1→0): module is ready to accept a new tile per the rules below.

> All ports are **1-D flattened** (no multi-dimensional arrays on the port list).

## 2) Ports (I/O only)

### 2.1 Control & Clock

* `input  clk`
* `input  rst`
* `input  tile_en` — **load enable**; must be **1 for four consecutive cycles** to provide **one tile**.

### 2.2 Data Inputs (sampled only when `tile_en=1`)

* `input  [15:0] tileA_data_0`
* `input  [15:0] tileA_data_1`
* `input  [15:0] tileA_data_2`
* `input  [15:0] tileA_data_3`
* `input  [15:0] tileB_data_0`
* `input  [15:0] tileB_data_1`
* `input  [15:0] tileB_data_2`
* `input  [15:0] tileB_data_3`

**Sampling rule:** On each **posedge** with `tile_en=1`, sample all eight inputs above. **Exactly four consecutive** such cycles constitute one complete tile load (32 total 16-bit values).

### 2.3 Data Outputs (valid only when `o_valid=1`)

* `output reg [15:0] tileO_data_0`  … `tileO_data_15`

**Mapping:** `tileO_data_(4*r + c)` corresponds to output element at row `r`, column `c`, with `r,c ∈ {0..3}` (row-major).

### 2.4 Completion Pulse

* `output reg o_valid` — **one-cycle pulse**; when `o_valid=1`, **all** `tileO_data_*` are valid and stable in that same cycle.

## 3) Timing Contract (externally observable)

1. **Load phase**

   * One tile **must** be provided by **four consecutive** cycles with `tile_en=1`.
   * Inputs are sampled on each **posedge** of those four cycles.

2. **Output validity**
   * `o_valid` is **one clock** wide; all `tileO_data_*` are valid and stable in that cycle only.
   * `tileO_data_*` are considered valid **only** in the cycle where `o_valid=1`.
   * Outside that cycle, `tileO_data_*` may be don’t-care.

## 4) **Critical rule after completion**

* The **cycle immediately after** `o_valid` assert `tile_en=1`.
* **If** `tile_en=1` in that cycle, it **must be accepted** as the **first load cycle of the next tile**.

## 5) Interface assumptions

* No other ready/valid or back-pressure signals exist.
* Inputs during `rst=1` are ignored; outputs/`o_valid` have no meaning during `rst=1`.
* Internal implementation is unconstrained; only this **I/O and timing** contract will be verified.

---
