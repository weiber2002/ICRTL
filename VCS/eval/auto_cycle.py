#!/usr/bin/env python2
# -*- coding: utf-8 -*-

from __future__ import print_function

import os
import re
import subprocess
import time

START_CYCLE = 4.0
END_CYCLE   = 10.0
STEP        = 3.0

SDC_PATH = '02_SYN/syn.sdc'
TB_PATH  = '00_TB/test.sv'

EVAL_CMD = 'python eval.py'
# ===========================================

def modify_file(file_path, pattern, new_val):

    if not os.path.exists(file_path):
        print("[ERROR] File not found: {0}".format(file_path))
        return False

    f = open(file_path, 'r')
    content = f.read()
    f.close()

    val_str = "{0:.1f}".format(new_val)

    new_content, count = re.subn(pattern, r'\g<1>' + val_str, content)

    if count > 0:
        f = open(file_path, 'w')
        f.write(new_content)
        f.close()
        print("    [UPDATE] {0} -> set to {1}".format(file_path, val_str))
        return True
    else:
        print("    [WARNING] Pattern not found in {0}. (Pattern: {1})".format(file_path, pattern))
        return False

def main():

    current_cycle = START_CYCLE

    print("=== Starting Auto Sweep: {0}ns to {1}ns (Step: {2}ns) ===\n".format(
        START_CYCLE, END_CYCLE, STEP))

    sdc_pattern = r'(set\s+cycle\s+)([\d\.]+)'

    tb_pattern  = r'(`define\s+CYCLE\s+)([\d\.]+)'

    while current_cycle <= END_CYCLE + 0.001:
        print("--- Iteration: Target Cycle = {0:.1f} ns ---".format(current_cycle))

        mod_sdc = modify_file(SDC_PATH, sdc_pattern, current_cycle)
        mod_tb  = modify_file(TB_PATH,  tb_pattern,  current_cycle)

        if not mod_sdc or not mod_tb:
            print("[ERROR] Failed to update files. Stopping.")
            break

        print("    [RUN] Running {0}...".format(EVAL_CMD))
        try:
            subprocess.check_call(EVAL_CMD, shell=True)
        except subprocess.CalledProcessError:
            print("    [FAIL] {0} encountered an error (check logs).".format(EVAL_CMD))

        print("    [DONE] Finished {0:.1f} ns.\n".format(current_cycle))

        current_cycle += STEP
        time.sleep(1)

    print("=== All iterations completed. Check evaluation.csv for results. ===")

if __name__ == "__main__":

    main()
