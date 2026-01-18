#!/usr/bin/env python3
"""
Result Parser for VLSI Design Flow
解析 area.log, setup.log, latency.log, power.log 並輸出 JSON 結果
"""

import re
import json
import os
from pathlib import Path

class ResultParser:
    def __init__(self, result_dir="./result"):
        self.result_dir = Path(result_dir)
        self.results = {}
    
    def parse_area_log(self):
        area_file = self.result_dir / "area.log"
        if not area_file.exists():
            print(f"Warning: {area_file} not found")
            return
        
        try:
            with open(area_file, 'r') as f:
                content = f.read()
            
            # 解析所有模組的面積資訊
            modules = {}
            
            # 更準確的正則表達式匹配您的格式
            # 格式1: Chip area for module '\PE': 2725.170000
            # 格式2: Chip area for top module '\systolic': 50082.214000
            module_patterns = [
                r"Chip area for module '\\([^']+)':\s*([0-9.]+)\s*\n\s*of which used for sequential elements:\s*([0-9.]+)",
                r"Chip area for top module '\\([^']+)':\s*([0-9.]+)\s*\n\s*of which used for sequential elements:\s*([0-9.]+)"
            ]
            
            for pattern in module_patterns:
                matches = re.finditer(pattern, content, re.MULTILINE)
                
                for match in matches:
                    module_name = match.group(1)
                    chip_area = float(match.group(2))
                    sequential_area = float(match.group(3))
                    
                    modules[module_name] = {
                        "chip_area": chip_area,
                        "sequential_area": sequential_area,
                        "sequential_percentage": round((sequential_area / chip_area) * 100, 2) if chip_area > 0 else None
                    }
            
            # 如果沒有找到模組，嘗試更寬鬆的匹配
            if not modules:
                # 備用匹配，不要求 sequential 資訊
                backup_pattern = r"Chip area for (?:top )?module '\\([^']+)':\s*([0-9.]+)"
                matches = re.finditer(backup_pattern, content, re.MULTILINE)
                
                for match in matches:
                    module_name = match.group(1)
                    chip_area = float(match.group(2))
                    
                    modules[module_name] = {
                        "chip_area": chip_area,
                        "sequential_area": None,
                        "sequential_percentage": None
                    }
            
            # 找出 top module
            top_module = None
            if modules:
                # 優先尋找包含 "systolic" 的模組
                for module_name in modules.keys():
                    if module_name.lower() in ["systolic"]:
                        top_module = module_name
                        break
                
                # 如果沒找到，尋找其他可能的 top module 名稱
                if not top_module:
                    for module_name in modules.keys():
                        if any(keyword in module_name.lower() for keyword in ["top", "design", "main"]):
                            top_module = module_name
                            break
                
                # 最後取面積最大的
                if not top_module:
                    top_module = max(modules.keys(), key=lambda x: modules[x]["chip_area"])
            
            # 計算統計資訊
            total_chip_area = sum(module["chip_area"] for module in modules.values())
            total_sequential_area = sum(module["sequential_area"] or 0 for module in modules.values())
            
            self.results["area"] = {
                "top_module": {
                    "name": top_module,
                    "chip_area": modules[top_module]["chip_area"] if top_module else None,
                    "sequential_area": modules[top_module]["sequential_area"] if top_module else None,
                    "sequential_percentage": modules[top_module]["sequential_percentage"] if top_module else None
                },
                "all_modules": modules,
                "summary": {
                    "total_modules": len(modules),
                    "total_chip_area": total_chip_area,
                    "total_sequential_area": total_sequential_area,
                    "overall_sequential_percentage": round((total_sequential_area / total_chip_area) * 100, 2) if total_chip_area > 0 else None
                }
            }
            
        except Exception as e:
            print(f"Error parsing area.log: {e}")
            # 提供備用的空結果
            self.results["area"] = {
                "top_module": {"name": None, "chip_area": None, "sequential_area": None, "sequential_percentage": None},
                "all_modules": {},
                "summary": {"total_modules": 0, "total_chip_area": 0, "total_sequential_area": 0, "overall_sequential_percentage": None}
            }
    
    def parse_setup_log(self):
        setup_file = self.result_dir / "setup.log"
        if not setup_file.exists():
            print(f"Warning: {setup_file} not found")
            return
        
        try:
            with open(setup_file, 'r') as f:
                lines = f.readlines()
            
            slack_value = None
            slack_status = None
            
            for line in reversed(lines):
                slack_pattern = r"(\d+\.?\d*)\s+slack\s*\((MET|VIOLATED)\)"
                match = re.search(slack_pattern, line)
                if match:
                    slack_value = float(match.group(1))
                    slack_status = match.group(2)
                    break
            
            self.results["timing"] = {
                "slack": slack_value,
                "status": slack_status
            }
            
        except Exception as e:
            print(f"Error parsing setup.log: {e}")
    
    def parse_latency_log(self):
        latency_file = self.result_dir / "latency.log"
        if not latency_file.exists():
            print(f"Warning: {latency_file} not found")
            return
        
        try:
            with open(latency_file, 'r') as f:
                content = f.read()
            
            cycles = None
            error_rate = None
            total_error = None
            status = None

            # 匹配 cycles 資訊
            cycles_pattern = r"total time:\s*(\d+)\s*cycles"
            cycles_match = re.search(cycles_pattern, content)
            if cycles_match:
                cycles = int(cycles_match.group(1))
            
            # 匹配 Verilog $display 格式的錯誤資訊
            # 格式: Total Error: 1083 (10.59% of total pixels)
            verilog_error_pattern = r"Total Error:\s*(\d+)\s*\(([0-9.]+)%\s*of total pixels\)"
            verilog_match = re.search(verilog_error_pattern, content, re.IGNORECASE)
            
            if verilog_match:
                total_error = int(verilog_match.group(1))
                error_rate = float(verilog_match.group(2))
            else:
                # 備用匹配：一般的錯誤率格式
                error_pattern = r"error\s*(?:rate)?[:\s]*(\d+\.?\d*)%?"
                error_match = re.search(error_pattern, content, re.IGNORECASE)
                if error_match:
                    error_rate = float(error_match.group(1))
            
            # 檢查狀態
            if "All tests PASS" in content:
                status = "PASS"
            elif "FAIL" in content or (error_rate is not None and error_rate > 0):
                status = "FAIL"
            elif error_rate is not None and error_rate == 0:
                status = "PASS"
            
            self.results["performance"] = {
                "cycles": cycles,
                "error_rate": error_rate,
                "total_error": total_error,
                "status": status
            }
            
        except Exception as e:
            print(f"Error parsing latency.log: {e}")
    
    def parse_power_log(self):
        power_file = self.result_dir / "power.log"
        if not power_file.exists():
            print(f"Warning: {power_file} not found")
            return
        
        try:
            with open(power_file, 'r') as f:
                content = f.read()

            # format: Total    5.778e-05  4.720e-06  1.656e-05  7.905e-05 100.0%
            total_pattern = r"Total\s+([0-9.e-]+)\s+([0-9.e-]+)\s+[0-9.e-]+\s+([0-9.e-]+)"
            match = re.search(total_pattern, content)
            
            if match:
                internal_power = float(match.group(1))
                switching_power = float(match.group(2))
                total_power = float(match.group(3))
            else:
                internal_power = switching_power = total_power = None
            
            self.results["power"] = {
                "internal_power": internal_power,
                "switching_power": switching_power,
                "total_power": total_power,
                "unit": "Watts"
            }
            
        except Exception as e:
            print(f"Error parsing power.log: {e}")
    
    def parse_all(self):
        print(f"Parsing results from {self.result_dir}...")
        
        self.parse_area_log()
        self.parse_setup_log()
        self.parse_latency_log()
        self.parse_power_log()
        
        return self.results
    
    def save_to_json(self, output_file="results.json"):
        try:
            with open(output_file, 'w', encoding='utf-8') as f:
                json.dump(self.results, f, indent=2, ensure_ascii=False)
            print(f"Results saved to {output_file}")
        except Exception as e:
            print(f"Error saving to JSON: {e}")
    
    def print_summary(self):
        print("\n" + "="*50)
        print("VLSI Design Flow Results Summary")
        print("="*50)
        
        # Area 結果
        if "area" in self.results:
            area = self.results["area"]
            print(f"📐 Area Analysis:")
            
            # Top module 資訊
            if "top_module" in area and area["top_module"]["name"]:
                top = area["top_module"]
                print(f"   Top Module ({top['name']}):")
                print(f"     Chip Area: {top.get('chip_area', 'N/A')}")
                seq_info = f"{top.get('sequential_area', 'N/A')}"
                if top.get('sequential_percentage'):
                    seq_info += f" ({top.get('sequential_percentage', 'N/A')}%)"
                print(f"     Sequential Area: {seq_info}")
            
            # 所有模組詳細資訊
            if "all_modules" in area and len(area["all_modules"]) > 1:
                print(f"   All Modules:")
                for module_name, module_data in area["all_modules"].items():
                    seq_info = f"{module_data.get('sequential_area', 'N/A')}"
                    if module_data.get('sequential_percentage'):
                        seq_info += f" ({module_data.get('sequential_percentage', 'N/A')}%)"
                    print(f"     {module_name}: {module_data.get('chip_area', 'N/A')} (seq: {seq_info})")
            
            # 總體統計
            if "summary" in area and area["summary"]["total_modules"] > 0:
                summary = area["summary"]
                print(f"   Summary:")
                print(f"     Total Modules: {summary.get('total_modules', 'N/A')}")
                if summary.get('overall_sequential_percentage'):
                    print(f"     Overall Sequential %: {summary.get('overall_sequential_percentage', 'N/A')}%")
        
        # Timing 結果
        if "timing" in self.results:
            timing = self.results["timing"]
            print(f"⏱️  Timing Analysis:")
            print(f"   Slack: {timing.get('slack', 'N/A')} ({timing.get('status', 'N/A')})")
        
        # Performance 結果
        if "performance" in self.results:
            perf = self.results["performance"]
            print(f"🚀 Performance Analysis:")
            print(f"   Cycles: {perf.get('cycles', 'N/A')}")
            print(f"   Error Rate: {perf.get('error_rate', 'N/A')}%")
            print(f"   Status: {perf.get('status', 'N/A')}")
        
        # Power 結果
        if "power" in self.results:
            power = self.results["power"]
            print(f"⚡ Power Analysis:")
            print(f"   Internal Power: {power.get('internal_power', 'N/A')} W")
            print(f"   Switching Power: {power.get('switching_power', 'N/A')} W")
            print(f"   Total Power: {power.get('total_power', 'N/A')} W")


def main():
    import argparse
    
    parser = argparse.ArgumentParser(description='Parse VLSI design flow results')
    parser.add_argument('--result-dir', '-d', default='./result', 
                       help='Result directory path (default: ./result)')
    parser.add_argument('--output', '-o', default='results.json',
                       help='Output JSON file (default: results.json)')
    parser.add_argument('--quiet', '-q', action='store_true',
                       help='Quiet mode, only output JSON')
    
    args = parser.parse_args()
    
    parser_instance = ResultParser(args.result_dir)
    
    results = parser_instance.parse_all()
    
    parser_instance.save_to_json(args.output)
    
    if not args.quiet:
        parser_instance.print_summary()


if __name__ == "__main__":
    main()