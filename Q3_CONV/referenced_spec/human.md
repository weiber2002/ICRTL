
---

# Version A — Human-Readable Spec (CONV)

## 1) Goal & Scope

Implement module **`TOP`** that:

* Reads a **64×64** grayscale image from the testfixture via the `iaddr/idata` interface. Pixel data width is **20 bits (Q4.16)**. &#x20;
* Produces:

  1. **Layer 0**: **zero-padding(1) → 3×3 convolution (Kernel 0) → +bias → ReLU** ⇒ **64×64** result in Q4.16, written to **L0\_MEM0**.   &#x20;
  2. **Layer 1**: **2×2 max-pooling, stride 2** over Layer-0 output ⇒ **32×32** result in Q4.16, written to **L1\_MEM0**.&#x20;

---

## 2) Top-Level Ports (names, widths, meaning)

| Signal     | Dir | Width | Description                                                                                                                                                 |
| ---------- | --- | ----: | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `clk`      | I   |     1 | System clock, **posedge-synchronous**.                                                                                                                      |
| `rst`    | I   |     1 | **Asynchronous, active-high** rst.                                                                                                                        |
| `ready`    | I   |     1 | Testfixture asserts when inputs are prepared; `TOP` may start only after seeing `ready=1`.                                                                 |
| `busy`     | O   |     1 | Set **High** once to start work after seeing `ready=1`; set **Low** once when all required writes finish. Exactly **one rise** and **one fall** per image.  |
| `iaddr`    | O   |    12 | Address for input image (row-major, 0..4095).                                                                                                               |
| `idata`    | I   |    20 | Input pixel at `iaddr`, **Q4.16** (20-bit).                                                                                                                 |
| `crd`      | O   |     1 | Result memory **read enable** (see timing).                                                                                                                 |
| `cdata_rd` | I   |    20 | Read data from selected result memory (Q4.16).                                                                                                              |
| `caddr_rd` | O   |    12 | Read address.                                                                                                                                               |
| `cwr`      | O   |     1 | Result memory **write enable** (see timing).                                                                                                                |
| `cdata_wr` | O   |    20 | Write data (Q4.16).                                                                                                                                         |
| `caddr_wr` | O   |    12 | Write address.                                                                                                                                              |
| `csel`     | O   |     3 | Memory select: `3’b001` = **L0\_MEM0**, `3’b011` = **L1\_MEM0**.                                                                                            |

---

## 3) Handshake & Global Timing

1. **Start/End protocol**

   * After `rst` deasserts, testfixture sets `ready=1` when inputs (image & constants) are ready. On detecting `ready=1`, assert `busy=1` (start). When all mandated writes (L0 then L1) complete, deassert `busy` (end). **Exactly one** rising and **one** falling edge of `busy` per image. &#x20;

2. **Image memory read timing (`iaddr`→`idata`)**

   * Drive `iaddr` on/after a **posedge**; the testfixture returns the addressed pixel on `idata` **after the following negedge**. Keep `iaddr` stable until that negedge. (You may pipeline one address per cycle.)&#x20;

3. **Result memory timing (L0\_MEM0 & L1\_MEM0)**

   * **Read**: If `crd=1` at a **negedge**, `cdata_rd` immediately reflects the word at `caddr_rd` (for selected `csel`).&#x20;
   * **Write**: If `cwr=1` at a **posedge**, the testfixture writes `cdata_wr` to `caddr_wr` (for selected `csel`).&#x20;
   * **Select**: Use `csel=3’b001` to access **L0\_MEM0**; use `csel=3’b011` to access **L1\_MEM0**. &#x20;

---

## 4) Memories & Addressing

* **Input image**: 64×64 = **4096** pixels, row-major (`addr = y*64 + x`). Data width **20 bits (Q4.16)**. &#x20;
* **L0\_MEM0**: Layer-0 output, **64×64**, row-major, **20-bit Q4.16**. Access with `csel=3’b001`. Quantize per §5. &#x20;
* **L1\_MEM0**: Layer-1 output, **32×32**, row-major, **20-bit Q4.16**. Access with `csel=3’b011`.&#x20;

---

## 5) Numeric Format & Quantization

* All I/O and stored results are **20-bit Q4.16 two’s-complement** (4 integer bits incl. sign + 16 fractional bits).&#x20;
* **Round-to-nearest** when writing to memories using the **17th fractional bit**.

---

## 6) Layer Algorithms

### 6.1 Layer 0 — Zero-padding → 3×3 Convolution → +Bias → ReLU

* **Zero-padding**: Pad the input image with **1-pixel zeros** on all sides so that 3×3 stride-1 convolution preserves 64×64 size.&#x20;
* **Convolution** (stride 1):

  $$
  S(x,y)=\sum_{i=0}^{2}\sum_{j=0}^{2}K[i,j]\cdot I(x+i-1,\,y+j-1)
  $$

  where `I` is the padded image (Q4.16) and `K` is **Kernel 0** (Q4.16). After the sum, **add bias**, then **ReLU**: `S←max(S,0)`. &#x20;
* **Kernel 0 (decimal, Q4.16 constants)**:

  ```
  [ [  0.426810,  0.573572,  0.658674 ],
    [ -0.569037, -0.439696,  0.0625617],
    [ -0.327755, -0.217964, -0.348290] ]

   =

   [ [ 0x0A89E, 0x092D5, 0x06D43], 
     [ 0x01004, 0xF8F71, 0xF6E54], 
     [ 0xFA6D7, 0xFC834, 0xFAC19] ]
  ```

  (Hex Q4.16 provided in the brief as well.) &#x20;
* **Bias**: `+0.07446326` (decimal), **Q4.16** = `0x01310`.&#x20;
* **Write-out**: Quantize to Q4.16 using §5, then write each (x,y) to **L0\_MEM0** at row-major address with `csel=3’b001` and `cwr=1` on the write **posedge**. &#x20;

### 6.2 Layer 1 — Max-Pooling (2×2 window, stride 2)

* For each **2×2** window over the Layer-0 image, output the **maximum** of the four Q4.16 values. Scan left→right, top→bottom; output size is **32×32**.&#x20;
* **Write-out**: Write each pooled value (unchanged Q4.16) to **L1\_MEM0** at row-major address with `csel=3’b011` and `cwr=1` on the write **posedge**. &#x20;

---

## 7) Legality & Assumptions

* Only **one** start (`busy`↑ after `ready`=1) and **one** end (`busy`↓) per image. While `busy=1`, you may perform unlimited reads/writes to L0/L1.&#x20;
* Respect the **edge timing**: `iaddr` valid until the following **negedge** when `idata` returns; `crd` read on **negedge**; `cwr` write on **posedge**; `csel` selects the target memory for both read/write. &#x20;
* Internal micro-architecture is unconstrained; only the **I/O, timing, addressing, numeric**, and **algorithm** contracts are verified.

---
