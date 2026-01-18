
---

# Human Version — Job Assignment Machine (JAM): Complete Design Specification

## 1) Problem Overview

Implement a hardware **Job Assignment Machine (JAM)** that, for **n = 8** workers and **8** jobs, **exhaustively enumerates all assignments** (permutations) to:

1. find the **minimum total cost**, and
2. report the **number of assignments** that achieve that minimum.

The per-worker per-job **costs are stored in a synchronous 8×8 cost ROM** accessed via index signals. JAM repeatedly queries this ROM while iterating through all permutations. When done, it outputs `MinCost`, `MatchCount`, and asserts `Valid` for one clock to indicate results are ready (the testbench ends on the next cycle).&#x20;

---

## 2) Top-Level Module & I/O

**Module name:** `TOP`

**Clocking & reset:**

* `CLK`: rising-edge synchronous.
* `RST`: **active-high, Synchronous** reset; testbench holds high for \~2 cycles then deasserts. While `RST=1`, internal state is cleared and no valid result is presented.&#x20;

**Ports (widths & meaning):**

* `input  CLK` (1): system clock, posedge trigger.
* `input  RST` (1): Synchronous active-high reset.
* `output reg [2:0] W` (3): worker index selector (**0..7**) into cost ROM row.
* `output reg [2:0] J` (3): job index selector (**0..7**) into cost ROM column.
* `input  [6:0] Cost` (7): **unsigned** cost returned by the ROM (range **0..100**).
* `output reg [3:0] MatchCount` (4): number of assignments achieving the minimum (0..15; guaranteed to fit).
* `output reg [9:0] MinCost` (10): **unsigned** minimum total cost; testbench guarantees the true minimum ≤ **1024**.
* `output reg Valid` (1): **1-cycle pulse** indicating `MinCost` and `MatchCount` are final and valid.&#x20;

---

## 3) External Cost ROM Interface & Timing

* The 8×8 cost table is provided as a synchronous read memory (“`cost_rom`”).
* **Addressing:** Drive `(W,J)` with values in **0..7**.
* **Read latency:** The **Cost** value reflects the **(W,J)** that were presented **in the preceding cycle**; i.e., apply `W`/`J` during cycle **t**, sample the corresponding `Cost` at the **rising edge of cycle t+1** (typical synchronous read). Keep `W`/`J` stable through the driving cycle to meet setup/hold.
* **Reuse:** The same ROM entries may be read any number of times; there is no side effect.
* **Waveforms:** Input (W,J→Cost) and output (`MinCost/MatchCount` with `Valid`) timing follow the figures in the brief; here we formalize: `Valid` is asserted for **exactly one** clock when the final numbers are present; the testbench terminates on the following cycle.&#x20;

---

## 4) Required Functionality

### 4.1 Exhaustive Enumeration

* Consider the set of job indices **\[0..7]**.
* An **assignment** is a **permutation P** of \[0..7] where worker **W=k** is assigned job **J=P\[k]**.
* There are **8!** assignments; JAM must **evaluate every one** (no pruning).&#x20;

### 4.2 Total Cost of an Assignment

For a given permutation **P**, compute:

$$
\text{TotalCost}(P) = \sum_{k=0}^{7} \text{Cost}(W=k,\;J=P[k]).
$$

Each term is obtained by a ROM read at address `(W=k, J=P[k])`. Accumulate the 8 terms to get the assignment’s total.&#x20;

### 4.3 Global Results

* **MinCost:** the minimum of `TotalCost(P)` over all permutations.
* **MatchCount:** how many distinct permutations achieve that **MinCost**.
* When the search completes, drive `MinCost`, `MatchCount`, and assert `Valid=1` for **one** clock.&#x20;

---

## 5) Permutation Generation (Lexicographic “next-permutation”)

You may generate all permutations by any correct method. For determinism and simplicity, the brief describes the **lexicographic next-permutation** routine (not the only allowable method). One standard formulation:

1. **Find pivot:** Scan from the right to find the **first i** with `a[i] < a[i+1]`. If none, the current sequence is the last permutation.
2. **Find successor:** In the suffix `a[i+1..end]`, find the **smallest element > a\[i]**; call its position `j`.
3. **Swap & reverse:** Swap `a[i]` and `a[j]`, then **reverse** the suffix `a[i+1..end]`. The result is the **next** permutation in lexicographic order.

Start from the sorted sequence `[0,1,2,3,4,5,6,7]` and iterate until all permutations are covered. (Example reasoning and a 7-element demonstration are provided in the brief; the above steps capture the required behavior.)&#x20;

---

## 6) Control & Output Protocol

1. **Reset phase:** With `RST=1`, clear internal state (counters, trackers, permutation registers, pipelines). No `Valid` pulse.
2. **Run phase:** After `RST` deasserts, begin exhaustive enumeration and ROM queries; accumulate and track the minimum and its multiplicity.
3. **Finalize:** Once all permutations are evaluated, present `MinCost`/`MatchCount` and assert `Valid=1` for a **single** clock. The testbench stops in the **next** cycle.&#x20;

---

## 7) Data Ranges & Types

* **Cost:** `0..100` (unsigned 7-bit), provided by the ROM.
* **MinCost:** unsigned 10-bit; true minimum is guaranteed ≤ **1024**.
* **MatchCount:** unsigned 4-bit (0..15); wide enough for all supplied patterns.
* **Indices:** `W`, `J` are 3-bit unsigned (`0..7`).&#x20;

---

## 8) Design Constraints & Notes

* **Must not** hard-code or special-case any known test patterns; solutions that detect pattern IDs or embed precomputed answers are disallowed.
* The lexicographic algorithm is **suggested** but **not mandatory**—any correct exhaustive enumeration is acceptable.
* The port names and widths are **fixed** as specified; do not change them.
* Synthesis, SDF, and tool command details belong to appendices and are **out of scope** here.&#x20;

---
