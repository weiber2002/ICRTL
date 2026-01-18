######################## RTL Simulation ########################
#vcs license 
#vcs -full64 -R +v2k -sverilog ./tb/tb.sv ./tb/Top_control.sv ./ref_solution/initial_island_1.sv -debug_access+all +lint=TFIPC-L | tee rtl_$1.log   
#iverilog 
iverilog -g2012 -o a.out ./tb/tb.sv ./tb/Top_control.sv ./ref_solution/initial_island_1.sv 
vvp a.out | tee ./result/latency.log
########################  Synthesis ############################
yosys -p "
  read_verilog ./ref_solution/initial_island_1.sv;
  hierarchy -top systolic;
  proc; opt; fsm; opt; memory; opt;
  techmap; opt;
  dfflibmap -liberty /home/weiber/project/NanGate45-Synopsys-Enablement/NanGate45/lib/NangateOpenCellLibrary_typical.lib;
  abc       -liberty /home/weiber/project/NanGate45-Synopsys-Enablement/NanGate45/lib/NangateOpenCellLibrary_typical.lib;
  stat      -liberty /home/weiber/project/NanGate45-Synopsys-Enablement/NanGate45/lib/NangateOpenCellLibrary_typical.lib;
  write_verilog -noattr mapped.v
" | tee ./result/area.log
###################### STA ####################################
sta sta.tcl
###################### CLEAN #############################
rm -f mapped.v
rm -f a.out
