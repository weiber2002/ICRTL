# Human-Readable Spec (LBP Accelerator)

## 1. Goal & Scope

Design an RTL hardware module **LBP** that:

* Reads an **8-bit** grayscale image from a host memory interface (**gray\_mem**, 128×128, linear address 0…16383).
* Computes **Local Binary Pattern (LBP)** for every pixel independently using a **3×3, 8-neighbor** definition.
* Writes each 8-bit result to a host memory interface (**lbp\_mem**, 128×128, address-aligned 1:1 with the source pixel).
* Sets **`finish=1`** when all required pixels are written.
* Excludes appendices and scoring/benchmark rules—this is a **functional** spec sufficient to implement and verify correctness.

## 2. Top-Level Module & Ports

**Module name:** `TOP`
**Clocking:** rising-edge synchronous (`clk`).
**rst:** `rst` is **active-high Synchronous**; design must reach a defined idle state after deassertion.

**Ports**

* `clk` (input, 1b): system clock, positive-edge synchronous.
* `rst` (input, 1b): Synchronous, active-high; initialize internal state when asserted; leave in a clean idle when deasserted.
* `gray_addr` (output, **14b**): read address to `gray_mem` (0…16383). **At most one address may be requested per clock cycle.**
* `gray_req` (output, 1b): read-request enable for `gray_mem`.
* `gray_ready` (input, 1b): host indicates `gray_mem` can accept requests. **Do not issue reads unless `gray_ready=1`.** If it ever deasserts, pause issuing new requests until it reasserts.
* `gray_data` (input, **8b**): data returned by host for the address requested.
* `lbp_addr` (output, **14b**): write address to `lbp_mem` (0…16383).
* `lbp_valid` (output, 1b): write-enable; when high, `lbp_addr` and `lbp_data` are valid and must be written by the host.
* `lbp_data` (output, **8b**): LBP result to be written.
* `finish` (output, 1b): assert high when the full frame is processed and all required writes have been performed; keep high until rst.

> **Interfaces:** `gray_mem` is read-only; `lbp_mem` is write-only. There is **no** `lbp_ready` input.

## 3. Image, Addressing & Mapping

* **Input image:** 128×128 pixels, each 8-bit unsigned (0…255), stored in `gray_mem`.
* **Output image:** 128×128 pixels, each 8-bit unsigned (0…255), stored in `lbp_mem`.
* **Linear address mapping (row-major):**
  `addr = y * 128 + x`, where `x,y ∈ [0,127]` and therefore `addr ∈ [0,16383]`.
* **1:1 address rule:** The LBP result derived from `gray_mem[k]` must be written to **`lbp_mem[k]`** (same `x,y` → same address).
* **Border rule:** The outermost ring (`x=0`, `x=127`, `y=0`, `y=127`) **must be 0** in `lbp_mem`. The host **pre-initializes** `lbp_mem` to 0. Your design may either:

  * Skip writing border addresses (preferred), or
  * Write explicit zeros to border addresses,
    but **must not** write any non-zero value at the border.

## 4. Read & Write Handshakes (with timing semantics)

**General:** Your RTL is rising-edge synchronous. The host side *acts* on the **negative edge** of the same clock.

### 4.1 Read (LBP → `gray_mem`)

* Issue a read by driving `gray_req=1` and a stable `gray_addr`.
* On the **next falling edge**, the host detects `gray_req=1` and places the byte at `gray_mem[gray_addr]` onto `gray_data`.
* Your RTL should **sample `gray_data`** on the **next rising edge** after that falling edge.
* **Burst reads**: keep `gray_req=1` and update `gray_addr` every cycle to stream one byte per cycle.
* **Pause**: deassert `gray_req`; host stops returning data from the next falling edge onward.
* **Constraint:** at most **one** read address may be issued per clock cycle. There is **no limit** on total requests over the whole run.

### 4.2 Write (LBP → `lbp_mem`)

