
set company "CIC"
set designer "Student"
set search_path       "./ /CIC/SynopsysDC/db  $search_path"
set target_library    "slow.db"
set link_library      "* $target_library"

set hdlin_translate_off_skip_text "TRUE"
set edifout_netlist_only "TRUE"
set verilogout_no_tri true

set hdlin_enable_presto_for_vhdl "TRUE"
set sh_enable_line_editing true
set sh_line_editing_mode emacs
history keep 100
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


read_fsdb -time {0 10000}  -strip_path test/TOP  ../03_GATE/top.fsdb
# read_fsdb -time {0 10000}  -strip_path test/TOP_Control/TOP  ../03_GATE/top.fsdb
update_power
report_power 
report_power > top.power



exit



