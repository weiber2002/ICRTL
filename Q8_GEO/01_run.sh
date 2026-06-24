######################## RTL Simulation ########################
#iverilog 
iverilog -g2012 -o a.out ./ref_solution/initial.sv ./ref_solution/sqrt.v ./00_TB/tb.sv 
vvp a.out

########################  Synthesis ############################
LIB=$HOME/pdk/NanGate45-Synopsys-Enablement/NanGate45/lib/NangateOpenCellLibrary_typical.lib

yosys -p "
  read_verilog -sv ./ref_solution/sqrt.v ./ref_solution/initial.sv;
  hierarchy -top TOP;
  proc; opt; fsm; opt; memory; opt;
  techmap; opt;
  dfflibmap -liberty $LIB;
  abc       -fast -liberty $LIB;
  stat      -liberty $LIB;
  write_verilog -noattr mapped.v
" | tee ./result/area.log

###################### CLEAN #############################
rm -f mapped.v
rm -f a.out