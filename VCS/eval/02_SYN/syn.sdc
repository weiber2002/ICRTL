############################################
# set Clock
############################################
set cycle 7.0

create_clock -period $cycle -name clk   [get_ports clk]
set_dont_touch_network                  [get_clocks clk]
set_fix_hold                            [get_clocks clk]
set_ideal_network                       [get_ports clk]
set_clock_uncertainty -hold 0.005       [get_clocks clk]
set_clock_uncertainty -setup 0.1        [get_clocks clk]
set_clock_latency 0.1                   [get_clocks clk]

set_false_path                    -from [get_ports rst]


############################################
# input drive and output load
############################################
set_drive 1 [all_inputs]
set_load 0.05 [all_outputs]

############################################
# set i/o delay
############################################
set_input_delay  [expr $cycle * 0.5] -clock clk [remove_from_collection [all_inputs] {clk}]
set_output_delay [expr $cycle * 0.5] -clock clk [all_outputs]