* To write a result, drive `lbp_valid=1` with stable `lbp_addr` and `lbp_data` in the same cycle.
* On the **next falling edge**, the host performs the write to `lbp_mem[lbp_addr] = lbp_data`.
* **Burst writes**: hold `lbp_valid=1` and update `lbp_addr`/`lbp_data` each cycle to stream one byte per cycle.
* **Stop**: deassert `lbp_valid` to pause writes.

### 4.3 Start & Finish

* Do **not** issue reads until `gray_ready=1` has been observed after rst deassertion.
* After all required pixels are written to `lbp_mem` (respecting border rule and address mapping), assert `finish=1`.

## 5. LBP Algorithm (3×3, 8 neighbors)

Let `gc` be the center pixel; `gp` for neighbors `p=0..7`. Use the **row-major** 3×3 labeling below and weight each neighbor by `2^p`.

```
p=0  p=1  p=2        (-1,-1) (-1, 0) (-1,+1)
p=3  gc   p=4   ==   ( 0,-1) ( 0, 0) ( 0,+1)
p=5  p=6  p=7        (+1,-1) (+1, 0) (+1,+1)
```

**Definition**

```
bit_p = 1 if (gp - gc) >= 0 else 0
LBP(x,y) = sum_{p=0..7} bit_p << p
```

* Each pixel’s LBP is **independent** of others (suitable for internal parallelism).
* The LBP value naturally fits in 8 bits (0…255); no saturation or sign handling is required.

## 6. Iteration Domain & Control

* **Compute only for non-border pixels:** `x ∈ [1,126]`, `y ∈ [1,126]`.
* For each `(x,y)` in that range:

  1. Gather the 3×3 window around `(x,y)` using the address mapping.
  2. Compute `LBP(x,y)` per Section 5.
  3. Write the result to `lbp_mem[ y*128 + x ]`.
* **Order freedom:** You may process pixels in any order (scanline, tiled, micro-pipelined…), provided all protocol rules and mapping constraints are satisfied.

## 7. rst & Initialization Requirements

* Asserting `rst=1` must Synchronously clear internal state and outputs to safe defaults:

  * `gray_req=0`, `lbp_valid=0`, `finish=0`.
  * Optional: clear internal FIFOs/buffers.
* After deasserting `rst`, wait for `gray_ready=1` before starting reads.

## 8. Legal/Illegal Behaviors (Protocol Safety)

**Legal**

* Issue at most one read request per cycle; stream reads/writes by holding enable high.
* Pause/resume cleanly by dropping `gray_req`/`lbp_valid`.
* Skip border writes (since host pre-zeros the frame).

**Illegal**

* Issuing read requests while `gray_ready=0`.
* Writing any **non-zero** to border addresses.
* Writing a result to an address different from the source pixel’s address (`1:1` rule).

## 9. Reference Pseudocode (behavioral, cycle-agnostic)

```c
// Assume gray(y,x) reads gray_mem[y*128 + x]
// and lbp(y,x) writes lbp_mem[y*128 + x].

for (int y = 1; y <= 126; ++y) {
  for (int x = 1; x <= 126; ++x) {
    uint8_t gc = gray(y, x);
    uint8_t g[8] = {
      gray(y-1,x-1), gray(y-1,x),   gray(y-1,x+1),
      gray(y,  x-1),                 gray(y,  x+1),
      gray(y+1,x-1), gray(y+1,x),   gray(y+1,x+1)
    };
    uint8_t v = 0;
    for (int p=0; p<8; ++p) v |= ((g[p] >= gc) ? 1 : 0) << p;
    lbp(y, x) = v;
  }
}
// border rows/cols remain 0 in lbp_mem.
```

## 10. Implementation Notes (non-normative)

* A sliding 3×3 window with **two line buffers** (for previous rows) is typical; still, external protocol limits you to **one** read address per cycle.
* You may pipeline comparison and bit-packing; write as soon as the byte is ready.
* Any internal parallelism is allowed if external protocol, mapping, and outputs are preserved.

---
