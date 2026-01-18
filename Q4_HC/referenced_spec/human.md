
---

# Human Version — Huffman Coding Hardware: Complete Design Specification

## 1) Problem Description

Design and implement a hardware **Huffman Coding generator** (`huffman` core) for lossless compression. The input is a stream of grayscale pixels. For this contest, pixels are restricted to **six symbols** A1..A6 with fixed values:

* A1 = 0x01, A2 = 0x02, A3 = 0x03, A4 = 0x04, A5 = 0x05, A6 = 0x06.
* Exactly **100 pixels** are provided per run.

Your circuit must:

1. **Count** occurrences of each symbol across the 100-pixel input (statistics phase).
2. **Build Huffman codes** from those statistics using the specified ordering and tie-breaking rules (see §4).
3. **Output** the counts and the per-symbol Huffman codes in a fixed-width format (8-bit code field + 8-bit mask), with single-cycle valid strobes for each output phase (see §5 Timing).

> Restrictions: You must **compute** Huffman codes from the input statistics as specified. **Exhaustive lookup / precomputed table solutions are forbidden.**

---

## 2) Top-Level Rules & Naming

* **Top module name**: `TOP`.
* **Do not modify** the provided testbench (assumed). Your design must conform strictly to the interface below.
* Synchronous design on **posedge `clk`**. rst is **synchronous active-high**.

---

## 3) Interface (Ports and Semantics)

### 3.1 Signals

| Signal       | Dir |  Width | Description                                                                                                     |
| ------------ | --: | -----: | --------------------------------------------------------------------------------------------------------------- |
| `clk`        |   I |      1 | System clock; all design logic is posedge-triggered.                                                            |
| `rst`        |   I |      1 | **Synchronous, active-high** system rst. While `rst=1`: internal state cleared; no valid outputs asserted. |
| `gray_valid` |   I |      1 | When High, **one pixel per cycle** is present on `gray_data`.                                                   |
| `gray_data`  |   I |      8 | Grayscale pixel value. For this problem, values are in {0x01..0x06} corresponding to A1..A6.                    |
| `CNT_valid`  |   O |      1 | Single-cycle pulse indicating that symbol **counts** are valid on `CNT1..CNT6`.                                 |
| `CNT1..CNT6` |   O | 8 each | 8-bit **counts** of A1..A6, respectively, captured when `CNT_valid=1`.                                          |
| `code_valid` |   O |      1 | Single-cycle pulse indicating that **codes/masks** are valid on `HC1..HC6` and `M1..M6`.                        |
| `HC1..HC6`   |   O | 8 each | 8-bit **Huffman code fields** for A1..A6 (variable-length codes packed into 8 bits; see §4.4).                  |
| `M1..M6`     |   O | 8 each | 8-bit **mask fields** for A1..A6 (which bits of HC are valid; see §4.4).                                        |

### 3.2 Input assumptions

* Exactly **100 pixels** are streamed **contiguously** while `gray_valid=1`.
* The testbench **presents pixels once per cycle** during the input phase; your design samples on the **posedge** (you need not track the bench’s negedge driving—just meet the posedge sampling requirement with `gray_valid`).
* After the 100th pixel, `gray_valid` is deasserted (low).

---

## 4) Functional Requirements

### 4.1 Symbols and indices

* Symbols are labeled A1..A6 with **indices 1..6**, respectively. Use these indices whenever a tie-break requires “smaller index” first.

### 4.2 Overview of the 3 stages

1. **Initialization (sort)**: Sort the six symbols in **descending** order of occurrence probability (i.e., by their counts). If probabilities are equal, the symbol with **smaller index** appears **higher** in the list.
2. **Combination (C1, C2, …)**: Repeatedly **merge the two bottom items** (the current **lowest** probabilities) to form one group whose probability is the **sum** of its members. Re-insert the merged group and **resort** in descending probability. **Tie rule in combination**: if the merged group’s probability ties other entries, the **merged group is placed last within that tie group** (i.e., at the lowest position among equal probabilities). Continue until only **two items** remain.
3. **Split (code assignment)**: Starting from the final 2-item list, assign codes and **propagate upward** (reverse of combination): for each split step, the **upper** item gets bit **‘0’**, the **lower** item gets bit **‘1’**. Codes are built by **inheriting parent bits and appending** the split bit at each step until reaching individual symbols.

> Tree view conventions (if you draw a tree internally): for any 2-child node, place the **smaller probability on the left** and the **larger on the right**; during the split/code assignment that corresponds to the described **upper=‘0’ / lower=‘1’** rule when using the table-style lists.

### 4.3 Counting and probability

* With 100 pixels, each symbol’s probability is `count/100`. You may work directly with **counts** (no need to normalize), since ordering by counts is equivalent to ordering by probabilities.

