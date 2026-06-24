# Huffman Coding Encoder — Design Specification

## 1. Overview

This module is a hardware **Huffman code generator**. It receives a stream of 100 grayscale pixels (one byte per pixel), counts how many times each of six possible symbols appears, then runs the classic Huffman construction algorithm (combine the two lowest-probability groups repeatedly, then split back down assigning bits) to produce a variable-length prefix-free code for each of the six symbols. Because the algorithm must genuinely be *computed*, a brute-force lookup table from input pattern to answer is forbidden.

The module reports two things in sequence: first the six symbol counts, then the six Huffman codewords plus a mask for each that says how many of the codeword's bits are valid.

---

## 2. What the module must do (functional description)

### 2.1 The six symbols

The image is a 100-pixel grayscale picture. Each pixel is one of six possible values. The symbols and their byte values are:

| Symbol | A1 | A2 | A3 | A4 | A5 | A6 |
|--------|----|----|----|----|----|----|
| Value  | 0x01 | 0x02 | 0x03 | 0x04 | 0x05 | 0x06 |

Each symbol has a fixed **index**: A1→1, A2→2, A3→3, A4→4, A5→5, A6→6. The index is used as a tie-breaker (see below), so it matters.

### 2.2 Stage 1 — counting

While the input is streaming, count occurrences of each symbol. After all 100 pixels arrive, you have six counts that sum to 100 (e.g. CNT1=count of A1, …, CNT6=count of A6). The probability of a symbol is just its count / 100, but **you can work entirely with raw counts** — every comparison the algorithm needs ("which is smaller") gives the same answer with counts as with probabilities, and avoids fractions.

### 2.3 Stage 2 — building the Huffman code

The construction has three conceptual phases: *initialization*, *combination*, and *split*.

**Initialization.** Sort the six symbols by probability, largest at the top, smallest at the bottom. **Tie-break rule for initialization:** if two symbols have equal probability, the one with the *smaller index* goes higher. (Example: if A1 and A4 both have probability 0.1, A1 — index 1 — sits above A4.)

**Combination.** Repeatedly take the two lowest groups (the bottom two in the current ordering), merge them into one combined group whose probability is the sum of the two, and re-insert (re-order) that combined group into the list by probability. Repeat until only two groups remain. **Tie-break rule for combination:** when a newly merged group ties in probability with existing groups, the merged group is placed *last* (lowest) among that equal-probability cluster.

**Split (assign codes).** Walk the combination history backwards. At the final two-group state, the **upper** group is assigned code bit `0` and the **lower** group is assigned code bit `1`. Then, undoing each merge in reverse, every time a combined group splits back into its two constituents, the **upper** constituent inherits the parent's code with a `0` appended and the **lower** constituent inherits the parent's code with a `1` appended. Continue until every group is a single symbol; the bits accumulated along the way are that symbol's Huffman codeword.

Equivalently, as a Huffman tree: at each branch the left child edge is `1` and the right child edge is `0`; reading edges from root to a leaf gives that leaf's code. (When drawing the tree, the smaller-probability child is placed on the left, i.e. the left/`1` side.) Both the table method and the tree method give identical codes.

### 2.4 Fully worked example (this is the canonical example — test pattern 2)

Suppose the 100 pixels produce these probabilities:

A1 = 0.1, A2 = 0.4, A3 = 0.06, A4 = 0.1, A5 = 0.04, A6 = 0.3.

**Initial sort (C0), high to low, smaller index wins ties:**

```
A2  0.4
A6  0.3
A1  0.1
A4  0.1
A3  0.06
A5  0.04
```

**C1 — merge the two smallest, A3 (0.06) and A5 (0.04) → {A3,A5} = 0.1.** It ties with A1 and A4 at 0.1; by the combination tie rule the merged group goes last in that cluster, so it sits below A4:

```
A2        0.4
A6        0.3
A1        0.1
A4        0.1
{A3,A5}   0.1
```

**C2 — merge the two smallest, A4 (0.1) and {A3,A5} (0.1) → {A4,A3,A5} = 0.2.** 0.2 is bigger than A1's 0.1 but smaller than A6's 0.3, so it re-orders to sit between A6 and A1:

```
A2            0.4
A6            0.3
{A4,A3,A5}    0.2
A1            0.1
```

**C3 — merge the two smallest, {A4,A3,A5} (0.2) and A1 (0.1) → {A4,A3,A5,A1} = 0.3.** It ties with A6 at 0.3; merged group goes last, so below A6:

