# Job Assignment Machine (JAM) Accelerator — Design Specification

## 1. Overview

The Job Assignment Machine assigns 8 workers to 8 jobs, one worker per job and one job per worker, so that the total cost is minimized. Each worker has a different cost for each job, given by an 8×8 cost table. The module must, by brute force over all 8! = 40320 possible assignments, find the **minimum total cost** and **how many distinct assignments achieve that minimum**, then report both and raise a done flag.

The module reads the cost table from an external asynchronous ROM in the testbench by driving a worker index and a job index and reading back the cost combinationally. The top module is named **`TOP`**.

---

## 2. What the module must do (functional description)

### The assignment problem

You have 8 workers (0–7) and 8 jobs (0–7). Assigning worker *w* to job *j* costs `cost[w][j]`. A valid assignment is a one-to-one matching: every worker gets exactly one job and every job is taken by exactly one worker. Such an assignment is exactly a **permutation** of the job indices: if you list, for worker 0, worker 1, …, worker 7, which job each is given, you get a permutation of `[0,1,2,3,4,5,6,7]`. The total cost of an assignment is the sum of the eight `cost[w][job_of_w]` values.

The task: over all 8! permutations, compute the smallest total cost (`MinCost`) and the number of permutations whose total cost equals that smallest value (`MatchCount`).

### Worked cost example

Using the 5×5 illustration from the source (rows = workers, columns = jobs):

```
        J0   J1   J2   J3   J4
 W0     12   22   34   54   12
 W1     45   21   97   98   34
 W2     54   88   21   22   34
 W3     12   43   57   21   33
 W4     35   98   32    1   13
```

For the permutation `[3, 2, 4, 0, 1]` (worker 0→job 3, worker 1→job 2, worker 2→job 4, worker 3→job 0, worker 4→job 1), the total cost is

```
cost[0][3] + cost[1][2] + cost[2][4] + cost[3][0] + cost[4][1]
   = 54   +   97       +   34       +   12       +   98   = 295
```

The real problem is the 8×8 version (n = 8); the 5×5 grid above is only to show how a permutation maps to a summed cost.

### Enumerating all permutations (lexicographic "next permutation")

The source teaches one way to generate every permutation: start from the sorted sequence and repeatedly compute the *next* permutation in lexicographic order until none remains. The reader is free to use any method that visits all permutations; this one is just the reference.

The "next permutation" of a sequence is found in three steps. Worked on the source's example with n = 7, sequence `[3, 0, 4, 6, 5, 2, 1]`:

1. **Find the pivot.** Scanning adjacent pairs from the right, find the first position where the left element is smaller than the element to its right. `[2,1]` no; `[5,2]` no; `[6,5]` no; `[4,6]` yes — so the value **4** (at index 2) is the pivot.
   ```
   [3, 0, 4, 6, 5, 2, 1]
          ^ pivot = 4
   ```
2. **Swap with the next-larger.** Among the elements to the right of the pivot (`[6,5,2,1]`), find the smallest value still larger than the pivot 4 — that is **5**. Swap 4 and 5:
   ```
   [3, 0, 5, 6, 4, 2, 1]
   ```
3. **Reverse the tail.** Reverse the elements after the pivot position (`[6,4,2,1]` → `[1,2,4,6]`):
   ```
   [3, 0, 5, 1, 2, 4, 6]
   ```
   This is the next permutation after `[3, 0, 4, 6, 5, 2, 1]`.

Repeating this from `[0,1,…,7]` until the sequence can no longer advance enumerates all 8! permutations exactly once.

### What to output

While enumerating, accumulate each permutation's total cost. Track the running minimum (`MinCost`) and count how many permutations tie that minimum (`MatchCount`). When enumeration is complete, present `MinCost` and `MatchCount` on the output ports and raise `Valid` High. The testbench compares both values and ends the simulation on the cycle after `Valid`.

(`MinCost` is an unsigned integer; the testbench guarantees the minimum total cost will not exceed 1024. `MatchCount` is the number of tying assignments.)

---

## 3. Interface

Port names, widths, and reset polarity below follow the authoritative harness (`test.sv` / `initial.sv`). The top module is **`TOP`**. Note the harness uses lowercase `clk` and `rst`, whereas the PDF's signal table writes `CLK` and `RST`; the environment names are authoritative.

