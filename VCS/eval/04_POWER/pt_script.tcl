set company {NTUGIEE}
set designer {Student}

set search_path      ". /home/raid7_2/course/cvsd/CBDK_IC_Contest/CIC/SynopsysDC/db  $search_path ../ ./"
set target_library [list "typical.db" "slow.db" "fast.db"]
set link_library     "* $target_library dw_foundation.sldb"
set symbol_library [list "generic.sdb"]
set synthetic_library "dw_foundation.sldb"
set default_schematic_options {-size infinite}

set hdlin_translate_off_skip_text "TRUE"
set edifout_netlist_only "TRUE"
set verilogout_no_tri true
set plot_command {lpr -Plw}
set hdlin_auto_save_templates "TRUE"
set compile_fix_multiple_port_nets "TRUE"

alias h history



#PrimeTime Script
set power_enable_analysis TRUE
set power_analysis_mode time_based

read_file -format verilog  ../02_SYN/Netlist/top_syn.v
current_design TOP
link

read_sdf -load_delay net ../02_SYN/Netlist/top_syn.sdf


## Measure  power
#report_switching_activity -list_not_annotated -show_pin


read_vcd -strip_path test/TOP  ../03_GATE/top.vcd
# read_fsdb -time {0 10000}  -strip_path test/TOP_Control/TOP  ../03_GATE/top.fsdb
update_power
report_power 
report_power > top.power



exit



