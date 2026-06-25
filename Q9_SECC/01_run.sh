#  ######################## RTL Simulation ########################
iverilog -g2012 -o a.out ./ref_solution/initial.sv ./00_TB/test.sv
vvp a.out

# ########################  Synthesis ############################
LIB=$HOME/pdk/NanGate45-Synopsys-Enablement/NanGate45/lib/NangateOpenCellLibrary_typical.lib

yosys -p "
  read_verilog -sv ./ref_solution/initial.sv ;
  hierarchy -top TOP;
  proc; opt; fsm; opt; memory; opt;
  techmap; opt;
  dfflibmap -liberty $LIB;
  abc       -liberty $LIB;
  stat      -liberty $LIB;
  write_verilog -noattr mapped.v
" | tee ./result/area.log

###################### CLEAN #############################
rm -f mapped.v
rm -f a.out
