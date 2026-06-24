# Image Convolution Circuit (CONV) Accelerator— Design Specification

## 1. Overview

This module is a small two-layer convolutional-neural-network accelerator for a single grayscale image. It reads a 64×64 grayscale image one pixel at a time from a testbench memory, runs a 3×3 convolution (with zero-padding and a fixed kernel plus bias) followed by a ReLU activation to produce **Layer 0** (a 64×64 feature map), then runs a 2×2 max-pooling with stride 2 over that feature map to produce **Layer 1** (a 32×32 map). It writes Layer 0 back to memory bank `L0_MEM0` and Layer 1 to memory bank `L1_MEM0`, selecting the bank via a channel-select signal. All pixel values are 20-bit signed fixed-point numbers: 4 integer bits (MSBs) + 16 fractional bits (LSBs).

## 2. What the module must do (functional description)

### 2.1 Data format

Every pixel — input, intermediate, and output — is a **20-bit signed fixed-point** value: the top 4 bits are the integer part, the bottom 16 bits are the fraction. So the raw 20-bit hex value `0x10000` represents `1.0`, `0x08000` represents `0.5`, and `0xF8000` (a negative number, sign bit set) represents `-0.5`.

### 2.2 The pipeline, layer by layer

**Layer 0 = zero-padding → convolution → ReLU.** The 64×64 input image is conceptually surrounded by a one-pixel border of zeros (making it 66×66), then convolved with a single fixed 3×3 kernel. Because of the zero-padding, the convolution output is again 64×64 (one output pixel per input pixel). A fixed bias is added to every convolution result, and finally ReLU is applied. The result is a 64×64 Layer-0 feature map.

**Layer 1 = max-pooling.** A 2×2 window slides over the 64×64 Layer-0 map with stride 2 (non-overlapping windows), emitting the maximum of each 2×2 block. This halves both dimensions, producing a 32×32 Layer-1 map.

### 2.3 Convolution, in detail

Convolution here is the standard "slide a 3×3 kernel over the image, multiply-and-accumulate" operation. Place the 3×3 kernel over a 3×3 patch of the (padded) image so the kernel center sits on the current output pixel. Multiply each of the 9 image pixels by the kernel weight directly above it, sum all 9 products, then add the bias. Slide the kernel one pixel to the right and repeat; at the end of a row, drop down one row and continue, scanning left-to-right, top-to-bottom.

