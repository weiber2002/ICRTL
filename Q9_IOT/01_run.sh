#  ######################## RTL Simulation ########################
for ri in $(seq 1 7); do
    echo "=================================================="
    echo "Compiling and running RI = ${ri}"
    echo "=================================================="
    iverilog -g2012 -o a.out ./ref_solution/IOTDF.v ./00_TB/tb.v -DF${ri}
    vvp a.out
done
# ########################  Synthesis ############################
LIB=$HOME/pdk/NanGate45-Synopsys-Enablement/NanGate45/lib/NangateOpenCellLibrary_typical.lib

yosys -p "
  read_verilog -sv ./ref_solution/IOTDF.v ;
  hierarchy -top IOTDF;
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