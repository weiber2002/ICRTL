# IoT Data Filtering Circuit — Design Specification

## 1. Overview

This module is an **IoT Data Filtering** accelerator. It receives a stream of fixed-size sensor data records, groups them into rounds of 8, and applies one of seven selectable filter/reduction functions (max, min, average, range-extract, range-exclude, running-peak-max, running-peak-min) to each round, emitting results on a wide output bus. Exactly one function is active for a given simulation, chosen by a 3-bit selector that never changes mid-run. The total input is fixed at **96 records of 128 bits each** (12 rounds of 8).

## 2. What the module must do (functional description)

### 2.1 Data shape and rounds

Every input record is a **128-bit unsigned integer**. Records arrive 8 bits per cycle, most-significant byte first, so one record takes 16 cycles to load. There are 96 records total, processed as **12 rounds of 8 records each**. Each round's 8 records are consumed by the active function to produce zero or one (or, for the filter functions, several) 128-bit outputs. A round's 8 values are never reused by the next round.

The seven functions are selected by `fn_sel`:

| `fn_sel` | Function | What it does per round |
|---|---|---|
| `3'b001` (F1) | Max(N) | Output the maximum of the round's 8 values. |
| `3'b010` (F2) | Min(N) | Output the minimum of the round's 8 values. |
| `3'b011` (F3) | Avg(N) | Output the integer average (sum of 8 ÷ 8, fractional part truncated). |
| `3'b100` (F4) | Extract(low < data < high) | Output every value strictly between fixed `low` and `high`. |
| `3'b101` (F5) | Exclude(data < low or high < data) | Output every value strictly below fixed `low` or strictly above fixed `high`. |
| `3'b110` (F6) | PeakMax | Running maximum: output a new value only when it exceeds every previously output value. |
| `3'b111` (F7) | PeakMin | Running minimum: output a new value only when it is below every previously output value. |

Note `fn_sel = 3'b000` is unused. For F1/F2/F3 every round produces exactly one output, so a 96-record run yields exactly **12 outputs**. For F4/F5/F6/F7 a round may produce zero, one, or many outputs — outputs are not guaranteed per round.

### 2.2 Worked examples (from the PDF figures)

The PDF illustrates each function with 8-bit values (the real data is 128-bit; the logic is identical). Take a first round of 8 bytes `34 F2 77 62 32 D9 15 CF` and a second round `57 D2 DC 13 68 49 F0 A5`:

- **F1 Max:** round 0 → `F2` (largest), round 1 → `F0`. Output sequence: `F2, F0, …`
- **F2 Min:** round 0 → `15`, round 1 → `13`. Output sequence: `15, 13, …`
- **F3 Avg:** round 0 → `(34+F2+77+62+32+D9+15+CF)/8 = 7D`, round 1 → `(57+D2+DC+13+68+49+F0+A5)/8 = 8B`. Output sequence: `7D, 8B, …`. The division **truncates** any fractional part (floor).
- **F4 Extract** with `low = 0x30`, `high = 0x70` (example values): output every value with `low < v < high`. Round 0 → `34, 62, 32`; round 1 → `57, 68, 49`. Values equal to a bound are **not** emitted (strict inequalities).
- **F5 Exclude** with the same example bounds: output every value with `v < low` **or** `v > high`. Round 0 → `F2, 77, D9, 15, CF`; round 1 → `D2, DC, 13, F0, A5`.
- **F6 PeakMax:** round 0's max is `F2`, output it. Round 1's max is `F0`, which is **not** greater than `F2`, so round 1 emits nothing. Only a later round whose max exceeds `F2` would emit. Output sequence so far: `F2, …`
- **F7 PeakMin:** round 0's min is `15`, output it. Round 1's min is `13`, which **is** below `15`, so output `13`. Output sequence: `15, 13, …`

### 2.3 The fixed bounds for F4 and F5 (real contest values, 128-bit)

These are hard-coded in the design, not supplied as ports:

- **F4 Extract:** `low = 128'h6FFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF`, `high = 128'hAFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF`. Emit `v` when `low < v < high`.
- **F5 Exclude:** `low = 128'h7FFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF`, `high = 128'hBFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF`. Emit `v` when `v < low` or `v > high`.

### 2.4 Expected output counts (from the testbench)

The golden files fix how many outputs each function produces over the full 96-record run: F1/F2/F3 → 12 each; F4 → 25; F5 → 73; F6 → 3; F7 → 4. A correct design emits exactly these counts in order.

