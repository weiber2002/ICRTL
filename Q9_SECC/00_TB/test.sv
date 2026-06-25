`timescale 1ns/10ps
`define SDFFILE    "../SYN/SET_syn.sdf"    // Modify your sdf file name here
`define cycle 10.0
`define terminate_cycle 2000000 // watchdog for the whole 4-mode sweep

module testfixture1;

`define central_pattern "./00_TB/dat/Central_pattern.dat"
`define radius_pattern "./00_TB/dat/Radius_pattern.dat"
`define  candidate_result_Length "./00_TB/dat/candidate_result_Length.dat"
`define  candidate_united_result_Length "./00_TB/dat/candidate_united_result_Length.dat"
`define  candidate_diff_result_Length "./00_TB/dat/candidate_diff_result_Length.dat"
`define  candidate_intersect_result_Length "./00_TB/dat/candidate_intersect_result_Length.dat"

reg clk = 0;
reg rst;
reg en;
reg [23:0] central;
reg [11:0] radius;
reg [1:0] mode;
wire busy;
wire valid;
wire [7:0] candidate;

integer err_cnt;
reg [31:0] cycle_cnt;

reg [23:0] central_pat_mem [0:63];
reg [11:0] radius_pat_mem[0:63];
reg [7:0] expected_mem [0:63];

`ifdef SDF
initial $sdf_annotate(`SDFFILE, u_set);
`endif

initial begin
	$timeformat(-9, 1, " ns", 9); //Display time in nanoseconds
	$readmemh(`central_pattern, central_pat_mem);
	$readmemh(`radius_pattern, radius_pat_mem);
end

always #(`cycle/2) clk = ~clk;

// Total cycle counter (accumulates across all four modes -> sum)
initial cycle_cnt = 0;
always @(posedge clk) cycle_cnt = cycle_cnt + 1;

TOP u_set( .clk(clk), .rst(rst), .en(en), .central(central), .radius(radius), .mode(mode), .busy(busy), .valid(valid), .candidate(candidate) );

integer k, md;
initial begin
	en  = 0;
	rst = 0;
	mode = 2'b00;
	err_cnt = 0;

	// Sweep all four modes (MD1..MD4) in a single simulation.
	for (md = 0; md < 4; md = md + 1) begin
		// Load the expected result length for this mode.
		case (md)
			0: $readmemh(`candidate_result_Length, expected_mem);
			1: $readmemh(`candidate_united_result_Length, expected_mem);
			2: $readmemh(`candidate_diff_result_Length, expected_mem);
			3: $readmemh(`candidate_intersect_result_Length, expected_mem);
		endcase
		mode = md[1:0];
		$display("--------------------------- [ Function %0d. Simulation START !! ] ---------------------------", md + 1);

		// Reset the DUT before each mode.
		en  = 0;
		@(negedge clk);
		rst = 1;
		repeat (3) @(negedge clk);
		rst = 0;

		for (k = 0; k <= 63; k = k + 1) begin
			@(negedge clk);
			//change inputs at strobe point
			#(`cycle/4) wait(busy == 0);
				en = 1;
				central = central_pat_mem[k];
				radius = radius_pat_mem[k];
				#(`cycle) en = 0;
				wait (valid == 1);
				//Wait for signal output
				@(negedge clk);
					if (candidate === expected_mem[k])
						$display(" Pattern %d at Mode %d is PASS !", k, mode);
					else begin
						$display(" Pattern %d at Mode %d is FAIL !. Expected candidate = %d, but the Response candidate = %d !! ", k, mode, expected_mem[k], candidate);
						err_cnt = err_cnt + 1;
					end
		end
		#(`cycle*2);
	end

	$display("--------------------------- Simulation FINISH !!---------------------------");
	$display("Total Error: %0d", err_cnt);
	if (err_cnt == 0)
		$display("All tests PASS");
	else
		$display("(T_T) FAIL!! there were %0d errors at all.", err_cnt);
	$display("total time: %0d cycles", cycle_cnt);
	$finish;
end

initial begin
	#`terminate_cycle;
	$display("--------------------------- (/`n`)/ ~#  Simulation can't finish, please check your code !! ---------------------------");
	$display("Total Error: %0d", err_cnt);
	$display("total time: %0d cycles", cycle_cnt);
	$finish;
end

endmodule