```
A2              0.4
A6              0.3
{A4,A3,A5,A1}   0.3
```

**C4 — merge the two smallest, A6 (0.3) and {A4,A3,A5,A1} (0.3) → {A6,A4,A3,A5,A1} = 0.6.** Two groups remain; done combining:

```
{A6,A4,A3,A5,A1}   0.6   (upper)
A2                 0.4   (lower)
```

**Split.** Upper group gets `0`, lower gets `1`:
- A2 = `1`
- {A6,A4,A3,A5,A1} = `0`

Undo C4: {A6,A4,A3,A5,A1} splits into A6 (upper) and {A4,A3,A5,A1} (lower):
- A6 = `0` + `0` = `00`
- {A4,A3,A5,A1} = `0` + `1` = `01`

Undo C3: {A4,A3,A5,A1} splits into {A4,A3,A5} (upper) and A1 (lower):
- {A4,A3,A5} = `01` + `0` = `010`
- A1 = `01` + `1` = `011`

Undo C2: {A4,A3,A5} splits into A4 (upper) and {A3,A5} (lower):
- A4 = `010` + `0` = `0100`
- {A3,A5} = `010` + `1` = `0101`

Undo C1: {A3,A5} splits into A5 (upper) and A3 (lower):
- A5 = `0101` + `0` = `01010`
- A3 = `0101` + `1` = `01011`

**Final codes for this example:**

| Symbol | P    | Huffman code |
|--------|------|--------------|
| A1     | 0.1  | 011          |
| A2     | 0.4  | 1            |
| A3     | 0.06 | 01011        |
| A4     | 0.1  | 0100         |
| A5     | 0.04 | 01010        |
| A6     | 0.3  | 00           |

These are prefix-free: no codeword is a prefix of another, so a concatenated bitstream decodes unambiguously without separators.

### 2.5 Codeword + mask output convention (critical for the HC/M outputs)

Each Huffman codeword is variable-length, but the outputs HC*i* and M*i* are fixed 8-bit buses. The convention:

- **M*i* (mask):** the low *L* bits are `1`, where *L* is the codeword length; all higher bits are `0`. The mask says how many bits of HC*i* are valid.
- **HC*i* (code):** the codeword placed in the low *L* bits, **right-aligned**, read left-to-right of the codeword as MSB-to-LSB of those *L* bits. All bits above bit *L*−1 are `0`.

Worked from the example:
- A6 code `00`, length 2 → M6 = `0000_0011` (0x03), HC6 = `0000_0000` (0x00).
- A3 code `01010`… *(note: the PDF prose at §2.3.1 says "A3 = 01010" but its own final table and golden data for pattern 2 give A3 = `01011`; the value placed on HC follows the actual code. The point of the example is the format: length 5 → M = `0001_1111` = 0x1F, and HC = the 5-bit code right-aligned. For code `01011`, HC = `0000_1011` = 0x0B.)*
- A1 code `011`, length 3 → M1 = `0000_0111` (0x07), HC1 = `0000_0011` (0x03).
- A2 code `1`, length 1 → M2 = `0000_0001` (0x01), HC2 = `0000_0001` (0x01).
- A4 code `0100`, length 4 → M4 = `0000_1111` (0x0F), HC4 = `0000_0100` (0x04).
- A5 code `01010`, length 5 → M5 = `0001_1111` (0x1F), HC5 = `0000_1010` (0x0A).

### 2.6 Decoding (informational)

With the example codes, the bitstream `1 0 1 0 0 1 0 0 0 1 1 1 1 0 0 1` decodes as A2 A4 A2 A6 A1 A2 A2 A6 A2, illustrating the prefix-free property. Decoding is not part of this module — it only generates the codes — but it shows why the codes must be exactly correct.

---

## 3. Interface

The port list below follows the **authoritative testbench (`test.sv`)** and the design entry point (`initial.sv`). The top module is named **`TOP`** (not `huffman`), and the reset port is named **`rst`** (not `reset`). In the testbench, the six CNT/HC/M outputs are connected positionally — `.CNT1(CNT[1])` … `.CNT6(CNT[6])`, and likewise for HC and M.

