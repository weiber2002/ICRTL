# ICRTL - Integrated Circuit RTL Design Challenges

This repository contains a collection of industrial-level RTL design challenges selected from the National Taiwan Integrated Circuit Design Contest and handcrafted problems, complete with our reference implementations and specs. Each challenge targets specific algorithms or hardware modules used in industry. We present this collection as the ICRTL benchmark, designed to evaluate PPA optimization on complex problems — a level of difficulty previously unexplored in the application of LLMs to RTL design.

Building this benchmark from scratch presented significant challenges, particularly in ensuring compatibility with open-source tools like Yosys without relying on proprietary IPs. We successfully overcame these obstacles thanks to the incredible efforts of our developers.

## Challenges Overview

The repository is organized into problem-specific directories (`Q1` through `Q6`), each containing the problem specification, testbench, and reference solution foundation.

| ID | Problem Name | Description |
|----|--------------|-------------|
| **Q1** | **LBP** (Local Binary Pattern) | Design an accelerator to compute Local Binary Patterns for 128x128 grayscale images. |
| **Q2** | **CONV** (Convolution) | Develop a hardware accelerator for 2D convolution operations on 64x64 images. |
| **Q3** | **HC** (Huffman Coding) | Create a hardware Huffman Coding generator for lossless compression. |
| **Q4** | **JAM** (Job Assignment Machine) | Implement an exhaustive search solver for the Job Assignment problem (finding min cost assignment). |
| **Q5** | **DT** (Distance Transform) | Design an engine to compute the Distance Transform (chessboard distance) for binary images. |
| **Q6** | **REF** (Optical Refraction) | Calculate the final position of vertically incident light after refracting through a curved glass surface onto its bottom plane. |  
| **Q7** | **GEO** (Geofence) | Build a Geofence System | 
| **Q8** | **IOT** (IoT Data Filtering) | This circuit performs real-time analysis and processing of massive IoT data collected from smart devices or sensors, according to a specified application function. |
| **Q9** | **SECC** (Set Element Coverage Counter) | Count the total number of covered vertices using set operations on multiple overlapping circles. |
| **Q10** | **GEMM** (Systolic Array) | Implement a Systolic Array based matrix processing unit. |

## Directory Structure

```
ICRTL/
├── Q1_LBP/           # Local Binary Pattern Challenge
├── Q2_CONV/          # Convolution Challenge
├── Q3_HC/            # Huffman Coding Challenge
├── Q4_JAM/           # Job Assignment Machine Challenge
├── Q5_DT/            # Distance Transform Challenge
├── Q6_REF/           # Optical Refraction Challenge
├── Q7_GEO/           # Geofence Challenge
├── Q8_IOT/           # IoT Data Filtering Challenge
├── Q9_SECC/          # Set Element Coverage Counter Challenge
├── Q10_GEMM/         # Systolic Array Challenge
├── PROMPT_Generate.  # Referenced Prompts for generating SPEC, Code Generation, and Code Optimization
└── VCS/              # Synopsys VCS / Design Compiler / PrimeTime Evaluation Flow
    ├── eval/         # Main evaluation scripts (auto_cycle.py, run_all.py)
    ├── 01_RTL/       # RTL Simulation setup
        ├── 01_run
        ├── rtl_01.f
    ├── 02_SYN/       # Synthesis setup
        ├── 02_run
        ├── syn.sdc
        ├── syn.tcl    # Remind for the location of PDK or Foundary 
        ├── filelist.v
    ├── 03_GATE/      # Gate-level Simulation setup
        ├── 03_run
        ├── gate_sim.f
    └── 04_POWER/     # Power Analysis setup
        ├── 04_run
        ├── pt_script.tcl  # Remind for the location of PDK or Foundary 
```