**Worked example (from the problem's convolution figure).** Take this image patch and kernel (small integers for illustration; the real kernel is fractional, given below):

```
image patch        kernel
 1 2 3             2 0 1
 0 1 2             0 1 2
 3 0 1             1 0 3
```

Element-by-element multiply and sum:
`1·2 + 2·0 + 3·1 + 0·0 + 1·1 + 2·2 + 3·1 + 0·0 + 1·3 = 2 + 0 + 3 + 0 + 1 + 4 + 3 + 0 + 3 = 16`.

Slide one pixel right and the same arithmetic on the next patch gives `18`, and so on, producing a grid of convolution results such as:

```
16 18 20
 6 16 12
12 19  9
```

Then **add the bias** to every element. In the figure the illustrative bias is `-0.5`, turning the first row `16 18 20` into `15.5 17.5 19.5`, the second row into `5.5 15.5 11.5`, and the third into `11.5 18.5 8.5`. That biased grid is the convolution output, which then feeds ReLU.

### 2.4 Zero-padding, in detail

Plain convolution shrinks the image. To keep the output the same size as the input, the image is padded with a one-pixel ring of zeros before convolving. Conceptually a 4×4 image becomes 6×6:

```
0 0 0 0 0 0
0 1 2 3 0 0
0 0 1 2 3 0
0 3 0 1 2 0
0 2 3 0 4 0
0 0 0 0 0 0
```

When the kernel center sits on a border pixel, the taps that fall outside the original image read zero. In hardware this is implemented not by physically storing the padded image, but by checking the current pixel coordinates `(x, y)` and substituting `0` for any of the 9 neighbors whose row or column would fall outside `0..63` (i.e. neighbors above row 0, below row 63, left of column 0, or right of column 63 contribute 0).

### 2.5 ReLU, in detail

ReLU clamps negatives to zero:

```
y = x   if x > 0
y = 0   if x <= 0
```

Every biased convolution pixel passes through ReLU; the result is the final Layer-0 value written to memory. (In the reference implementation this is done by inspecting the sign bit of the accumulated sum and writing `0` when it is negative.)

### 2.6 The fixed Kernel 0 and bias

The single 3×3 kernel (`Kernel 0`), as 20-bit signed fixed-point (4int+16frac) hex values, laid out in row-major 3×3 order:

```
0x0A89E  0x092D5  0x06D43      ( ≈  0.658674   0.573572   0.426810 )
0x01004  0xF8F71  0xF6E54      ( ≈  0.062562  -0.439696  -0.569037 )
0xFA6D7  0xFC834  0xFAC19      ( ≈ -0.348290  -0.217964  -0.327755 )
```

The **bias** is `0x13100` in 20-bit form (≈ `0.07446326` decimal). The reference design holds it as a 40-bit value `0x0013100000` aligned to match the 40-bit product accumulator (see §6).

### 2.7 Output rounding / saturation

`L0_MEM0` stores 20-bit values (4int+16frac), but the true convolution accumulator is wider than 20 bits. The designer must take 4 integer bits + 16 fractional bits and **round** based on bit 17 (the first dropped fractional bit): round half up. The reference implementation adds 1 to the truncated 20-bit result when that rounding bit is set, and clamps negative results to 0 as part of ReLU.

### 2.8 Max-pooling, in detail

A 2×2, stride-2 window scans the 64×64 Layer-0 map left-to-right, top-to-bottom, and outputs the maximum of each non-overlapping 2×2 block.

**Worked example (from the pooling figure).** For a block whose four values are `5, 7, 0, 1` the output is `max(5,7,0,1) = 7`. Slide right by two columns to the block `7, 3, 2, 3` and the output is `max = 7`, and so on. A 64×64 input therefore yields a 32×32 output.

### 2.9 Border / size summary

- Input image: 64×64, 4096 pixels.
- Layer 0 output: 64×64, 4096 pixels (padding keeps the size).
- Layer 1 output: 32×32, 1024 pixels.

## 3. Interface

The port list below is taken from the authoritative top module in `initial.sv` and the instantiation in `test.sv`. **The top module is named `TOP`** (not `CONV`), and **reset is named `rst`**.

| Signal | Dir | Width | Meaning |
|---|---|---|---|
| `clk` | In | 1 | System clock. Design is synchronous to the **rising (positive) edge**. |
| `rst` | In | 1 | **Active-high, asynchronous** reset. |
| `ready` | In | 1 | Testbench asserts High when image + kernel data are ready; CONV may then begin requesting input pixels. |
| `busy` | Out | 1 | CONV asserts High when it starts working, and returns it Low exactly once when all processing + writeback is done. |
| `iaddr` | Out | 12 | Address of the input grayscale pixel being requested (0..4095). |
| `idata` | In | 20 | Signed input pixel data returned for `iaddr` (4int+16frac). |
| `cwr` | Out | 1 | Write enable to the result memory. When High at a rising clock edge, `cdata_wr` is written to `caddr_wr`. |
| `caddr_wr` | Out | 12 | Write address into the selected result memory. |
| `cdata_wr` | Out | 20 | Signed result data to write (4int+16frac). |
| `crd` | Out | 1 | Read enable for the result memory. |
| `caddr_rd` | Out | 12 | Read address into the selected result memory. |
| `cdata_rd` | In | 20 | Signed read data returned from the selected memory. |
| `csel` | Out | 3 | Memory-bank select (see below). |

`csel` chooses which result memory the read/write targets:

- `3'b000` — no memory selected.
- `3'b001` — Layer 0 (convolution result), bank `L0_MEM0`.
- `3'b011` — Layer 1 (max-pooling result), bank `L1_MEM0`.

**How the signals interact.** `ready`/`busy` form the top-level handshake: the design waits for `ready`, raises `busy`, does all its work, then lowers `busy`. Input pixels are fetched on the `iaddr`/`idata` channel. Results live in two memory banks reached through a shared port group (`caddr_wr`/`cdata_wr`/`cwr` for writes, `caddr_rd`/`cdata_rd`/`crd` for reads); `csel` decides which bank that port group currently talks to. A write happens only while `cwr` is High; a read only while `crd` is High. During the whole `busy`-High interval the design may read and write `L0_MEM0`/`L1_MEM0` as many times as needed.

## 4. Timing / protocol

All design state updates on the **rising edge** of `clk`. Reset is **asynchronous, active-high**: while `rst` is High, registers are forced to their reset values regardless of the clock.

### 4.1 Startup / shutdown handshake

In `test.sv`: on a falling edge `rst` and `ready` are both raised, `rst` is held for 3 cycles then dropped, and the bench then waits for `busy==1` before dropping `ready` (a quarter-cycle after `busy` rises). So the sequence is:

1. Reset asserted; `ready` driven High by the bench.
2. Reset released. The design sees `ready` High and asserts `busy` High to start.
3. The bench observes `busy` High and drops `ready` Low.
4. The design runs the full Layer-0 then Layer-1 computation.
5. When everything (including writeback) is finished, the design drops `busy` Low **once**. The bench treats the falling edge of `busy` as "done" and immediately verifies memory.

`busy` must rise exactly once and fall exactly once per image. (In the reference design, `busy` rises as soon as `ready` is seen and falls when the FSM reaches its `FINISH` state.)

### 4.2 Input read protocol (`iaddr` → `idata`)

The design drives `iaddr` with the pixel address it wants. The testbench, in an `always @(negedge clk)` block, returns `idata <= PAT[iaddr]` — i.e. the requested pixel appears on `idata` **after the falling edge that follows** the cycle in which `iaddr` was driven. Practically: present an address this cycle, and the corresponding data is available the next cycle (a one-cycle read latency through the negedge-updated bench register). When the design is not actively fetching (`ready==0 & busy==1` is false), the bench drives `idata` to `x`.

### 4.3 Result-memory read protocol (`crd`, `caddr_rd` → `cdata_rd`)

The bench services reads on the **falling** edge of `clk`: if `crd` is High at that negedge, `cdata_rd` is updated from the selected bank (`L0_MEM0` for `csel==3'b001`, `L1_MEM0` for `csel==3'b011`) at the address on `caddr_rd`. So drive `crd`, `caddr_rd`, and `csel` from a rising edge and the data is ready after the following falling edge.

### 4.4 Result-memory write protocol (`cwr`, `caddr_wr`, `cdata_wr`)

The bench services writes on the **rising** edge of `clk`: if `cwr` is High at a posedge, the current `cdata_wr` is written into the selected bank at `caddr_wr`. The bench also records that the corresponding layer produced output (its internal `check0`/`check1` flag) so that an all-zero / no-write layer is reported as a failure rather than silently passing.

## 5. Memory layout

All three memories are **row-major**: for an image of width `W`, the pixel at row `r`, column `c` lives at linear address `r·W + c`.

**Input image (`PAT`, read via `iaddr`/`idata`):** 64×64 = 4096 entries, addresses 0..4095, each 20 bits. Address = `row·64 + col`. So pixel (row 0, col 0) is at address 0, (row 0, col 63) at 63, (row 1, col 0) at 64, …, (row 63, col 63) at 4095. The reference design forms addresses by concatenating the 6-bit row and 6-bit column: `iaddr = {y, x}`.

**Layer 0 output (`L0_MEM0`, `csel==3'b001`):** 64×64 = 4096 entries, addresses 0..4095, same row-major mapping as the input. Write address `caddr_wr = {y, x}`.

**Layer 1 output (`L1_MEM0`, `csel==3'b011`):** 32×32 = 1024 entries, addresses 0..1023. Address = `pooled_row·32 + pooled_col`. The reference design takes the full-resolution window origin `(L1_y, L1_x)` (which step by 2) and writes to `caddr_wr = {L1_y[5:1], L1_x[5:1]}` — i.e. divides each coordinate by 2.

Example address ↔ pixel correspondence (row-major, width 64) for the 64×64 banks:

| Address | (row, col) |
|---|---|
| 0 | (0, 0) |
| 1 | (0, 1) |
| 63 | (0, 63) |
| 64 | (1, 0) |
| 128 | (2, 0) |
| 4095 | (63, 63) |

(The source's memory figures label cells "Pixel 0 … Pixel 4096"; that labeling is 1-based and slightly inconsistent at the end. The authoritative ranges are the array bounds in `test.sv`: `[0:4095]` for the 64×64 banks and `[0:1023]` for the 32×32 bank.)

The testbench compares each written bank against golden data loaded from `cnn_layer0_exp0.dat` (Layer 0) and `cnn_layer1_exp0.dat` (Layer 1), reporting per-pixel mismatches. The stimulus image is loaded from `cnn_sti.dat`.

## 6. Reference implementation (from `initial.sv`)

**Algorithm level.** The reference `TOP` walks the image pixel by pixel. For each output position `(x, y)` it issues the 9 neighbor addresses, fetches the 9 input pixels (substituting 0 for out-of-range neighbors to realize zero-padding), multiplies each by the matching kernel tap, accumulates the 9 products, adds the bias, applies ReLU (clamp negative to 0) with rounding, and writes the 20-bit result to `L0_MEM0`. After Layer 0 is complete it reads back 2×2 blocks of `L0_MEM0`, keeps the running maximum of the four values, and writes each maximum to `L1_MEM0`.

**Micro-architecture.** An 8-state FSM (`IDLE, INPUT, L0_MEM, DELAY_CLK, READ_L0_MEM, L1_MEM, DELAY_CLK_2, FINISH`) drives everything:

- Coordinate registers `x, y` (current Layer-0 pixel, each incrementing 0..63) and `L1_x, L1_y` (max-pool window origin, stepping by 2).
- `counter_addr` / `counter_data` (0..10) sequence the 9 neighbor fetches plus the bias-add step; they are offset by one cycle to account for the one-cycle input read latency.
- The convolution datapath: `idata_tmp` holds the (possibly zero-padded) fetched pixel; `data_conv = idata_tmp * Kernel` is a 40-bit signed product; `data_conv_sum` accumulates the nine products and then the bias.
- Output forming: `conv_result` takes `data_conv_sum[35:16]` as the 20-bit value and adds 1 when `data_conv_sum[15]` (the rounding bit) is set; if the accumulator is negative (`data_conv_sum[39]` set), the written value is 0 (ReLU).
- `INPUT` fetches neighbors and accumulates; `L0_MEM` writes the Layer-0 pixel (`cwr=1`, `csel=001`, `caddr_wr={y,x}`); `READ_L0_MEM` reads the four pixels of a pooling window (`crd=1`, `csel=001`) and keeps the max in `cdata_wr`; `L1_MEM` writes the pooled result (`cwr=1`, `csel=011`); `FINISH` drops `busy`.
- Clocking: every sequential block is `always @(posedge clk or posedge rst)` with active-high async reset, matching the harness.

## 7. Differences from the original problem

- **Module name:** the design module is `TOP`, not the PDF's `CONV`. (From `test.sv`/`initial.sv`.)
- **Design entry point:** the design is written in `initial.sv`, which already declares the `TOP` port list.
- **Reset signal name:** the reset port is `rst` (the PDF/Appendix-B port list calls it `reset`). Polarity/timing unchanged: active-high asynchronous.
- **Data/expectation file paths:** the harness reads `./00_TB/dat_grad/cnn_sti.dat`, `cnn_layer0_exp0.dat`, `cnn_layer1_exp0.dat` (the PDF's Appendix B lists a `./dat_univ/` path); the SDF path is `../02_SYN/Netlist/top_syn.sdf` annotated onto `TOP`.
- **Single kernel:** there is one kernel (`Kernel 0`) and two layers (Conv+ReLU, then Max-pool); the result banks are `L0_MEM0` and `L1_MEM0`.
- **Omitted as irrelevant to solving the problem:** contest scoring tiers (S/A/B/C and the area threshold), submission/FTP/`report.000` procedures, and EDA tool-version/library lists from the PDF appendices.