| Signal | Dir | Width | Meaning |
|--------|-----|-------|---------|
| `clk` | In | 1 | System clock. Design is synchronous, **positive-edge triggered**. |
| `rst` | In | 1 | **Active-high asynchronous** reset. |
| `gray_valid` | In | 1 | High while pixel data is valid on `gray_data`. |
| `gray_data` | In | 8 | One grayscale pixel per cycle while `gray_valid` is high (values 0x01–0x06). |
| `CNT_valid` | Out | 1 | High for exactly one cycle when CNT1–CNT6 hold the final counts. |
| `CNT1`…`CNT6` | Out | 8 each | Count of symbols A1…A6 respectively. Valid the cycle `CNT_valid` is high. |
| `code_valid` | Out | 1 | High for exactly one cycle when the codeword/mask outputs are final. |
| `HC1`…`HC6` | Out | 8 each | Huffman codeword for A1…A6, right-aligned, valid when `code_valid` is high. |
| `M1`…`M6` | Out | 8 each | Mask for A1…A6 (low *L* bits set), valid when `code_valid` is high. |

**Interaction.** `gray_valid` gates input counting: each cycle it is high, `gray_data` is one more pixel to tally. When `gray_valid` falls, counting is complete and the design proceeds to compute counts, then codes. `CNT_valid` and `code_valid` are one-cycle strobes that tell the testbench when to sample the respective output groups; they are not held. CNT results come first, code results later, in two separate strobes.

---

## 4. Timing / protocol

All design logic is **positive-edge** triggered on `clk`; the testbench drives its stimulus on the **negative edge**. Clock period is fixed at 10 ns. The testbench will not be modified.

**Reset.** The testbench holds `rst` low at time 0, raises it to 1 after one cycle, and lowers it back to 0 two cycles later — i.e. `rst` is asserted high for two clock cycles, then released. Reset is asynchronous and active-high: assertion immediately clears state.

**Input phase (counting).** After reset, the testbench waits a few cycles, then on a negative clock edge asserts `gray_valid = 1` and places the first pixel `pattern[0]` on `gray_data`. On each subsequent negative edge it advances to the next pixel, for 100 pixels total (`pattern[0]` … `pattern[99]`). After the 100th, on the next negative edge it lowers `gray_valid` to 0 and drives `gray_data` to 0. The design samples this stream on its positive edges. Because the data is updated on the negative edge, each pixel is stable across the positive edge that follows.

**Output phase (counts).** Once the design has finished tallying, it raises `CNT_valid` high for exactly one clock cycle and, during that cycle, presents the six counts on CNT1–CNT6. The testbench samples and compares them against the golden counts on the negative edge while `CNT_valid` is high. If the counts are wrong the simulation stops there.

**Output phase (codes).** After the design has computed all six Huffman codes and masks, it raises `code_valid` high for exactly one clock cycle and, during that cycle, presents HC1–HC6 and M1–M6. The testbench samples and compares HC and M against golden values. When `code_valid` returns low and the comparison is done, the simulation ends. A full pass requires CNT, HC, and M all to match.

---

## 5. Memory / data layout

There is no external image memory; pixels arrive as a serial stream. The relevant "memory" is the two arrays the testbench loads from `.dat` files.

**Pattern file** (`pattern1.dat` / `pattern2.dat` / `pattern3.dat`): 100 bytes, read by `$readmemh` into `pat_mem[0:99]`. Each byte is one pixel value, 0x01–0x06. They are fed in array order, index 0 first.

**Golden file** (`golden1.dat` / `golden2.dat` / `golden3.dat`): **18 bytes**, read into `exp_mem[0:17]`. The testbench compares them in this exact order:

| exp_mem index | compared against |
|---------------|------------------|
| 0–5   | CNT1, CNT2, CNT3, CNT4, CNT5, CNT6 |
| 6–11  | HC1, HC2, HC3, HC4, HC5, HC6 |
| 12–17 | M1, M2, M3, M4, M5, M6 |

The testbench packs each group of six into a 48-bit value (`{CNT1,…,CNT6}` etc.) and compares equality, so all six entries in a group must be correct simultaneously.

**Sample golden values** (from the three provided test patterns, useful as regression checks):

*Pattern 1* (counts: A1=3, A2=6, A3=2, A4=51, A5=13, A6=25; codes A1=`11110`, A2=`1110`, A3=`11111`, A4=`0`, A5=`110`, A6=`10`):

| Symbol | CNT (hex) | HC (hex) | M (hex) |
|--------|-----------|----------|---------|
| A1 | 0x03 | 0x1E | 0x1F |
| A2 | 0x06 | 0x0E | 0x0F |
| A3 | 0x02 | 0x1F | 0x1F |
| A4 | 0x33 | 0x00 | 0x01 |
| A5 | 0x0D | 0x06 | 0x07 |
| A6 | 0x19 | 0x02 | 0x03 |

