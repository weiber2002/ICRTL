`timescale 1ns/10ps
`define CYCLE      10.0  
`define End_CYCLE  1000000
`define PAT        "./00_TB/cost_rom"

`ifdef P1
    `define PAT_NUM 1 
`elsif P2
    `define PAT_NUM 2 
`elsif P3
    `define PAT_NUM 3 
`else
    `define PAT_NUM 1 
`endif


module test;
integer fd;
localparam LINE_MAX = 256; 
integer charcount;
reg[LINE_MAX*8-1:0] line_buf;
string line;
integer freturn;

integer patnum;

reg clk = 0;
wire Valid;
reg rst = 1;
wire [2:0] W;
wire [2:0] J;
reg [6:0] Cost;
wire [3:0] MatchCount;
wire [9:0] MinCost;
TOP TOP(.clk(clk),
        .rst(rst),
        .W(W),
        .J(J),
        .Cost(Cost),
        .MatchCount(MatchCount),
        .MinCost(MinCost),
        .Valid(Valid));
        
localparam SDFFILE = "../02_SYN/Netlist/top_syn.sdf";
`ifdef SDF
	initial $sdf_annotate(SDFFILE, TOP);
`endif
always begin #(`CYCLE/2) clk = ~clk; end

initial begin
	$display(" Cycle Period = %0f ns", `CYCLE);
end

// initial begin
//     $fsdbDumpfile("top.fsdb");
//     $fsdbDumpvars(0, TOP);
// end

//initial begin
//    $dumpvars();
//    $dumpfile("JAM.vcd");
//end

initial begin
    $display("*******************************");
    $display("** Simulation Start          **");
    $display("*******************************");
    @(posedge clk);  #2 rst = 1'b1; 
    #(`CYCLE*2);  
    @(posedge clk);  #2  rst = 1'b0;
end

reg [30:0] cycle=0;
reg [6:0] costrom [0:63];
always @(posedge clk) begin
    cycle=cycle+1;
    if (cycle > `End_CYCLE) begin
        $display("-              Total Error: %0d               -", 1);
        $display("********************************************************************");
        $display("**  Failed waiting Valid signal, Simulation STOP at cycle %d **",cycle);
        $display("**  If needed, You can increase End_CYCLE value in tp.v           **");
        $display("********************************************************************");
        $fclose(fd);
        $finish;
    end
end
integer key_value;
string key;
integer v0,v1,v2,v3,v4,v5,v6,v7;
integer worker = -1;
integer i;
integer j;
reg [3:0] goldMatchCount;
reg [8:0] goldMinCost;
initial begin : MAIN
    //------------------------------------------------------------------
    // 1) 開檔
    //------------------------------------------------------------------
    fd = $fopen(`PAT,"r");
    if (fd == 0) begin
        $display("pattern handle null");
        $finish;
    end

    //------------------------------------------------------------------
    // 2) 讀第一行
    //------------------------------------------------------------------
    charcount = $fgets(line_buf, fd);
    line      = line_buf;          // reg → string

    //------------------------------------------------------------------
    // 3) 主迴圈：掃完整個檔案
    //------------------------------------------------------------------
    while (charcount > 0) begin : READ_PATTERN

        //------------------------------------------------------------------
        // 3‑1) 先把空行與註解行全部跳過
        //------------------------------------------------------------------
        while (charcount > 0 &&
            (charcount == 1 ||
            line_buf[8*LINE_MAX-1 -:16] == 16'h2f2f)) begin
            charcount = $fgets(line_buf, fd);
            line      = line_buf;
        end
        if (charcount == 0) disable READ_PATTERN;   // EOF 時提早離開

        //------------------------------------------------------------------
        // 3‑2) 判斷這行是 pattern 標頭還是資料
        //------------------------------------------------------------------
        if (line.substr(0, 6) == "pattern") begin
            freturn = $sscanf(line, "pattern %d", patnum);
            if (patnum == `PAT_NUM) $display("PATTERN: %3d", patnum);
        end
        else if (patnum == `PAT_NUM) begin
            // 只處理目標樣本的屬性或矩陣
            if ($sscanf(line, "min_cost %d", key_value) == 1) begin
                goldMinCost = key_value;
            end
            else if ($sscanf(line, "match_count %d", key_value) == 1) begin
                goldMatchCount = key_value;
            end
            else if ($sscanf(line,
                      "%d %d %d %d %d %d %d %d",
                      v0,v1,v2,v3,v4,v5,v6,v7) == 8) begin
                if (worker == -1) begin
                    $display("-------------- Cost Table --------------");
                    $display("Jobs       0   1   2   3   4   5   6   7");
                end
                worker = worker + 1;
                $display("worker%1d: %3d %3d %3d %3d %3d %3d %3d %3d",
                         worker,v0,v1,v2,v3,v4,v5,v6,v7);

                // 存進 ROM（一維展平）
                costrom[worker*8+0] = v0;
                costrom[worker*8+1] = v1;
                costrom[worker*8+2] = v2;
                costrom[worker*8+3] = v3;
                costrom[worker*8+4] = v4;
                costrom[worker*8+5] = v5;
                costrom[worker*8+6] = v6;
                costrom[worker*8+7] = v7;
            end
            else begin
                $display("unknown line: -%s-", line);
            end
        end

        //------------------------------------------------------------------
        // 3‑3) 讀下一行，再回到 while 判斷
        //------------------------------------------------------------------
        charcount = $fgets(line_buf, fd);
        line      = line_buf;
    end : READ_PATTERN
end : MAIN

reg wait_valid;
reg [2:0] W_s;
reg [2:0] J_s;
assign Cost=costrom[8*W_s+J_s];
always @(posedge clk ) begin
    W_s <=  #1 W;
    J_s <=  #1 J;
end

integer total_error;
always @(posedge clk ) begin
    total_error = 0;
    if (rst) begin
        wait_valid=1;
    end
    else begin
        if(cycle[20:0] == 20'b00000000000000000000) begin
            $display("cycle: %d, still running...", cycle);
        end
        if(wait_valid == 1) begin
            if (Valid ==1) begin
                wait_valid=0;
                $display("receive MinCost/MatchCount= %d/%d , golden MinCost/MatchCount= %d/%d",MinCost,MatchCount,goldMinCost,goldMatchCount);
                $display("----------------------------------------------");
                $display("------------total time: %0d cycles-----------------", cycle);
                $display("----------------------------------------------");
                if((goldMatchCount == MatchCount) && (goldMinCost == MinCost)) begin
            		$display("------------------------------------------------");
            		$display("----------------All tests PASS!-----------------");
            		$display("------------------------------------------------");
            	end else begin
                    total_error = 1;
            		$display("------------------------------------------------");
            		$display("-              Total Error: %0d               -", total_error);
            		$display("------------------------------------------------");
            	end

                $finish;
            end
        end
//assert (W<10) else $display("ERROR,at cycle %-d,  W = %d >10",cycle,W);
//assert (J<10) else $display("ERROR,at cycle %-d,  J = %d >10",cycle,J);
    end
end


endmodule

