#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import re
import subprocess
import time

START_CYCLE = 3.0
END_CYCLE   = 7.0
STEP        = 1.0

SDC_PATH = '02_SYN/syn.sdc'
TB_PATH  = '00_TB/test.sv' 

EVAL_CMD = 'python3 eval.py'
# ===========================================

def modify_file(file_path, pattern, new_val):

    if not os.path.exists(file_path):
        print(f"[ERROR] File not found: {file_path}")
        return False

    with open(file_path, 'r') as f:
        content = f.read()

    val_str = f"{new_val:.1f}"

    new_content, count = re.subn(pattern, fr'\g<1>{val_str}', content)

    if count > 0:
        with open(file_path, 'w') as f:
            f.write(new_content)
        print(f"    [UPDATE] {file_path} -> set to {val_str}")
        return True
    else:
        print(f"    [WARNING] Pattern not found in {file_path}. (Pattern: {pattern})")
        return False

def main():

    current_cycle = START_CYCLE
    
    print(f"=== Starting Auto Sweep: {START_CYCLE}ns to {END_CYCLE}ns (Step: {STEP}ns) ===\n")


    sdc_pattern = r'(set\s+cycle\s+)([\d\.]+)'

    tb_pattern  = r'(`define\s+CYCLE\s+)([\d\.]+)'

    while current_cycle <= END_CYCLE + 0.001:
        print(f"--- Iteration: Target Cycle = {current_cycle:.1f} ns ---")

        mod_sdc = modify_file(SDC_PATH, sdc_pattern, current_cycle)
        mod_tb  = modify_file(TB_PATH,  tb_pattern,  current_cycle)

        if not mod_sdc or not mod_tb:
            print("[ERROR] Failed to update files. Stopping.")
            break

        print(f"    [RUN] Running {EVAL_CMD}...")
        try:

            subprocess.check_call(EVAL_CMD, shell=True)
        except subprocess.CalledProcessError:
            print(f"    [FAIL] {EVAL_CMD} encountered an error (check logs).")
        
        print(f"    [DONE] Finished {current_cycle:.1f} ns.\n")
        
        current_cycle += STEP
        time.sleep(1)

    print("=== All iterations completed. Check evaluation.csv for results. ===")

if __name__ == "__main__":

    main()