## 3. Interface

Port list from the authoritative `TOP` module (`initial.sv`) and its instantiation in `tb.sv`. **The top module is named `TOP`** (the PDF block diagram labels it IOTDF). **Reset is `rst`, active-high asynchronous.**

| Signal | Dir | Width | Meaning |
|---|---|---|---|
| `clk` | In | 1 | Clock, positive-edge triggered. |
| `rst` | In | 1 | **Active-high, asynchronous** reset. |
| `in_en` | In | 1 | Input-enable from the host. High means the byte on `iot_in` this cycle is valid input. |
| `iot_in` | In | 8 | One byte of the current 128-bit record (MSB byte first). |
| `fn_sel` | In | 3 | Selects which of the seven functions is active; constant for the whole run. |
| `busy` | Out | 1 | High when the design cannot accept new input this cycle; Low when it can. |
| `valid` | Out | 1 | High when `iot_out` holds a valid result this cycle. |
| `iot_out` | Out | 128 | The 128-bit result, emitted in a single cycle when `valid` is High. |

**How the signals interact.** `busy` and `in_en` form the input handshake. When `busy` is Low, the host drives `in_en` High and presents a byte on `iot_in`; when `busy` is High, the host holds `in_en` Low and `iot_in` at 0 (input paused). The design raises `busy` whenever it needs to stall input (e.g. while computing/emitting a result). Output uses `valid`: whenever the design has a result, it raises `valid` for one cycle and drives the full 128-bit value on `iot_out`. The host samples `iot_out` on every cycle where `valid` is High and compares it, in order, against the golden result file for the selected function. Once the host has sent all 96 records and the design has emitted all expected results, the simulation ends.

## 4. Timing / protocol

The clock is **positive-edge** triggered; reset is **asynchronous active-high**.

### 4.1 Reset

In `tb.sv`: after the first rising clock edge, `rst` is driven High (with a small `#1` delay) and held for one full cycle, then dropped Low. The design must reset its state asynchronously while `rst` is High and begin operating once `rst` returns Low. (The reference design uses `always @(posedge clk or posedge rst)`.)

### 4.2 Input handshake (`busy`, `in_en`, `iot_in`) — cycle by cycle

The host loop runs once per rising clock edge:

1. After reset, the design lowers `busy` to signal it can accept data.
2. On a cycle where the host sees `busy` Low: shortly after the edge (`#1` in the bench) it drives the next byte onto `iot_in` and raises `in_en` High. The first byte of a record is bits `[127:120]` (MSB byte), the next is `[119:112]`, …, the 16th is `[7:0]`.
3. The host advances its byte counter; after 16 bytes it advances to the next record. This repeats until all 96 records are sent.
4. On any cycle where the host sees `busy` High: it drives `iot_in = 0` and `in_en` Low — input is paused. The design may raise `busy` whenever it needs to stall (for example to finish a computation or emit a result).
5. After all input is sent, `in_en` stays Low for the rest of the simulation.

So one complete record is 16 consecutive accepted bytes (16 cycles if never stalled), MSB byte first. The design assembles the 128-bit record by shifting each incoming byte into the low end of an accumulator (`in_r = {in_r, iot_in}`), so after 16 bytes the first byte sits in bits `[127:120]`.

### 4.3 Output handshake (`valid`, `iot_out`)

When the design has a result, it raises `valid` High and places the 128-bit value on `iot_out` in the same cycle (a result takes only one cycle to output). The host, in an `always @(posedge clk)` block, samples `iot_out` whenever `valid` is High, compares against the next expected golden word, and increments its output index. `valid` must be Low on cycles with no valid output. Results must come out in the exact order the golden file lists them.

## 5. Memory / data layout

There is no addressed memory interface in this design — data streams through ports. The relevant layout facts are how records and golden results are organized:

- **Input pattern (`pattern1.dat`):** 96 entries, each a 128-bit hex word, the same set of records for all seven functions. Read into `pat_mem[0:95]`. Record `i` is streamed MSB-byte-first as described above. Records 0–7 form round 0, 8–15 round 1, …, 88–95 round 11.
- **Golden outputs (`f1.dat`…`f7.dat`):** one file per function, each a list of 128-bit hex words giving the expected outputs in emission order. Lengths: `f1`/`f2`/`f3` = 12 words, `f4` = 25, `f5` = 73, `f6` = 3, `f7` = 4. The testbench selects the file and sets `fn_sel` based on which `+define+F1..F7` macro is active (default F1).

