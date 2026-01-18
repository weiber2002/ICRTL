
`timescale 1ns/10ps
`define CYCLE 10               // clk period. DO NOT modify period
`define tb1

`ifdef tb1
  `define PAT "./00_TB/pattern1.dat"
  `define EXP "./00_TB/golden1.dat"
`endif

`ifdef tb2
  `define PAT "./00_TB/pattern2.dat"
  `define EXP "./00_TB/golden2.dat"
`endif

`ifdef tb3
  `define PAT "./00_TB/pattern3.dat"
  `define EXP "./00_TB/golden3.dat"
`endif


module test;
reg clk;
reg rst;
reg [7:0] pat_mem [0:99];
reg [7:0] exp_mem [0:17];
reg gray_valid;
reg [7:0] gray_data;
integer i;


wire CNT_valid;
wire [7:0] CNT [1:6];
wire code_valid;
wire [7:0] HC [1:6];
wire [7:0] M [1:6]; 

reg flag1; // CNT PASS or not
reg flag2; // HC PASS or not
reg flag3; // M PASS or not
reg done1;

wire [47:0] CNT_G, CNT_EXP;
wire [47:0] HC_G, HC_EXP;
wire [47:0] M_G, M_EXP;

// initial begin
// $fsdbDumpfile("top.fsdb");
// $fsdbDumpvars(0, test);
// end

localparam SDFFILE = "../02_SYN/Netlist/top_syn.sdf";
`ifdef SDF
	initial $sdf_annotate(SDFFILE, TOP);
`endif

TOP TOP(.clk(clk), .rst(rst), .gray_valid(gray_valid), .gray_data(gray_data),
    .CNT_valid(CNT_valid), 
    .CNT1(CNT[1]),   // should compare with exp_mem[0]
    .CNT2(CNT[2]),   // should compare with exp_mem[1]
    .CNT3(CNT[3]),   // should compare with exp_mem[2]
    .CNT4(CNT[4]),   // should compare with exp_mem[3]
    .CNT5(CNT[5]),   // should compare with exp_mem[4]
    .CNT6(CNT[6]),   // should compare with exp_mem[5]
    .code_valid(code_valid), 
    .HC1(HC[1]),   // should compare with exp_mem[6]
    .HC2(HC[2]),   // should compare with exp_mem[7]
    .HC3(HC[3]),   // should compare with exp_mem[8]
    .HC4(HC[4]),   // should compare with exp_mem[9]
    .HC5(HC[5]),   // should compare with exp_mem[10]
    .HC6(HC[6]),   // should compare with exp_mem[11]
    .M1(M[1]),   // should compare with exp_mem[12]
    .M2(M[2]),   // should compare with exp_mem[13]
    .M3(M[3]),   // should compare with exp_mem[14]
    .M4(M[4]),   // should compare with exp_mem[15]
    .M5(M[5]),   // should compare with exp_mem[16]
    .M6(M[6]) ); // should compare with exp_mem[17]

assign CNT_G = {CNT[1], CNT[2], CNT[3], CNT[4], CNT[5], CNT[6]};
assign CNT_EXP = {exp_mem[0], exp_mem[1], exp_mem[2], exp_mem[3], exp_mem[4], exp_mem[5]};
assign HC_G = {HC[1], HC[2], HC[3], HC[4], HC[5], HC[6]};
assign HC_EXP = {exp_mem[6], exp_mem[7], exp_mem[8], exp_mem[9], exp_mem[10], exp_mem[11]};
assign M_G = {M[1], M[2], M[3], M[4], M[5], M[6]};
assign M_EXP = {exp_mem[12], exp_mem[13], exp_mem[14], exp_mem[15], exp_mem[16], exp_mem[17]};

initial $readmemh(`PAT, pat_mem);
initial $readmemh(`EXP, exp_mem);
initial $display("%s and %s were used for this simulation.", `PAT, `EXP);   //

initial clk = 1'b0;

always begin #(`CYCLE/2) clk = ~clk; end

initial begin
  #0 rst = 1'b0;
  #`CYCLE rst = 1'b1;
  #(`CYCLE*2) rst = 1'b0;
end
initial begin
    $display(" Cycle Period = %0f ns", `CYCLE);
end
initial begin
  #0 gray_valid = 1'b0;
     i = 0;
  #(`CYCLE*5);
  @(negedge clk) gray_valid = 1'b1;
  gray_data = pat_mem[i];
  for (i=1;i<100;i=i+1)
    @(negedge clk) gray_data = pat_mem[i];
  @(negedge clk) gray_valid = 1'b0;
       gray_data = 8'b0;
end

reg out_end;
integer exe_cycle;
integer total_error;

always@(negedge clk) begin
  if (rst) begin
    done1 <= 1'b0;
    flag1 <= 1'b0;
    flag2 <= 1'b0;
    flag3 <= 1'b0;
    out_end <= 1'b0;
    total_error = 0;
    
  end else begin

    if(CNT_valid == 1'b1) begin
      if (CNT_G == CNT_EXP) begin     // flag1 1 means PASS, 0 means ERROR
        $display("Check CNT : PASS");
        flag1 <= 1'b1;
      end else begin
        $display("Check CNT : ERROR. Please fixed it first!");
        $display("Simulation stop here.");
        $finish;
      end
      done1 <= 1'b1;
    end

    if(code_valid == 1'b1) begin

      case ({(HC_G == HC_EXP),(M_G == M_EXP)})   // (HC_G == HC_EXP) true means HC PASS
        2'b00: begin                             // (M_G == M_EXP) true means M PASS
                 $display("Check HC : ERROR");
                 $display("Check M : ERROR");
                //  $display("Simulation stop here.");
                 total_error = 1;
                 out_end <= 1'b1;
                //  $finish;
               end
        2'b01: begin
                 $display("Check HC : ERROR");
                 $display("Check M : PASS");
                 total_error = 1;
                 out_end <= 1'b1;
                //  $display("Simulation stop here.");

                //  $finish;
               end
        2'b10: begin
                 $display("Check HC : PASS");
                 $display("Check M : ERRPR");
                 total_error = 1;
                 out_end <= 1'b1;
                //  $display("Simulation stop here.");
                //  $finish;
               end
        2'b11: begin
                 $display("Check HC : PASS");
                 $display("Check M : PASS");
                 if(flag1 == 1'b1)
                   $display("You PASS the contest now.");
                 else
                   $display("Where are those CNT output?");
                   out_end <= 1'b1;
                //  $finish;
                 //$stop;
               end
        endcase
    end

  end
end



initial begin
  repeat(5)@(negedge clk);
	exe_cycle = 0;
	while(!out_end) begin
		exe_cycle = exe_cycle + 1;
		@(negedge clk);
	end
  $display("----------------------------------------------");
  $display("------------total time: %0d cycles-----------------", exe_cycle);
  $display("----------------------------------------------");
	if(total_error == 0) begin
		$display("------------------------------------------------");
		$display("----------------All tests PASS!-----------------");
		$display("------------------------------------------------");
	end else begin
		$display("------------------------------------------------");
		$display("-              Total Error: %0d               -", total_error);
		$display("------------------------------------------------");
	end
	
	$finish;
end



/*
initial begin
  for (i=0; i<100; i=i+1) begin
    $display("%3d %h", i, pat_mem[i]);
  end
  $display("--------------------------------------");
  for( i=0; i<18; i=i+1) begin
    $display("%3d %h", i, exp_mem[i]);
  end
end
*/

endmodule

