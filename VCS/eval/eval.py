#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import subprocess
import re
import os
import csv
from datetime import datetime

ROOT = os.path.dirname(os.path.abspath(__file__))

def run_cmd(cmd, cwd):
    try:
        result = subprocess.check_output(cmd, stderr=subprocess.STDOUT, shell=True, cwd=cwd)
        return result.decode('utf-8', 'ignore')
    except subprocess.CalledProcessError as e:
        return e.output.decode('utf-8', 'ignore')

def grep(pattern, text):
    match = re.search(pattern, text)
    return match.group(1) if match else ''

# 01_RTL
print("Running RTL simulation...")
rtl_log = run_cmd('bash -c "cd 01_RTL && source 01_run"', ROOT)
rtl_sim = 'PASS' if 'All tests PASS!' in rtl_log else 'FAIL'
cycle_period_str = grep(r'Cycle Period\s*=\s*(\d+(\.\d+)?)', rtl_log)
array_compute_cycles_str = grep(r'total time:\s*(\d+)\s*cycles', rtl_log)
evaluation_time_ps_str = grep(r'Time:\s*(\d+)\s*ps', rtl_log)

cycle_period = float(cycle_period_str) if cycle_period_str else ''
array_compute_cycles = int(array_compute_cycles_str) if array_compute_cycles_str else ''
evaluation_time_ps = int(evaluation_time_ps_str) if evaluation_time_ps_str else ''

if not array_compute_cycles:
    print("[WARNING] Cannot find array compute cycles in RTL log.")
if not cycle_period:
    print("[WARNING] Cannot find cycle period in RTL log.")
if not evaluation_time_ps:
    print("[WARNING] Cannot find evaluation time in RTL log.")

evaluation_time_ns = float(evaluation_time_ps) / 1000 if evaluation_time_ps else ''
compute_time_ns = float(array_compute_cycles) * float(cycle_period) if array_compute_cycles and cycle_period else ''

# 02_SYN

print("Running Synthesis... (This may take a while)")
syn_log = run_cmd('bash -c "cd 02_SYN && source 02_run"', ROOT)

print("Extracting synthesis area and violation...")

area_path = os.path.join(ROOT, '02_SYN', 'Report', 'TOP_syn.area')
area_txt = open(area_path).read() if os.path.exists(area_path) else ''

area_seq = grep(r'Non.?combinational area:\s*([\d\.]+)', area_txt)
area_comb = grep(r'Combinational area:\s*([\d\.]+)', area_txt)
area_total = grep(r'Total cell area:\s*([\d\.]+)', area_txt)

timing_path = os.path.join(ROOT, '02_SYN', 'Report', 'TOP_syn.timing_max')
timing_txt = open(timing_path).read() if os.path.exists(timing_path) else ''
violation = 'VIOLATION' if 'VIOLATED' in timing_txt else 'Clean'

# 03_GATE
print("Running Gate-level simulation...")
gate_log = run_cmd('bash -c "cd 03_GATE && source 03_run"', ROOT)
gate_sim = 'PASS' if 'All tests PASS!' in gate_log else 'FAIL'

# 04_POWER
print("Running Power analysis...")
power_log = run_cmd('bash -c "cd 04_POWER && source 04_run "', ROOT)
power_path = os.path.join(ROOT, '04_POWER', 'top.power')
power_txt = open(power_path).read() if os.path.exists(power_path) else ''
power_total = grep(r'Total Power\s*=\s*([\d\.]+)', power_txt)

try:
    ppa_total = float(area_total) * float(evaluation_time_ns) * float(power_total)
except Exception:
    ppa_total = ''
try:
    ppa_compute = float(area_total) * float(compute_time_ns) * float(power_total)
except Exception:
    ppa_compute = ''
    
    
source_file_name = os.environ.get('TARGET_FILENAME', 'N/A')

# write CSV
csv_path = os.path.join(ROOT, 'evaluation.csv')
header = [
    'Timestamp', 
    'Source File', 
    'RTL_sim', 'Cycle Period', 
    'Area_seq(mm^2)', 'Area_comb(mm^2)', 'Area_total(mm^2)', 
    'Evaluation time(ns)', 'Array_compute time(ns)', 
    'GATE_sim', 'Power(mW)', 
    'PPA_total', 'PPA_compute_time'
]
row = [
    datetime.now().strftime('%Y/%m/%d %H:%M'),
    source_file_name, 
    rtl_sim, 
    cycle_period, 
    area_seq, 
    area_comb, 
    area_total, 
    evaluation_time_ns, 
    compute_time_ns, 
    gate_sim, 
    power_total,
    ppa_total,
    ppa_compute
]

write_header = not os.path.isfile(csv_path)
with open(csv_path, 'a') as f:
    writer = csv.writer(f)
    if write_header:
        writer.writerow(header)
    writer.writerow(row)


print("\n[DONE] Results recorded in evaluation.csv")