*Pattern 2* (the worked example; counts A1=10, A2=40, A3=6, A4=10, A5=4, A6=30):

| Symbol | CNT (hex) | HC (hex) | M (hex) |
|--------|-----------|----------|---------|
| A1 | 0x0A | 0x03 | 0x07 |
| A2 | 0x28 | 0x01 | 0x01 |
| A3 | 0x06 | 0x0A | 0x1F |
| A4 | 0x0A | 0x04 | 0x0F |
| A5 | 0x04 | 0x0B | 0x1F |
| A6 | 0x1E | 0x00 | 0x03 |

*(Note: the PDF's pattern-2 table lists A3 HC = 0x0A / A5 HC = 0x0B, which corresponds to swapping which of A3/A5 sits on the left/right of the lowest merge. Follow the golden file as the authority; the table above reproduces the PDF's golden listing.)*

*Pattern 3* (counts A1=9, A2=7, A3=36, A4=8, A5=10, A6=30; codes A1=`0001`, A2=`0011`, A3=`1`, A4=`0010`, A5=`0000`, A6=`01`):

| Symbol | CNT (hex) | HC (hex) | M (hex) |
|--------|-----------|----------|---------|
| A1 | 0x09 | 0x01 | 0x0F |
| A2 | 0x07 | 0x03 | 0x0F |
| A3 | 0x24 | 0x01 | 0x01 |
| A4 | 0x08 | 0x02 | 0x0F |
| A5 | 0x0A | 0x00 | 0x0F |
| A6 | 0x1E | 0x01 | 0x03 |

---

## 6. Reference implementation (from `initial.sv`)

`initial.sv` contains a working reference design, module `TOP`.

**Algorithm level.** It counts pixels into a per-symbol count array, then repeatedly finds the two minimum-count groups, merges them (assigning a `1` bit to the group that becomes the upper branch and `0` to the lower, prepended into each member's code register), and tracks group membership until one merged group reaches count 100 — at which point all symbols are coded.

**Micro-architecture.** A four-state FSM (`ACCEPT`, `FIND_MIN1`, `COMPARE`, `FINAL`) clocked on the positive edge with asynchronous active-high `rst`.
- `ACCEPT`: while `gray_valid`, increments `CNT_array[gray_data]` (indexing the count array directly by the pixel value 1–6). A small `counter` lets reset/startup settle; when `gray_valid` drops and the counter has saturated, it raises `CNT_valid` for one cycle and moves on.
- `FIND_MIN1`: a bubble-style scan across the six entries to find the two smallest counts (`min1`, `min2`) and their group indices, using the equal-count tie-breaking via `CNT_group` / `group_count`.
- `COMPARE`: for every symbol belonging to either selected group, shifts a new MSB into its `HC_array` register (`1` for group1, `0` for group2) and increments its `M_array` length, then reassigns those members to a new group id, sums the two counts into one slot and sets the other to 255 (so it's never picked again). Loops back to `FIND_MIN1` until a merged count hits 100.
- `FINAL`: raises `code_valid`.

Output formatting: `M`*i* `= 255 >> (8 - length)` builds the low-*L*-ones mask, and `HC`*i* `= HC_array[i] >> (8 - length)` right-aligns the accumulated code. Counts are driven straight from `CNT_array`.

This reference builds codes MSB-first by left-shifting bits into the high end of each code register and then right-aligning at output, which is one valid way to realize the split-phase bit assignment described in §2.

---

## 7. Differences from the original problem (PDF vs. environment)

- **Top module is `TOP`**, not the PDF's `huffman`. The testbench instantiates `TOP`.
- **Design is entered via `initial.sv`** (which defines module `TOP`), not `huffman.v`/`huffman.vhd` as the PDF appendix states.
- **Reset port is named `rst`** (active-high asynchronous, asserted two cycles), not `reset` as in the PDF table — same polarity and behavior, different name.
- **Pattern/golden file paths** are `./00_TB/pattern*.dat` and `./00_TB/golden*.dat` per `test.sv`, not the bare `./pattern*.dat` shown in the PDF appendix. SDF (gate-level) path is `../02_SYN/Netlist/top_syn.sdf`.
- The PDF §2.3.1 prose example states A3's code as `01010`, but the PDF's own final example table and the pattern-2 golden data use `01011` for A3 (and `01010` for A5). The **golden files are authoritative**; the formatting rule (mask = low-*L*-ones, code right-aligned) is unaffected.
- Scoring grades, submission/FTP steps, EDA tool versions, and report-file format from the PDF are omitted as irrelevant to solving/verifying the RTL.