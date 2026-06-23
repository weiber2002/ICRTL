
`timescale 1ns/10ps
`define CYCLE      50.0  
`define SDFFILE    "./REFRACT_syn.sdf"
`define MAX_CYCLE  100000
`define SHOW_MISMATCH_MAX 8
`define SHOW_MATCH 0

`define TOLERANCE_RADIUS 64 // tolerance = 64/4096 unit 


module testfixture();
reg CLK= 0;
reg RST =0;

reg  [3:0]  INDEX;
wire [8:0]  SRAM_A;
wire [15:0] SRAM_D;
wire [15:0] SRAM_Q;
wire        SRAM_WE;
wire        DONE;

REFRACT u_REFRACT( .CLK(CLK), .RST(RST), .RI(INDEX), .SRAM_A(SRAM_A), .SRAM_D(SRAM_D), .SRAM_Q(SRAM_Q), .SRAM_WE(SRAM_WE), .DONE(DONE));

SRAM u_SRAM ( .A(SRAM_A), .CLK(CLK), .D(SRAM_D), .Q(SRAM_Q), .WE(SRAM_WE));

`ifdef SDF
    initial $sdf_annotate(`SDFFILE, u_REFRACT);
`endif


//initial begin
//    $fsdbDumpfile("REFRACT.fsdb");
//    $fsdbDumpvars();
//    $fsdbDumpMDA;
//end

initial begin
    $dumpfile("REFRACT.vcd");
    $dumpvars;
end

integer mismatch_cnt;
integer show_cnt;
integer x,y;
reg [15:0] golden_x,golden_y;
reg [15:0] get_x,get_y;
integer error_distance;
real    error_distance_real;
integer mem_index;


function integer distance;
    input [15:0] x1;
    input [15:0] y1;
    input [15:0] x2;
    input [15:0] y2;
    real nx1,nx2,ny1,ny2;
    real dist_square;
    begin
        nx1=x1;
        nx2=x2;
        ny1=y1;
        ny2=y2;
        //if ($isunknown({x1,y1,x2,y2})) distance = -1;
        if (^{x1,y1,x2,y2}===1'bx) distance = -1;
        else begin
            dist_square= (nx1-nx2)**2+(ny1-ny2)**2 ;
            distance= $sqrt(dist_square); 
            //$display("%f,%f",dist_square,distance);
        end
    end
endfunction

initial begin
    #1
    $timeformat(-9,2,"ns",20);
end

reg [8*64-1:0] golden_fname;   
reg [15:0] golden [0:511];

`ifndef RI
    `define RI 5
`endif

initial begin
    INDEX = `RI ;
    $sformat(golden_fname, "00_TB/golden/golden_%0d.memh", INDEX);
    $display("Loading golden file: %0s", golden_fname);
    $readmemh(golden_fname, golden);
end

initial begin
    CLK = 1'b0;
    forever #(`CYCLE/2) CLK = ~CLK; 
end

reg [22:0] cycle_cnt=0;
real    tolerance_distance = `TOLERANCE_RADIUS/4096.0;

initial begin
    $display("--------------------------------");
    $display("-- Simulation Start , RI = %d --",INDEX);
    $display("--------------------------------");
    RST = 1'b1; 
    mismatch_cnt = 0;
    cycle_cnt=0;
    show_cnt=0;
    #(`CYCLE*2);  
    @(posedge CLK);  #1  RST = 1'b0;
    repeat (2) @(posedge CLK);

    wait (DONE === 1'b1);
    $display("%10t, Recive DONE", $time);

    for (y = 0; y < 16; y = y + 1) begin
        for (x = 0; x < 16; x = x + 1) begin
            mem_index = y*16+x*2;
            get_x = u_SRAM.mem[mem_index];
            get_y = u_SRAM.mem[mem_index+1];
            golden_x = golden[mem_index];
            golden_y = golden[mem_index+1];
            error_distance = distance(get_x,get_y,golden_x,golden_y);
            error_distance_real = error_distance;
            if (error_distance>0) begin
                error_distance_real = error_distance/4096.0;
            end

            if ((error_distance<0) || (error_distance > `TOLERANCE_RADIUS)) begin
                mismatch_cnt = mismatch_cnt + 1;
                if (show_cnt < `SHOW_MISMATCH_MAX) begin
                    $display("MISMATCH (%0d,%0d), got= (0x%04h,0x%04h), exp=(0x%04h,0x%04h) distance=%g ", x,y,get_x,get_y,golden_x,golden_y,error_distance_real);
                    show_cnt = show_cnt + 1;
                end
            end else begin
                if (`SHOW_MATCH) begin
                    $display("MATCH (%0d,%0d), got= (0x%04h,0x%04h), exp=(0x%04h,0x%04h) distance=%g ", x,y,get_x,get_y,golden_x,golden_y,error_distance_real);
                end
            end
        end
    end


    if (mismatch_cnt == 0) begin
        $display("--------------------------------------------------");
        $display("-- Simulation Finished , RI = %d",INDEX);
        $display("-- PASS: all 256 points match " );
        $display("-- Execution Time: %10t", $time);
        $display("--------------------------------------------------");
    end else begin
        $display("-------------------------------------------------------------------------");
        $display("-- Simulation Finished , RI = %d , Max tolerance diatance = %g",INDEX, tolerance_distance);
        $display("-- FAIL: mismatches = %0d / 256", mismatch_cnt);
        $display("-- Execution Time: %10t", $time);
        $display("-------------------------------------------------------------------------");
    end

    $finish;
end

always @(posedge CLK) begin
    cycle_cnt=cycle_cnt+1;
    if (cycle_cnt > `MAX_CYCLE) begin
        $display("--------------------------------------------------");
        $display("-- MAX_CYCLE %d reached, Simulation STOP ", `MAX_CYCLE);
        $display("-- You can extend MAX_CYCLE in tb.v if necessary.");
        $display("--------------------------------------------------");
        $finish;
    end
end

endmodule

module SRAM (
    input  wire [8:0]  A,
    input  wire        CLK,
    input  wire [15:0] D,
    output reg  [15:0] Q,
    input  wire        WE
);
    reg [15:0] mem [0:511];
    integer i;
    initial begin
        Q = 16'h0000;
        for (i = 0; i < 512; i = i + 1)
            mem[i] = 16'h0000;
    end

    always @(posedge CLK) begin
        if (WE) mem[A] <= D;
        Q <= mem[A];
    end
endmodule