A small sample of the input pattern (first records, from the PDF appendix), to anchor a regression check:

| Index | Round | 128-bit record (hex) |
|---|---|---|
| 0 | 0 | `1A_A9_92_A8_74_2B_E4_86_B7_89_00_B6_8F_C1_38_1D` |
| 1 | 0 | `D1_99_D7_A0_25_9F_50_AA_B8_CA_1A_89_78_5D_99_5B` |
| 2 | 0 | `FA_0F_13_92_4B_6C_48_75_BD_5F_5E_96_5C_8C_6F_C9` |
| 8 | 1 | `C8_C2_6D_6A_08_E4_0A_1E_4B_C4_69_DA_32_5A_2F_9E` |

And the first few F1 (Max) golden outputs:

| Output index | Round | Expected max (hex) |
|---|---|---|
| 0 | 0 | `FA_0F_13_92_4B_6C_48_75_BD_5F_5E_96_5C_8C_6F_C9` |
| 1 | 1 | `F8_B5_ED_42_4B_D8_D4_8C_45_61_A1_60_10_20_2C_1F` |
| 2 | 2 | `C8_82_4C_5D_1D_86_50_29_5A_E7_40_FE_09_64_68_C3` |

## 6. Reference implementation (from `initial.sv`)

**Algorithm level.** A 3-state machine (`IDLE → INPUT → OUTPUT`) gathers each record byte-by-byte, and once 8 records (one round) are in, computes the selected function. For F1/F2 it keeps a running max/min `num_r` across the round; for F3 it accumulates the sum and, at output, shifts right by 3 (÷8, truncating) — the `num_r` register is 131 bits wide to hold the sum of eight 128-bit values without overflow. F4/F5 are stateless per value: as each record completes, it is compared against the fixed bounds and emitted immediately on `valid`/`iot_out` if it passes. F6/F7 keep a running peak across the whole stream and emit only when a round's max/min beats the stored peak (seeded so the first round always outputs). F7's peak register is initialized to all-ones in IDLE so the first minimum compares correctly.

**Micro-architecture.** Two always-blocks: a combinational next-state/output block and a sequential register block clocked on `posedge clk or posedge rst` (active-high async reset clears state to `IDLE`). Key registers: `state_r`; `in_r` (120-bit shift accumulator that, combined with the incoming byte, forms the 128-bit record); `in_count_r` (0–15, byte position within a record); `num_count_r` (0–7, record position within a round); `num_r` (running result / accumulator, 131 bits); `first_count_r` (a small flag used by F6/F7 to handle the first-round output). `busy` is driven Low in `IDLE` and during `INPUT` while accepting bytes, and High when transitioning to `OUTPUT` (F1/F2/F3, which emit once per round from the dedicated `OUTPUT` state). For F4–F7, results are emitted directly from within the `INPUT` state as each qualifying value/round completes, so those functions never enter the separate `OUTPUT` state.

## 7. Differences from the original problem

- **Module name:** the design module is `TOP`, not the PDF's `IOTDF`. (From `tb.sv`/`initial.sv`.)
- **Design entry point:** the design is written in `initial.sv`, which already declares the `TOP` port list (and uses SystemVerilog `typedef enum`).
- **Reset polarity/name:** the reset port is `rst`, active-high asynchronous (`posedge rst`), matching the PDF's "active high"; the PDF's text alternately calls it `reset` in places.
- **F4/F5 bounds are internal constants:** the PDF/testbench show commented-out `low`/`high` ports, but in the authoritative `TOP` they are hard-coded `localparam`s inside the design (F4: `low=0x6FFF…`, `high=0xAFFF…`; F5: `low=0x7FFF…`, `high=0xBFFF…`). `TOP` has no `low`/`high` ports.
- **Function selection is via testbench macros:** `tb.sv` chooses the function and golden file from `+define+F1..F7` and sets `fn_sel` accordingly (default F1); there is one shared input pattern for all functions.
- **Data/file paths:** the harness reads `./00_TB/pattern1.dat` and `./00_TB/f1.dat … f7.dat`; the SDF file is `./IOTDF_syn.sdf` annotated onto the instance `u_IOTDF`. Cycle time in the bench is 10 ns.
- **Omitted as irrelevant to solving the problem:** contest scoring tiers (A/B/C/D, `Score = Power × Time`), APR/DRC/LVS/power-analysis procedures, submission/report-form metadata, and EDA tool-version and design-library lists from the PDF appendices.