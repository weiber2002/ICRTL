read_liberty /home/weiber/project/NanGate45-Synopsys-Enablement/NanGate45/lib/NangateOpenCellLibrary_typical.lib
read_verilog mapped.v
link_design systolic

create_clock -name clk -period 10.0 [get_ports clk]
set_input_delay  0.1 -clock clk [all_inputs -no_clocks]
set_output_delay 0.1 -clock clk [all_outputs]
set_false_path -from [get_ports rst] -to [all_registers]

report_checks -path_delay max -digits 3 -group_path_count 1 -format full > ./result/setup.log
report_power -digits 3 > ./result/power.log

exit