Each `Q*` folder typically contains:
*   `00_TB/`: Testbench files and golden data.
*   `ref_solution/`: Reference solutions (can be executed on Yosys - no DesignWare).
*   `SPEC.md`: LLM-readable SPEC extracted from Original_SPEC, including a description of the current implementation.
*   `Original_SPEC.pdf`: The original version of the SPEC written in Chinese.
*   `01_run.sh`: Shell script for open-source flow execution.

## Quick Start: Installing Yosys (OSS CAD Suite)

The `yosys` package available via some Linux distro package managers (e.g. apt) can be quite old (e.g. `0.9`), which lacks full SystemVerilog support (`-sv` parsing of constructs like `.*` implicit port connections) and is significantly slower on large designs. We recommend installing the latest nightly build via [OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build).

**Steps:**

1.  Download and extract the latest `linux-x64` release (release filenames are date-stamped, so grab the actual asset name from the [releases page](https://github.com/YosysHQ/oss-cad-suite-build/releases/latest) rather than guessing it):
    ```bash
    cd ~
    URL=$(curl -s https://api.github.com/repos/YosysHQ/oss-cad-suite-build/releases/latest \
      | grep "browser_download_url.*linux-x64" | cut -d '"' -f 4)
    wget -O oss-cad-suite.tgz "$URL"
    tar xzf oss-cad-suite.tgz
    ```

2.  Add it to your `PATH` (prepend so it takes priority over any older system/conda `yosys`):
    ```bash
    echo 'export PATH="$HOME/oss-cad-suite/bin:$PATH"' >> ~/.bashrc
    source ~/.bashrc
    ```

3.  Verify the install:
    ```bash
    yosys -V
    which yosys   # should point to ~/oss-cad-suite/bin/yosys
    ```

> **Note:** If you use a conda environment, double-check `which yosys` afterwards — conda environments can prepend their own `bin/` to `PATH` and shadow the OSS CAD Suite build.

## Quick Start: Installing the PDK (NanGate45)

The synthesis scripts (`02_run` / `01_run.sh`) reference a `.lib` file from the NanGate45 Synopsys-enablement PDK. **Clone it to a fixed path at `~/pdk/`** so the paths in this repo's scripts work without modification:

```bash
mkdir -p ~/pdk
cd ~/pdk
git clone https://github.com/ABKGroup/NanGate45-Synopsys-Enablement.git
```

This results in the following path, which the scripts expect:

```
~/pdk/NanGate45-Synopsys-Enablement/NanGate45/lib/NangateOpenCellLibrary_typical.lib
```

Verify the file exists:
```bash
ls -la ~/pdk/NanGate45-Synopsys-Enablement/NanGate45/lib/NangateOpenCellLibrary_typical.lib
```

> **No internet access on the target machine?** Clone the repo on a machine that has internet access, `tar czf` it, `scp` it over, then `tar xzf` it into `~/pdk/` on the target machine.

> **Using a different path?** If you'd rather keep the PDK somewhere else, update the `LIB` variable at the top of each problem's synthesis script (e.g. `01_run.sh`) accordingly.

## How to Run

There are two primary ways to run the designs: using the provided open-source scripts (Icarus Verilog + Yosys) or the commercial tool flow (VCS). Remind the location of your PDK files.

### Method 1: Open-Source Flow (Icarus Verilog & Yosys)

Each problem folder contains a `01_run.sh` script that runs simulation using `iverilog` and synthesis using `yosys`.

**Prerequisites:**
*   `iverilog` (Icarus Verilog)
*   `yosys` (Yosys Open SYnthesis Suite) — see [Quick Start: Installing Yosys](#quick-start-installing-yosys-oss-cad-suite) above for installing an up-to-date build
*   NanGate45 PDK installed at `~/pdk/` — see [Quick Start: Installing the PDK](#quick-start-installing-the-pdk-nangate45) above

**Steps:**
1.  Navigate to the problem directory (e.g., `Q1_LBP`).
2.  Execute the run script:
    ```bash
    cd Q1_LBP
    bash 01_run.sh
    ```

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