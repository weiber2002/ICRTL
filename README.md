# ICRTL - Integrated Circuit RTL Design Challenges

This repository contains a collection of industrial-level RTL design challenges selected from the National Taiwan Integrated Circuit Design Contest and handcrafted problems, complete with our reference implementations and specs. Each challenge targets specific algorithms or hardware modules used in industry. We present this collection as the ICRTL benchmark, designed to evaluate PPA optimization on complex problems — a level of difficulty previously unexplored in the application of LLMs to RTL design.

## Challenges Overview

The repository is organized into problem-specific directories (`Q1` through `Q6`), each containing the problem specification, testbench, and reference solution foundation.

| ID | Problem Name | Description |
|----|--------------|-------------|
| **Q1** | **LBP** (Local Binary Pattern) | Design an accelerator to compute Local Binary Patterns for 128x128 grayscale images. |
| **Q2** | **GEMM** (Systolic Array) | Implement a Systolic Array based matrix processing unit. |
| **Q3** | **CONV** (Convolution) | Develop a hardware accelerator for 2D convolution operations on 64x64 images. |
| **Q4** | **HC** (Huffman Coding) | Create a hardware Huffman Coding generator for lossless compression. |
| **Q5** | **JAM** (Job Assignment Machine) | Implement an exhaustive search solver for the Job Assignment problem (finding min cost assignment). |
| **Q6** | **DT** (Distance Transform) | Design an engine to compute the Distance Transform (chessboard distance) for binary images. |

## Directory Structure

```
ICRTL/
├── Q1_LBP/           # Local Binary Pattern Challenge
├── Q2_GEMM/          # Systolic Array Challenge
├── Q3_CONV/          # Convolution Challenge
├── Q4_HC/            # Huffman Coding Challenge
├── Q5_JAM/           # Job Assignment Machine Challenge
├── Q6_DT/            # Distance Transform Challenge
└── VCS/              # Synopsys VCS / Design Compiler / PrimeTime Evaluation Flow
    ├── eval/         # Main evaluation scripts (auto_cycle.py, run_all.py)
    ├── 01_RTL/       # RTL Simulation setup
    ├── 02_SYN/       # Synthesis setup
    ├── 03_GATE/      # Gate-level Simulation setup
    └── 04_POWER/     # Power Analysis setup
```

Each `Q*` folder typically contains:
*   `00_TB/`: Testbench files.
*   `ref_solution/`: Initial RTL templates or reference solutions.
*   `referenced_spec/`: Detailed problem specifications (look for `human.md`).
*   `result/`: Directory for storing simulation/synthesis results.
*   `01_run.sh`: Shell script for open-source flow execution.

## How to Run

There are two primary ways to run the designs: using the provided open-source scripts (Icarus Verilog + Yosys) or the commercial tool flow (VCS). Remind the location of your PDK files.

### Method 1: Open-Source Flow (Icarus Verilog & Yosys)

Each problem folder contains a `01_run.sh` script that runs simulation using `iverilog` and synthesis using `yosys`.

**Prerequisites:**
*   `iverilog` (Icarus Verilog)
*   `yosys` (Yosys Open SYnthesis Suite)

**Steps:**
1.  Navigate to the problem directory (e.g., `Q1_LBP`).
2.  Execute the run script:
    ```bash
    cd Q1_LBP
    bash 01_run.sh
    ```
3.  Check `result/` for logs:
    *   `latency.log`: Simulation output.
    *   `area.log`: Synthesis area report.

### Method 2: VCS / Evaluation Flow

The `VCS` directory contains a Python-based evaluation framework designed for a more comprehensive analysis (RTL sim, Synthesis, Power).

**Prerequisites:**
*   Synopsys VCS
*   Synopsys Design Compiler (DC)
*   Synopsys PrimeTime (PT)
*   Python 3

**Steps:**
1.  Navigate to `VCS/eval`.
2.  Run the main evaluation script:
    ```bash
    cd VCS/eval
    python3 run_all.py
    ```
    *Note: You may need to edit `run_all.py` to select which questions to run by modifying the `QUESTIONS` list.*

