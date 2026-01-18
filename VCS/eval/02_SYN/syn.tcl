# Setting environment
sh mkdir -p Netlist
sh mkdir -p Report

define_design_lib work -path ./work

set company {NTUGIEE}
set designer {Student}

set search_path      " /CIC/SynopsysDC/db  $search_path ../ ./"
set target_library   "slow.db "              
set link_library     "* $target_library dw_foundation.sldb"
set symbol_library   "tsmc13.sdb generic.sdb"
set synthetic_library "dw_foundation.sldb"
set default_schematic_options {-size infinite}


# Import Design
set DESIGN "TOP"

set hdlin_translate_off_skip_text "TRUE"
set edifout_netlist_only "TRUE"
set verilogout_no_tri true

set hdlin_enable_presto_for_vhdl "TRUE"
set sh_enable_line_editing true
set sh_line_editing_mode emacs

set_host_options -max_core 16
history keep 100
alias h history


analyze -format sverilog "filelist.v"
elaborate $DESIGN

current_design [get_designs $DESIGN]
link

source -echo -verbose ./syn.sdc
set_fix_hold [get_clocks clk]

# Compile Design
# current_design [get_designs ${DESIGN}]

check_design > Report/check_design.txt
check_timing > Report/check_timing.txt
#set high_fanout_net_threshold 0

uniquify
set_fix_multiple_port_nets -all -buffer_constants [get_designs *]

 compile 

# Report Output
current_design [get_designs ${DESIGN}]
report_timing -delay min -max_paths 10 > "./Report/${DESIGN}_syn.timing_min" 
report_timing -delay max -max_paths 10 > "./Report/${DESIGN}_syn.timing_max"
report_area -hierarchy > "./Report/${DESIGN}_syn.area"

# Output Design
current_design [get_designs ${DESIGN}]

set bus_inference_style {%s[%d]}
set bus_naming_style {%s[%d]}
set hdlout_internal_busses true
change_names -hierarchy -rule verilog
define_name_rules name_rule -allowed {a-z A-Z 0-9 _} -max_length 255 -type cell
define_name_rules name_rule -allowed {a-z A-Z 0-9 _[]} -max_length 255 -type net
define_name_rules name_rule -map {{"\\*cell\\*" "cell"}}
define_name_rules name_rule -case_insensitive
change_names -hierarchy -rules name_rule

#remove_unconnected_ports -blast_buses [get_cells -hierarchical *]
set verilogout_higher_designs_first true
write -format ddc     -hierarchy -output "./Netlist/top_syn.ddc"
write -format verilog -hierarchy -output "./Netlist/top_syn.v"
write_sdf -version 2.1  -context verilog -load_delay cell ./Netlist/top_syn.sdf
write_sdc  ./Netlist/top_syn.sdc -version 1.8

exit
