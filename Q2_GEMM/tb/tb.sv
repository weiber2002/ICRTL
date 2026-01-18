`timescale 1ns/10ps
`define CYCLE 	  10.0
`define MAX_CYCLE 5000
`define RST_DELAY 5.0
`define SDFFILE    "../02_SYN/Netlist/top_syn.sdf"	  // Modify your sdf file name

`define Matrix1_A_ref "pattern/matrix1_A.hex"
`define Matrix2_A_ref "pattern/matrix2_A.hex"
`define Matrix3_A_ref "pattern/matrix3_A.hex"
`define Matrix1_B_ref "pattern/matrix1_B.hex"
`define Matrix2_B_ref "pattern/matrix2_B.hex"
`define Matrix3_B_ref "pattern/matrix3_B.hex"
`define Matrix1_O_ref "pattern/matrix1_O.hex"
`define Matrix2_O_ref "pattern/matrix2_O.hex"
`define Matrix3_O_ref "pattern/matrix3_O.hex"
`define INST_ref      "pattern/inst.hex"

module testfixture;

 // Ports
    wire            clk;
    wire            rst;
    wire            rst_n;
	logic           out_end;
	integer         correct, error, j, total_error;
            
	logic  [15:0]  matrixA1 [0:63], matrixA2 [0:63], matrixA3 [0:63];
    logic  [15:0]  matrixB1 [0:63], matrixB2 [0:63], matrixB3 [0:63];
    logic  [15:0]  matrixO1 [0:255], matrixO2 [0:255], matrixO3 [0:255];
	logic  [5:0]   inst_m  [0:3];

	// signal of top module
	logic [7:0] addr_A, addr_B, addr_I, addr_O;
	logic en_A, en_B, en_I, en_O;
	logic [15:0] data_A, data_B;
	logic [5:0]  data_I;
	logic [15:0] data_O;
    logic out_valid;
	logic ap_start, ap_done;

    logic [1:0] inst_length;

    integer s;

    initial begin
        $readmemh(`Matrix1_A_ref, matrixA1);
        $readmemh(`Matrix2_A_ref, matrixA2);
        $readmemh(`Matrix3_A_ref, matrixA3);
        $readmemh(`Matrix1_B_ref, matrixB1);
        $readmemh(`Matrix2_B_ref, matrixB2);
        $readmemh(`Matrix3_B_ref, matrixB3);
        $readmemh(`Matrix1_O_ref, matrixO1);
        $readmemh(`Matrix2_O_ref, matrixO2);
        $readmemh(`Matrix3_O_ref, matrixO3);
		$readmemh(`INST_ref, inst_m);
    end

    // initial begin
    //     $dumpfile("GEMM.vcd");
    //     $dumpvars(0, testfixture);
    // end

    `ifdef SDF
        initial begin
            $sdf_annotate(`SDFFILE, u_top);
        end
    `endif

    // Modules
    clk_gen clk_gen_inst (
        .clk   (clk),
        .rst   (rst),
        .rst_n (rst_n)
    );
    top u_top (
        .clk 	  (clk),
		.rst 	  (rst),
		.addr_A  (addr_A),
		.en_A 	  (en_A),
		.data_A  (data_A),
		.addr_B  (addr_B),
		.en_B 	  (en_B),
		.data_B  (data_B),
		.addr_I  (addr_I),
		.en_I 	  (en_I),
		.data_I  (data_I),
		.addr_O  (addr_O),
		.data_O  (data_O),
        .en_O 	  (en_O),
        .out_valid(out_valid),
		.ap_start(ap_start),
		.ap_done (ap_done)

    );
    
    // initial begin
    //     $fsdbDumpfile("top.fsdb");
    //     $fsdbDumpvars(0, "+all");
    // end

    integer i, inst_i;
    // Input
    initial begin

        i = 0; inst_i = 0;
        addr_A = 0; addr_B = 0; addr_I = 0; addr_O = 0;
        en_A = 0; en_B = 0; en_I = 0;
        data_A = 0; data_B = 0; data_I = 0;
		ap_start = 0;

        out_end = 0;
        correct = 0;
        error   = 0;
        total_error = 0;
        en_O = 0;

        j = 0;

        // Waiting for reset to finish
        wait (rst_n === 1'b0);
        wait (rst_n === 1'b1);
        @(posedge clk);

        while(inst_m[inst_i] !== 0) begin
            $display("----------------------------------------------");
            $display("-             inst = %0d                      -", inst_m[inst_i]);
            @(negedge clk);
            addr_I = inst_i;
            en_I = 1;
            data_I = inst_m[inst_i];

            while(i < 64) begin
                @(negedge clk);
                en_I = 0;
                addr_A = i;             addr_B = i;
                en_A = 1;               en_B = 1;
                case(inst_i)
                0: begin
                    data_A = matrixA1[i]; data_B = matrixB1[i];
                end
                1: begin
                    data_A = matrixA2[i]; data_B = matrixB2[i];
                end
                2: begin
                    data_A = matrixA3[i]; data_B = matrixB3[i];
                end
                endcase

                i = i + 1;
            end
            i = 0;
            @(negedge clk);
            ap_start = 1;
            $display("-             START COMPUTE                  -");

            @(posedge ap_done);
            $display("-             CHECK ANSWER                   -");
            ap_start = 0;
            @(posedge clk);
            
            while (ap_done) begin
                @(negedge clk);
                addr_O = j;
                en_O = 1;
                @(negedge clk);
                en_O = 0;
                if(out_valid) begin
                    case(inst_i)
                    0: begin
                        if (data_O === matrixO1[j]) begin
                            correct = correct + 1;
                        end else begin
                            error = error + 1;
                            $display("Test[%d]: Error!, expected %h, got %h", j, matrixO1[j], data_O);
                        end
                    end
                    1: begin
                        if (data_O === matrixO2[j]) begin
                            correct = correct + 1;
                        end else begin
                            error = error + 1;
                            $display("Test[%d]: Error!, expected %h, got %h", j, matrixO2[j], data_O);
                        end
                    end
                    2: begin
                        if (data_O === matrixO3[j]) begin
                            correct = correct + 1;
                        end else begin
                            error = error + 1;
                            $display("Test[%d]: Error!, expected %h, got %h", j, matrixO3[j], data_O);
                        end
                    end
                    endcase
                end
                j = j + 1;
                if(j==256) begin
                    j = 0;
                    inst_i = inst_i + 1;
                    en_O = 0;
                    if(error == 0) begin
                        $display("----------------------------------------------");
                        $display("-              Test %0d PASS!                  -", inst_i);
                        $display("----------------------------------------------");
                    end
                    total_error = total_error + error;
                    error = 0;
                end
            end
        end
        out_end = 1;
    end

    // execution cycle
    integer exe_cycle;
    real err_percent;
    integer N_EXP = 256 * 3;

    initial begin
        exe_cycle = 0;
        while(!out_end) begin
            while(ap_start) begin
                @(posedge clk);
                exe_cycle = exe_cycle + 1;
            end
            @(negedge clk);
        end
        // $display("-----------------------------------------------------------------");
        // $display("it takes %d cycles to finish (without loading and comparing answer)", exe_cycle);
        // $display("-----------------------------------------------------------------");
        
        if(total_error == 0) begin
            $display("------------------------------------------------");
            $display("----------------All tests PASS!-----------------");
            $display("------------total time: %0d cycles-----------------", exe_cycle);
            $display("------------------------------------------------");
        end else begin
            err_percent = (total_error * 100.0) / N_EXP; // 計算百分比
            $display("------------------------------------------------");
			$display("------------------FAIL-------------------------");
            $display("-   Total Error: %0d (%.2f%% of total pixels)   -", total_error, err_percent);
            $display("------------------------------------------------");
        end
        
        $finish;
    end

endmodule

module clk_gen(
    output reg clk,
    output reg rst,
    output reg rst_n
);
    always #(`CYCLE/2.0) clk = ~clk;
    // initial begin
    //     clk = 1'b0;
    //     rst = 1'b0; rst_n = 1'b1; #(              0.25  * `CYCLE);
    //     rst = 1'b1; rst_n = 1'b0; #((`RST_DELAY - 0.25) * `CYCLE);
    //     rst = 1'b0; rst_n = 1'b1; #(         `MAX_CYCLE * `CYCLE);
    //     $display("Error! Time limit exceeded!");
    //     $finish;
    // end

   initial begin
        clk = 1'b1; 
        rst = 1'b0;  rst_n = 1'b1; #(`CYCLE * 0.25);
        rst = 1'b1;  rst_n = 1'b0; #((`RST_DELAY)        * `CYCLE);
        rst = 1'b0; rst_n = 1'b1;
        
        #(`MAX_CYCLE * `CYCLE);
        $display("------------------------");
        $display("-------FAIL-------------");
        $display("Error! Runtime exceeded!");
        $display("------------------------");
        $finish;
    end
endmodule