| Signal | Dir | Width | Meaning |
|--------|-----|-------|---------|
| `clk`        | I | 1  | Clock. Positive-edge triggered. |
| `rst`        | I | 1  | Reset, **active high**. The testbench holds it High for 2 cycles, then drops it Low. (PDF writes this as `RST`.) |
| `W`          | O | 3  | Worker-select index to the cost ROM, 0–7. |
| `J`          | O | 3  | Job-select index to the cost ROM, 0–7. |
| `Cost`       | I | 7  | Cost value: the cost of worker `W` doing job `J`. Unsigned, 0–100. Responds combinationally to `W`/`J` (see timing — the testbench registers the lookup, adding one cycle of latency). |
| `MatchCount` | O | 4  | Number of distinct assignments achieving the minimum cost. |
| `MinCost`    | O | 10 | The minimum total assignment cost (unsigned; ≤ 1024 by guarantee). |
| `Valid`      | O | 1  | When High, `MinCost` and `MatchCount` are valid; the testbench ends the simulation on the following cycle. |

### How the signals interact

After reset, the design drives `W` and `J` to address the cost ROM and reads the corresponding cost on `Cost`. The ROM is asynchronous from the PDF's point of view — the cost responds directly to the address — but the harness inserts a one-cycle register on the lookup (see §4), so a value requested by driving `W`/`J` in one cycle is observed on `Cost` in the next. The design may re-read any ROM entry as many times as needed; there is no read-count limit.

The design walks through permutations, summing the eight per-worker costs for each, maintaining the running minimum and tie count. When every permutation has been evaluated, it drives the final `MinCost`/`MatchCount` and asserts `Valid`. There is no input-side handshake (no ready/req); `W`/`J`/`Cost` form a simple addressed-read interface, and `Valid` is the only completion signal.

---

## 4. Timing / protocol

The clock period in the harness is 10 ns, toggling every half period; all design logic is on the **rising edge** of `clk`. Reset is asynchronous active-high in the reference design (the reset branch sits in `always @(posedge clk or posedge rst)`).

### Reset

The testbench raises `rst` shortly after a rising edge, holds it High for two cycles, then drops it Low after a rising edge. While `rst` is High the design initializes; once `rst` is Low it begins enumerating.

### Cost-read handshake (figure 3 as prose)

To read a cost, the design places a worker index on `W` and a job index on `J`. Conceptually the ROM responds immediately with `cost[W][J]` on `Cost`, independent of the clock. **However, the harness samples `W`/`J` into registers on the rising edge (with a small `#1` delay) and drives `Cost` from those registered indices**:

```
Cost = costrom[8*W_s + J_s],  where W_s, J_s are W, J registered one cycle earlier
```

So in practice there is a **one-cycle read latency**: the cost for the indices presented in cycle *t* appears on `Cost` in cycle *t+1*. A correct design must pipeline its accumulation to account for this delay (the reference begins summing on the second beat of its input phase — it discards the first, latency-filling read; see §6).

### Result / completion (figure 4 as prose)

When enumeration finishes, the design drives the final `MinCost` and `MatchCount` and raises `Valid` High in the same cycle. The testbench, on detecting `Valid` High at a rising edge, prints and compares the received `MinCost`/`MatchCount` against the golden values, and immediately finishes the simulation. There is a global timeout: if `Valid` is never asserted within the cycle budget, the testbench reports failure and stops. (The design must therefore complete well within the budget.)

---

## 5. Cost ROM layout

The cost table is an 8×8 array of unsigned 7-bit values (each 0–100). It is addressed by the pair `(W, J)`: `W` selects the worker (row), `J` selects the job (column). In the harness the ROM is stored flattened, row-major:

```
costrom[8*W + J] = cost of worker W on job J
```

So worker 0's eight job costs occupy indices 0–7, worker 1's occupy 8–15, and so on through worker 7 at indices 56–63. The cost data is loaded from an external pattern file (`cost_rom`), and the harness selects one of three patterns at compile time. The minimum total cost is guaranteed not to exceed 1024.

### Reference golden results (for regression)

The source lists the expected answers for the three provided patterns. These are gold for checking a design end-to-end:

| Pattern | MinCost | MatchCount |
|---------|---------|------------|
| 1 | 119 | 3 |
| 2 | 250 | 6 |
| 3 | 485 | 9 |

