
# Human Version — Distance Transform (DT): Complete Design Specification

## 1) Problem Description

Design a hardware **Distance Transform (DT)** engine that reads a **binary 128×128 image** from a host **input ROM (`sti_ROM`)**, computes an **8-distance (chessboard) transform**, and writes the resulting **8-bit grayscale 128×128 image** to a host **output RAM (`res_RAM`)**. When the full frame is written, assert `done=1`. The object pixels are denoted by **1**, background by **0**; test data guarantee the object region does **not** touch the outermost border ring.&#x20;

---

## 2) Top-Level Module & I/O

**Top module name:** `DT`  (Verilog: `module DT (...);`)

**Clocking & reset**

* `clk`: rising-edge synchronous.
* `reset`: **active-low, asynchronous**. While `reset=0`, clear state and do not produce valid writes/`done`. The testbench holds `reset=0` for \~2 cycles then deasserts to `1`.&#x20;

**Ports (fixed names, widths, semantics)**

| Signal                                           | Dir | Width | Meaning                                                                                                                                      |
| ------------------------------------------------ | --: | ----: | -------------------------------------------------------------------------------------------------------------------------------------------- |
| `clk`                                            |   I |     1 | System clock (posedge).                                                                                                                      |
| `reset`                                          |   I |     1 | **Active-low async reset**. Low→reset; High→run.                                                                                             |
| `sti_rd`                                         |   O |     1 | `sti_ROM` **read enable**; when High at **negedge**, data appears immediately on `sti_di`.                                                   |
| `sti_addr`                                       |   O |    10 | `sti_ROM` **address** (0..1023). **At most one** address read per cycle. Keep stable across the servicing **negedge**.                       |
| `sti_di`                                         |   I |    16 | `sti_ROM` **read data**: 16 packed binary pixels.                                                                                            |
| `res_wr`                                         |   O |     1 | `res_RAM` **write enable**; when High at **posedge**, write `res_do` to `res_addr`.                                                          |
| `res_rd`                                         |   O |     1 | `res_RAM` **read enable**; when High at **negedge**, data appears immediately on `res_di`.                                                   |
| `res_addr`                                       |   O |    14 | `res_RAM` address (0..16383). **At most one** read and **at most one** write address serviced per cycle (read at negedge, write at posedge). |
| `res_do`                                         |   O |     8 | `res_RAM` **write data** (grayscale).                                                                                                        |
| `res_di`                                         |   I |     8 | `res_RAM` **read data**.                                                                                                                     |
| `done`                                           |   O |     1 | Assert High **after** all result pixels are written; 1 indicates completion; host then checks results and ends simulation.                   |
| (Ports and timing semantics per problem brief.)  |     |       |                                                                                                                                              |

---

## 3) External Memories: Mapping & Timing

### 3.1 Input binary image ROM — `sti_ROM` (read-only)

* **Image size:** 128×128 = 16,384 pixels, **1 bit per pixel**.
* **ROM geometry:** width **16 bits**, depth **1024** addresses.
* **Address-to-pixel mapping (row-major):** address `a` holds **pixels \[16a .. 16a+15]** corresponding to a **left-to-right** run in the raster order, then top-to-bottom across rows. Treat the 16-bit word as a 16-pixel pack. (The testbench uses this contiguous, row-major packing.)
* **Timing:** On **each negative clock edge**, if `sti_rd=1`, `sti_di` **immediately** drives the data of the address on `sti_addr` (no additional latency). If `sti_rd=0`, no action. **Issue at most one ROM address per cycle**; keep `sti_addr` stable through the servicing **negedge**.&#x20;

### 3.2 Output grayscale image RAM — `res_RAM` (read/write)

* **Result size:** 128×128 = 16,384 pixels, **8 bits per pixel**.
* **Addressing (row-major):** write pixels **left-to-right, top-to-bottom** to addresses **0..16383**. You may also re-use `res_RAM` as scratch during computation.
* **Timing:**

  * **READ:** If `res_rd=1` on a **negedge**, `res_di` **immediately** reflects `res_addr` (no extra latency).
  * **WRITE:** If `res_wr=1` on a **posedge**, `res_do` is written to `res_addr`.
  * In a given cycle you may perform **one read (at negedge)** and **one write (at posedge)**.&#x20;

---

## 4) Algorithm — 8-Distance (Chessboard) Transform

We compute, for each **object pixel** (input bit = 1), the **minimum chessboard distance** to any **background pixel** (input bit = 0), using a **forward pass** then a **backward pass** over the raster. Background pixels remain 0. (The object region never touches the outermost image border.)&#x20;

**Coordinate & neighborhood notation**
At location `(x,y)`, define neighbors:

* **Forward window:** `NW, N, NE, W`
* **Backward window:** `E, SE, S, SW`
  (These are the four preceding neighbors in the forward scan and the four succeeding neighbors in the backward scan, respectively.)&#x20;

**Initialization**
Set each pixel to **1** if object, **0** if background (i.e., use the binary input as initial scalar field).&#x20;

**Forward pass (scan left→right, top→bottom)**
For every **object** pixel `p(x,y)` (the red “center” in the figure), compute
`x = min( NW, N, NE, W )`, then **update** `p(x,y) ← x + 1`.
(Background pixels keep value 0.)&#x20;

**Backward pass (scan right→left, bottom→top)**
For every **object** pixel `p(x,y)`, compute
`z = min( E, SE, S, SW )`, then `y = min( p(x,y), z + 1 )`, and **update** `p(x,y) ← y`.
After this pass, `p` holds the chessboard distance to the nearest background pixel.&#x20;

---

## 5) System-Level Operation Sequence & Control

1. **Reset** (`reset=0` for \~2 cycles): clear all internal state; no reads/writes; `done=0`.
2. **ROM read / compute:** after `reset` deasserts (`reset=1`), drive `sti_rd/sti_addr` to fetch binary data packs from `sti_ROM` and perform the DT algorithm. You **may** use `res_RAM` as temporary storage via `res_rd/res_wr` during forward/backward passes.
3. **Write-out:** write the **final 8-bit result image** to `res_RAM` **row-major** via `res_wr/res_addr/res_do` (write on posedges).
4. **Finish:** after all 16,384 result pixels are written, **assert `done=1`**; the host immediately starts result checking and ends the simulation on completion.&#x20;

---

## 6) Constraints & Notes

* **Do not** modify testbench or memory modules; observe the **exact** port names, widths, and edge-sensitive protocols above.
* **Throughput/latency** are not constrained by the spec beyond the memory protocols; any correct micro-architecture is acceptable (single/dual pass buffering, streaming or tiled, etc.).
* **Boundary safety**: the input guarantees the object region does **not** touch the outermost border, simplifying neighborhood access during forward/backward scans.&#x20;

---
