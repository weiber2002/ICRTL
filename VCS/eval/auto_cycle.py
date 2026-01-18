#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import re
import subprocess
import time

# ================= 設定區 =================
# 範圍設定 (單位: ns)
START_CYCLE = 3.0
END_CYCLE   = 7.0
STEP        = 1.0

# 檔案路徑 (請確認你的 Testbench 到底是在 00_TB 還是 01_RTL)
SDC_PATH = '02_SYN/syn.sdc'
TB_PATH  = '00_TB/test.sv'   # 或是 '01_RTL/test.sv'

# 執行評估的指令
EVAL_CMD = 'python3 eval.py'
# ===========================================

def modify_file(file_path, pattern, new_val):
    """
    讀取檔案 -> 用 Regex 替換數值 -> 寫回檔案
    """
    if not os.path.exists(file_path):
        print(f"[ERROR] File not found: {file_path}")
        return False

    with open(file_path, 'r') as f:
        content = f.read()

    # 將數值格式化為字串 (例如 3.0)
    val_str = f"{new_val:.1f}"

    # Regex 替換: \g<1> 保留前面的關鍵字，只換後面的數字
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
    # 產生要測試的週期列表 (3.0, 4.0, ..., 8.0)
    # 使用整數迴圈避免浮點數誤差，再除以 10 或乘倍率
    # 這裡簡單實作：
    current_cycle = START_CYCLE
    
    print(f"=== Starting Auto Sweep: {START_CYCLE}ns to {END_CYCLE}ns (Step: {STEP}ns) ===\n")

    # 定義 Regex
    # SDC 範例: set cycle 10.0
    sdc_pattern = r'(set\s+cycle\s+)([\d\.]+)'
    # TB 範例: `define CYCLE 10.0
    tb_pattern  = r'(`define\s+CYCLE\s+)([\d\.]+)'

    while current_cycle <= END_CYCLE + 0.001: # +0.001 是為了防止浮點數尾數誤差
        print(f"--- Iteration: Target Cycle = {current_cycle:.1f} ns ---")

        # 1. 修改檔案
        mod_sdc = modify_file(SDC_PATH, sdc_pattern, current_cycle)
        mod_tb  = modify_file(TB_PATH,  tb_pattern,  current_cycle)

        if not mod_sdc or not mod_tb:
            print("[ERROR] Failed to update files. Stopping.")
            break

        # 2. 執行 eval.py
        print(f"    [RUN] Running {EVAL_CMD}...")
        try:
            # 使用 subprocess 呼叫 eval.py
            # stdout=None 表示讓 eval.py 的輸出直接印在螢幕上
            subprocess.check_call(EVAL_CMD, shell=True)
        except subprocess.CalledProcessError:
            print(f"    [FAIL] {EVAL_CMD} encountered an error (check logs).")
        
        print(f"    [DONE] Finished {current_cycle:.1f} ns.\n")
        
        # 3. 前往一下個週期
        current_cycle += STEP
        time.sleep(1) # 稍微暫停一下讓 I/O 寫入確保完成

    print("=== All iterations completed. Check evaluation.csv for results. ===")

if __name__ == "__main__":
    main()