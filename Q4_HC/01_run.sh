######################## RTL Simulation ########################
#iverilog 
iverilog -g2012 -o a.out ./00_TB/test.sv ./ref_solution/initial.sv 
vvp a.out | tee ./result/latency.log
########################  Synthesis ############################
yosys -p "
  read_verilog -sv ./ref_solution/initial.sv;
  hierarchy -top TOP;
  proc; opt; fsm; opt; memory; opt;
  techmap; opt;
  dfflibmap -liberty /home/weiber/pdk/NanGate45-Synopsys-Enablement/NanGate45/lib/NangateOpenCellLibrary_typical.lib;
  abc       -liberty /home/weiber/pdk/NanGate45-Synopsys-Enablement/NanGate45/lib/NangateOpenCellLibrary_typical.lib;
  stat      -liberty /home/weiber/pdk/NanGate45-Synopsys-Enablement/NanGate45/lib/NangateOpenCellLibrary_typical.lib;
  write_verilog -noattr mapped.v
" | tee ./result/area.log
###################### CLEAN #############################
rm -f mapped.v
rm -f a.out