For pattern 1, the three minimum-cost assignments (job index per worker, W0→W7) are `1 7 5 0 4 3 6 2`, `6 7 5 0 4 3 1 2`, and `6 7 5 0 4 3 2 1`. For pattern 2 there are six tying assignments; for pattern 3, nine. (The full per-pattern cost matrices and tie lists are in the source's pattern appendix; only the final `MinCost`/`MatchCount` are checked by the testbench.)

Note: designs must not special-case the known patterns (e.g. detect a specific table and hard-code the answer); the grader uses additional patterns.

---

## 6. Reference implementation

`initial.sv` contains a **working reference** implementation of `TOP`. Description follows.

### Algorithm level

The design enumerates all permutations of `[0..7]` using the lexicographic next-permutation method, summing each permutation's eight costs read from the ROM, and tracking the running minimum and a count of ties. It uses a 4-state FSM that, for each permutation, streams the eight `(W=job[cnt], J=cnt)` lookups, accumulates the costs, compares the total against the current minimum, then computes the next permutation in place. When no next permutation exists (the sequence is fully descending), it asserts `Valid`.

### Micro-architecture

- **FSM:** four states `IDLE → INPUT → OUTPUT → SORT0 → INPUT …`. From `IDLE` it goes to `INPUT`; `INPUT` iterates a counter `cnt` from 0 to 8 issuing the eight cost reads; at `cnt==8` it moves to `OUTPUT`; `OUTPUT` updates the min/count and decides whether another permutation exists (`match==0` → done, go `IDLE`; else go `SORT0` to perform the swap/reversal); `SORT0` returns to `INPUT` for the next permutation.
- **Permutation state:** `job[0..7]` holds the current permutation, reset to the identity `[0,1,…,7]`. The next-permutation logic is split across the `match` array (records, for each adjacent pair, whether it is ascending — used to find the pivot), `index` (the pivot position, chosen as the highest ascending-pair index), `index2[]` (inverse-position map used to find the swap partner), and the `flag[]` generate block (selects which element right of the pivot is the smallest value still larger than the pivot). `SORT0` performs the tail reversal via the per-`index` case statement; `OUTPUT` performs the pivot/partner swap.
- **Address generation:** `W = job[cnt]`, `J = cnt`. So during `INPUT`, on beat `cnt` the design asks for the cost of the worker assigned to job `cnt` — walking the permutation.
- **Cost accumulation:** `costTemp` accumulates `Cost`. Because of the one-cycle ROM read latency, the reference starts accumulating at `cnt==1` (`costTemp <= Cost`) and adds subsequent reads (`costTemp <= costTemp + Cost`), so the eight summed values correspond to the eight workers with the pipeline delay absorbed.
- **Min / count:** in `OUTPUT`, if `MinCost` is still 0 (first permutation) or `costTemp < MinCost`, it sets `MinCost <= costTemp` and resets `MatchCount <= 1`; if `costTemp == MinCost`, it increments `MatchCount`.
- **Done detection:** `match` becomes all-zero exactly when the current permutation is the last (fully descending) one; `Valid` is asserted combinationally as `state_r == IDLE && match == 0`.
- **Clock/reset:** all sequential logic is `posedge clk` with asynchronous `posedge rst`; reset initializes `job` to identity, `match` to all-ones, `index2` to identity, `cnt`/`costTemp`/`MinCost` to 0, `MatchCount` to 1, and the FSM to `IDLE`.

This is one valid (cycle-by-cycle, ~one-permutation-per-several-cycles) solution; the problem does not require this particular structure.

---

## 7. Differences from the original problem

- **Top module is `TOP`.** The harness instantiates `module TOP`; the PDF's deliverable was named `JAM` (`JAM.v`). The environment wins.
- **Design entry point is `initial.sv`**, which defines `module TOP` and contains a working reference implementation (described in §6).
- **Lowercase `clk` / `rst`.** The PDF's signal table writes `CLK` and `RST`; the harness ports are `clk` and `rst`. Polarity (active-high reset, positive-edge clock) is unchanged.
- **Cost read has one cycle of latency.** The PDF describes the cost ROM as asynchronous (cost responds directly to `W`/`J`). The harness registers `W`/`J` (`W_s`/`J_s`) before indexing the ROM, so `Cost` is effectively one cycle behind the requested address; the design must pipeline accordingly.
- **Testbench file is `test.sv`** (PDF appendix refers to `tb.sv` / `tb.v`), and the cost data comes from a `cost_rom` pattern file selected by `+define+P1/P2/P3`.
- **Omitted:** the grading scheme (A/B/C/D levels, cycle/area targets), submission/FTP procedure, EDA tool-version lists, and SDF-annotation contest mechanics from the PDF are intentionally excluded as irrelevant to solving and verifying the RTL.