### 4.4 Code representation on outputs (HC/M)

Because Huffman codes are **variable-length**, each symbol’s code is conveyed as:

* `HCx` (8 bits): the **code bits packed into the 8 LSBs**, and
* `Mx` (8 bits): a **bitmask** marking which bits of `HCx` are valid.

**Rules:**

* If a symbol’s code length is `L` (1 ≤ L ≤ 8):

  * Set `Mx[L-1:0] = 1` and `Mx[7:L] = 0`.
  * Put the code’s bit string into `HCx[L-1:0]` **in the same left-to-right order that you write the code**. (Example below.)
  * Force `HCx[7:L] = 0`.
* **Examples**:

  * If A6’s code is `00` (length 2): `M6 = 0000_0011 (0x03)`, `HC6 = 0000_0000 (0x00)`.
  * If A3’s code is `01010` (length 5): `M3 = 0001_1111 (0x1F)`, `HC3 = 0000_1010 (0x0A)`.

> Note: The code strings shown in figures (e.g., `00`, `011`, `01010`) are the **exact bit patterns** to place into `HCx[L-1:0]` (so the numeric value of `HCx[L-1:0]` equals the binary code read left-to-right).

### 4.5 Prohibited approach

* It is **not allowed** to solve by **exhaustive enumeration** / prebuilt mapping. The Huffman construction must follow the specified **initialize → combination (with tie rules) → split** process on the **actual input counts**.

---

## 5) Timing and Phases

### 5.1 rst and input (T1, T2, T3)

* **T1**: `rst=1` is asserted for at least two cycles. During `rst=1`, clear all internal state and do **not** assert `CNT_valid` or `code_valid`. After `rst` deasserts (1→0), the core is ready.
* **T2**: **Input phase** — the testbench sets `gray_valid=1` and streams **100 pixels**, one per cycle, on `gray_data`. Your design samples at the **posedge** while `gray_valid=1`.
* **T3**: End of input — the testbench deasserts `gray_valid` to 0. The design must then proceed to compute counts (if not already complete) and the Huffman codes.

### 5.2 Outputs (T4, T5)

* **T4 (Counts available)**: When the six symbol counts are ready, assert `CNT_valid=1` for **one clock cycle** and **simultaneously** drive:

  * `CNT1..CNT6` with the counts of A1..A6 (8-bit each).
* **T5 (Codes available)**: When all Huffman codes are ready, assert `code_valid=1` for **one clock cycle** and **simultaneously** drive:

  * `HC1..HC6` (8-bit each) with the packed codes per §4.4, and
  * `M1..M6` (8-bit each) with the masks per §4.4.
    After `code_valid` returns Low, verification may complete; no further outputs are required in that run.

> All outputs are synchronous to `clk`. Valid strobes (`CNT_valid`, `code_valid`) are **one-cycle pulses**.

---

## 6) Determinism & Tie-Breaking (must-follow)

To ensure every implementation produces the **same codes** for a given input:

1. **Initialization**: Sort symbols by **descending** probability (count). **If equal**, the **smaller index** (A1 < A2 < … < A6) is **higher** (earlier) in the list.
2. **Combination**: At each combination round, always **merge the bottom two** entries (the two with **lowest** probabilities in the current sorted list). The merged group’s probability is the **sum** of its members. After merging, **resort**; **if the merged group ties** with others, place the merged group **last** within that tie group.
3. **Split / Code assignment**: Starting from the final 2-item list, at each split step:

   * The **upper** item gets bit **‘0’**,
   * The **lower** item gets bit **‘1’**,
     and codes are formed by **appending** these bits while moving from the final list back to the individual symbols.
4. **Output packing**: Place the resulting bit strings into `HCx`/`Mx` exactly as in §4.4.

---

## 7) Verification Expectations (what the bench assumes)

* Input values are limited to {0x01..0x06}.
* Exactly 100 samples per run.
* The checker latches counts on `CNT_valid=1` and codes/masks on `code_valid=1`.
* Code equivalence is judged using the **deterministic procedure** above (including tie-break rules).

---

## 8) Examples (mirroring the brief)

* If counts yield codes like:
  A2:`1`, A6:`00`, A1:`011`, A4:`0100`, A3:`01010`, A5:`01011`,
  then (lengths in brackets):

  * `HC2=0000_0001`, `M2=0000_0001` (L=1)
  * `HC6=0000_0000`, `M6=0000_0011` (L=2)
  * `HC1=0000_0111`, `M1=0000_0111` (L=3)
  * `HC4=0000_0100`, `M4=0000_1111` (L=4)
  * `HC3=0000_1010`, `M3=0001_1111` (L=5)
  * `HC5=0000_1011`, `M5=0001_1111` (L=5)

(Exact codes depend on the measured counts; use the specified rules so your results match the reference for any pattern.)

---
