#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import glob
import re
import subprocess
import time

QUESTIONS = ["Q1_LBP", "Q2_GEMM", "Q3_CONV", "Q4_JAM", "Q5_HC", "Q6_DT"]
PT_SCRIPT_PATH = "./04_POWER/pt_script.tcl"
AUTO_CYCLE_CMD = "python3 auto_cycle.py"

def run_shell(cmd):
    try:
        subprocess.run(cmd, shell=True, check=True)
    except subprocess.CalledProcessError:
        print(f"[ERROR] Command failed: {cmd}")
        pass

def modify_q2_tcl(enable_control):
    if not os.path.exists(PT_SCRIPT_PATH):
        print(f"[Error] Cannot find {PT_SCRIPT_PATH}")
        return

    with open(PT_SCRIPT_PATH, 'r') as f:
        content = f.read()

    pattern_top = r'(^\s*|^\s*#\s*)(read_fsdb\s+.*strip_path\s+test/TOP\s+.*)'
    pattern_control = r'(^\s*|^\s*#\s*)(read_fsdb\s+.*strip_path\s+test/TOP_Control/TOP\s+.*)'

    def replace_func(match, should_comment):
        cmd = match.group(2)
        return f"# {cmd}" if should_comment else cmd

    if enable_control:
        content = re.sub(pattern_top, lambda m: replace_func(m, True), content, flags=re.MULTILINE)
        content = re.sub(pattern_control, lambda m: replace_func(m, False), content, flags=re.MULTILINE)
    else:
        content = re.sub(pattern_top, lambda m: replace_func(m, False), content, flags=re.MULTILINE)
        content = re.sub(pattern_control, lambda m: replace_func(m, True), content, flags=re.MULTILINE)

    with open(PT_SCRIPT_PATH, 'w') as f:
        f.write(content)

def find_verilog_files(src_dir):
    files = []
    search_paths = [
        os.path.join(src_dir, "*.sv"),
        os.path.join(src_dir, "*.v"),
        os.path.join(src_dir, "01_RTL", "*.sv"),
        os.path.join(src_dir, "01_RTL", "*.v")
    ]

    for pattern in search_paths:
        files.extend(glob.glob(pattern))

    valid_files = []
    seen_names = set()

    for f in files:
        fname = os.path.basename(f)
        f_lower = fname.lower()

        if "test" in f_lower or "_tb" in f_lower or "pattern" in f_lower:
            continue
        
        if fname in seen_names:
            continue
            
        seen_names.add(fname)
        valid_files.append(f)

    valid_files.sort()
    return valid_files

def main():
    print("=== Starting Batch Evaluation (Debug Mode) ===")

    for q_name in QUESTIONS:
        print(f"\n{'='*40}")
        print(f" Processing Question: {q_name}")
        print(f"{'='*40}")

        src_dir = os.path.join("..", q_name)
        
        run_shell("rm -rf 00_TB")
        src_tb = os.path.join(src_dir, "00_TB")
        
        if os.path.exists(src_tb):
            print(f" -> Copying 00_TB from {src_tb} ...")
            run_shell(f"cp -rf {src_tb} .")
        else:
            print(f" [Error] 00_TB not found in {src_dir}")
            continue

        if q_name == "Q2_GEMM":
            modify_q2_tcl(enable_control=True)

        sv_files = find_verilog_files(src_dir)
        
        if not sv_files:
            print(f" [Warning] No valid design files (.sv/.v) found in {src_dir} or {src_dir}/01_RTL")
            print(f"           (Checked for *.sv, *.v, excluding 'test', 'tb')")
        else:
            print(f" -> Found Design Files: {[os.path.basename(f) for f in sv_files]}")

        for sv_file in sv_files:
            base_name = os.path.basename(sv_file)
            print(f"\n   --- Evaluation Target: {base_name} ---")

            if not os.path.exists("01_RTL"):
                os.makedirs("01_RTL")
            
            target_path = os.path.join("01_RTL", "initial.sv")

            run_shell(f"cp -f {sv_file} {target_path}")
            
            my_env = os.environ.copy()

            my_env["TARGET_FILENAME"] = f"{q_name}_{base_name}"

            print(f"   -> Running {AUTO_CYCLE_CMD}...")
            try:
                subprocess.run(AUTO_CYCLE_CMD, shell=True, env=my_env, check=True)
            except subprocess.CalledProcessError:
                print(f"   [Error] auto_cycle.py failed for {base_name}")

        if q_name == "Q2_GEMM":
            modify_q2_tcl(enable_control=False)

        time.sleep(1)

    print("\n=== All Tasks Completed ===")

if __name__ == "__main__":

    main()
