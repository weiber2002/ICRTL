`timescale 1ns/10ps
`define CYCLE      10          	  // Modify your clock period here
`define End_CYCLE  10000000              // Modify cycle times once your design need more cycle times!
`define PAT        "../00_TB/pattern1.dat" 
   
`define EXP        "../00_TB/golden1.dat"     


module test;

parameter N_EXP   = 16384; // 128 x 128 pixel
parameter N_PAT   = N_EXP;

reg   [7:0]   gray_mem   [0:N_PAT-1];
reg   [7:0]   exp_mem    [0:N_EXP-1];

reg [7:0] LBP_dbg;
reg [7:0] exp_dbg;
wire [7:0] lbp_data;
reg   clk = 0;
reg   rst = 0;
reg   result_compare = 0;

integer total_error = 0;
integer times = 0;
reg over = 0;
integer exp_num = 0;
wire [13:0] gray_addr;
wire [13:0] lbp_addr;
reg [7:0] gray_data;
reg gray_ready = 0;
integer i;

   TOP TOP( .clk(clk), .rst(rst), 
            .gray_addr(gray_addr), .gray_req(gray_req), .gray_ready(gray_ready), .gray_data(gray_data), 
			.lbp_addr(lbp_addr), .lbp_valid(lbp_valid), .lbp_data(lbp_data), .finish(finish));
			
   lbp_mem u_lbp_mem(.lbp_valid(lbp_valid), .lbp_data(lbp_data), .lbp_addr(lbp_addr), .clk(clk));
   

localparam SDFFILE = "../02_SYN/Netlist/top_syn.sdf";
`ifdef SDF
	initial $sdf_annotate(SDFFILE, TOP);
`endif


initial	$readmemh (`PAT, gray_mem);
initial	$readmemh (`EXP, exp_mem);

always begin #(`CYCLE/2) clk = ~clk; end

// initial begin
// 	$fsdbDumpfile("LBP.fsdb");
// 	$fsdbDumpvars;
// end

initial begin  // data input
   @(negedge clk)  rst = 1'b1; 
   #(`CYCLE*2);    rst = 1'b0; 
   @(negedge clk)  gray_ready = 1'b1;
    while (finish == 0) begin             
      if( gray_req ) begin
         gray_data = gray_mem[gray_addr];  
      end 
      else begin
         gray_data = 'hz;  
      end                    
      @(negedge clk); 
    end     
    gray_ready = 0; gray_data='hz;
	@(posedge clk) result_compare = 1; 
end

initial begin // result compare
	$display("-----------------------------------------------------\n");
 	$display("START!!! Simulation Start .....\n");
 	$display("-----------------------------------------------------\n");
	#(`CYCLE*3); 
	wait( finish ) ;
	@(posedge clk); @(posedge clk);
	for (i=0; i <N_PAT ; i=i+1) begin
			//@(posedge clk);  // TRY IT ! no comment this line for debugging !!
				exp_dbg = exp_mem[i]; LBP_dbg = u_lbp_mem.LBP_M[i];
				if (exp_mem[i] == u_lbp_mem.LBP_M[i]) begin
					total_error = total_error;
				end
				else begin
					//$display("pixel %d is FAIL !!", i); 
					total_error = total_error+1;
					if (total_error <= 10) $display("Output pixel %d are wrong!", i);
					if (total_error == 11) begin $display("Find the wrong pixel reached a total of more than 10 !, Please check the code .....\n");  end
				end
				if( ((i%1000) === 0) || (i == 16383))begin  
					if ( total_error === 0)
      					$display("Output pixel: 0 ~ %d are correct!\n", i);
					else
					$display("Output Pixel: 0 ~ %d are wrong ! The wrong pixel reached a total of %d or more ! \n", i, total_error);
					
  				end					
				exp_num = exp_num + 1;
	end
	over = 1;
end

integer exe_cycle;
reg ooo;
initial begin
	ooo = 0;
	exe_cycle = 0;
	repeat(3) @(posedge clk);
	while(over != 1) begin
		exe_cycle = exe_cycle + 1;
		@(negedge clk);
	end
	ooo = 1;
end


initial begin
	$display(" Cycle Period = %0f ns", `CYCLE);
end
initial  begin
 #`End_CYCLE ;
 	$display("-----------------------------------------------------\n");
 	$display("Error!!! Somethings' wrong with your code ...!\n");
 	$display("-------------------------FAIL------------------------\n");
 	$display("-----------------------------------------------------\n");
 	$finish;
end

initial begin
      @(posedge ooo);      
      if((ooo) && (exp_num!='d0)) begin
         $display("-----------------------------------------------------\n");
        if(total_error == 0) begin
            $display("------------------------------------------------");
            $display("----------------All tests PASS!-----------------");
            $display("------------total time: %0d cycles-----------------", exe_cycle);
            $display("------------------------------------------------");
        end else begin
            $display("------------------------------------------------");
            $display("-              Total Error: %0d               -", total_error);
            $display("------------------------------------------------");
        end
      end
      #(`CYCLE/2); $finish;
end


        
        

endmodule


module lbp_mem (lbp_valid, lbp_data, lbp_addr, clk);
input		lbp_valid;
input	[13:0] 	lbp_addr;
input	[7:0]	lbp_data;
input		clk;

reg [7:0] LBP_M [0:16383];
integer i;

initial begin
	for (i=0; i<=16383; i=i+1) LBP_M[i] = 0;
end

always@(negedge clk) 
	if (lbp_valid) LBP_M[ lbp_addr ] <= lbp_data;

endmodule





