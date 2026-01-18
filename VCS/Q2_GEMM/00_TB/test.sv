`timescale 1ns/10ps
`define CYCLE 	  4.4
`define MAX_CYCLE 5000
`define RST_DELAY `CYCLE/2
`define Matrix1_A_ref "../00_TB/data/matrix1_A.hex"
`define Matrix2_A_ref "../00_TB/data/matrix2_A.hex"
`define Matrix3_A_ref "../00_TB/data/matrix3_A.hex"
`define Matrix1_B_ref "../00_TB/data/matrix1_B.hex"
`define Matrix2_B_ref "../00_TB/data/matrix2_B.hex"
`define Matrix3_B_ref "../00_TB/data/matrix3_B.hex"
`define Matrix1_O_ref "../00_TB/data/matrix1_O.hex"
`define Matrix2_O_ref "../00_TB/data/matrix2_O.hex"
`define Matrix3_O_ref "../00_TB/data/matrix3_O.hex"
`define INST_ref      "../00_TB/data/inst.hex"

module test;

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


    localparam SDFFILE = "../02_SYN/Netlist/top_syn.sdf";
    `ifdef SDF
        initial $sdf_annotate(SDFFILE, TOP);
    `endif

    // initial begin
    //     $dumpfile("GEMM.vcd");
    //     $dumpvars(0, testfixture);
        // for(i = 0; i < M; i = i + 1) $dumpvars(1, full.path.to.array.data[i]);
        // for(s = 0; s < 64; s++) begin
        //     $dumpvars(1, testfixture.u_top.matrixA_r[s]);
        // end
        // for(s = 0; s<256; s++) begin
        //     $dumpvars(1, testfixture.u_top.matrixO1_r[s]);
        // end
        // for(s = 0; s<16; s++) begin
        //     $dumpvars(1, testfixture.u_top.tileO_data[s]);
        // end
        // for(s = 0; s<16; s++) begin
        //     $dumpvars(1, testfixture.u_top.systolic_inst.tileO_data[s]);
        // end
        // for(s = 0; s<6; s++) begin
        //     $dumpvars(1, testfixture.u_top.inst_m_r[s]);
        // end
        // $dumpvars(1, testfixture.u_top.tile_en);

        // $dumpvars(1, testfixture.u_top.matrixA_r[2]);
    // end


    // Modules
    clk_gen clk_gen_inst (
        .clk   (clk),
        .rst   (rst),
        .rst_n (rst_n)
    );
    TOP_Control TOP_Control (
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
    
    initial begin
        $fsdbDumpfile("top.fsdb");
        $fsdbDumpvars(0, TOP_Control);
    end
    initial begin
        $display(" Cycle Period = %0f ns", `CYCLE);
    end

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

    initial begin
        exe_cycle = 0;
        while(!out_end) begin
            while(ap_start) begin
                @(posedge clk);
                exe_cycle = exe_cycle + 1;
            end
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
        $display("Error! Runtime exceeded!");
        $display("------------------------");
        $finish;
    end
endmodule


module TOP_Control (
    input clk,
    input rst, 
    input  [7:0]  addr_A, 
    input         en_A,
    input  [15:0] data_A,
    input  [7:0]  addr_B,
    input         en_B,
    input  [15:0] data_B,
    input  [7:0]  addr_I,
    input         en_I,
    input  [5:0]  data_I,
    input  [7:0]  addr_O,
    output [15:0] data_O,
    input         en_O,
    output        out_valid,
    input         ap_start,
    output        ap_done
);

    reg [15:0] matrixA_w[0:63], matrixA_r[0:63];
    reg [15:0] matrixB_w[0:63], matrixB_r[0:63];
    reg [15:0] matrixO1_w[0:255], matrixO1_r[0:255];
    reg [5:0]  inst_m_w  [0:5], inst_m_r  [0:5];

    reg tile_en;
    reg  [15:0] tileA_data [0:3], tileB_data [0:3];
    wire [15:0] tileO_data [0:15];
    wire o_valid;

    TOP TOP (
        .clk(clk),
        .rst(rst),
        .tile_en(tile_en),
        // .tileA_data(tileA_data),
        // .tileB_data(tileB_data),
        .tileA_data_0(tileA_data[0]),
        .tileA_data_1(tileA_data[1]),
        .tileA_data_2(tileA_data[2]),
        .tileA_data_3(tileA_data[3]),
        .tileB_data_0(tileB_data[0]),
        .tileB_data_1(tileB_data[1]),
        .tileB_data_2(tileB_data[2]),
        .tileB_data_3(tileB_data[3]),
        // .tileO_data(tileO_data),
        .tileO_data_0(tileO_data[0]),
        .tileO_data_1(tileO_data[1]),
        .tileO_data_2(tileO_data[2]),
        .tileO_data_3(tileO_data[3]),
        .tileO_data_4(tileO_data[4]),
        .tileO_data_5(tileO_data[5]),
        .tileO_data_6(tileO_data[6]),
        .tileO_data_7(tileO_data[7]),
        .tileO_data_8(tileO_data[8]),
        .tileO_data_9(tileO_data[9]),
        .tileO_data_10(tileO_data[10]),
        .tileO_data_11(tileO_data[11]),
        .tileO_data_12(tileO_data[12]),
        .tileO_data_13(tileO_data[13]),
        .tileO_data_14(tileO_data[14]),
        .tileO_data_15(tileO_data[15]),
        .o_valid(o_valid)
    );

    typedef enum logic [2:0] {
        IDLE, 
        LOADING, 
        FILLING,
        COMPUTE, 
        DONE, 
        FINISH
    } state_t;
    state_t state_w, state_r;

    reg [1:0] load_num_w, load_num_r;
    reg [2:0] inst_num_w, inst_num_r;
    reg [1:0] tile_row_num_w, tile_row_num_r;
    reg [1:0] tile_col_num_w, tile_col_num_r;

    reg [15:0] odata_w, odata_r;
    reg out_valid_w, out_valid_r;
    wire [2:0] inst_sel;
    

    assign ap_done   = (state_r == DONE);
    assign data_O    = odata_r;
    assign out_valid = out_valid_r;
    assign inst_sel = addr_I[2:0];
    

    always@(*)  begin
        state_w = state_r;
        case (state_r)
        IDLE: begin
            state_w = LOADING;
        end
        LOADING: begin
            if(ap_start) begin
                state_w = FILLING;
            end
            if(en_I && data_I==0) begin
                state_w = FINISH;
            end
        end
        FILLING: begin
            if(load_num_r == 3) begin
                state_w = COMPUTE;
            end
        end
        COMPUTE: begin
            if(o_valid) begin
                case(inst_m_r[inst_num_r])
                4: begin
                    state_w = DONE;
                end
                8: begin
                    if(tile_row_num_r == 1 && tile_col_num_r == 1) begin
                        state_w = DONE; // Move to DONE after filling first tile
                    end else begin
                        state_w = FILLING; // Continue filling next tile
                    end
                end
                16: begin
                    if(tile_row_num_r == 3 && tile_col_num_r == 3) begin
                        // state_w = DONE; // Move to DONE after filling second tile
                        state_w = DONE;
                    end else begin
                        state_w = FILLING; // Continue filling next tile
                    end
                end
                endcase
            end
        end
        DONE: begin
            if(en_O && addr_O == 255) begin
                state_w = LOADING; // Otherwise, go back to LOADING
            end
        end
        FINISH: begin
        end
        endcase
    end
    always @(posedge clk or posedge rst) begin
        if (rst) state_r <= IDLE;
        else state_r <= state_w;
    end

    
    always@(*)  begin
        for(int i=0; i<64; i++) begin
            matrixA_w[i] = matrixA_r[i];
            matrixB_w[i] = matrixB_r[i];
        end
        for(int i=0; i<256; i++) begin
            matrixO1_w[i] = matrixO1_r[i];
        end
        for(int i=0; i<6; i++) begin
            inst_m_w[i] = inst_m_r[i];
        end
        tile_en    = 0;
        load_num_w = load_num_r;
        inst_num_w = inst_num_r;
        tile_row_num_w = tile_row_num_r;
        tile_col_num_w = tile_col_num_r;
        for(int i=0; i<4; i++) begin
            tileA_data[i] = 0;
            tileB_data[i] = 0;
        end
        odata_w     = odata_r;
        out_valid_w = 0;

        case(state_r)
        IDLE: begin end
        LOADING: begin
            if(en_A) begin // and en_B
                matrixA_w[addr_A] = data_A;
                matrixB_w[addr_B] = data_B;
            end
            if(en_I && data_I!=0) begin
                inst_m_w[inst_sel] = data_I;
            end
        end
        FILLING: begin
            load_num_w = load_num_r + 1;
            tile_en = 1; // Enable tile for processing
            if(load_num_r == 3) begin        
                load_num_w = 0;
            end
            // 0000 0001 0010 0011
            // 0100 0101 0110 0111
            // 1000 1001 1010 1011
            // 1100 1101 1110 1111
            case(load_num_r)
            0: begin
                for(int i=0;i<4;i++) begin
                    tileA_data[i] = matrixA_r[4*tile_row_num_r*4 + i];
                    tileB_data[i] = matrixB_r[4*tile_col_num_r + i];
                end
            end
            1: begin
                for(int i=0;i<4;i++) begin
                    tileA_data[i] = matrixA_r[(4*tile_row_num_r + 1)*4 + i];
                    tileB_data[i] = matrixB_r[16 + 4*tile_col_num_r + i];
                end
            end
            2: begin
                for(int i=0;i<4;i++) begin
                    tileA_data[i] = matrixA_r[(4*tile_row_num_r + 2)*4 + i];
                    tileB_data[i] = matrixB_r[32 + 4*tile_col_num_r + i];
                end
            end
            3: begin
                for(int i=0;i<4;i++) begin
                    tileA_data[i] = matrixA_r[(4*tile_row_num_r + 3)*4 + i];
                    tileB_data[i] = matrixB_r[48 + 4*tile_col_num_r + i];
                end
            end
            endcase
        end
            
        COMPUTE: begin
            if(o_valid) begin
                for(int i=0; i<4; i++) begin
                    for(int j=0; j<4; j++) begin
                        matrixO1_w[(4*tile_row_num_r + i)*16 + 4*tile_col_num_r + j] = tileO_data[4*i + j];

                    end
                end
                case(inst_m_r[inst_num_r])
                4: begin
                end
                8: begin
                    tile_col_num_w = tile_col_num_r + 1;
                    if(tile_col_num_r == 1) begin
                        tile_row_num_w = 1;
                        tile_col_num_w = 0; // Reset column for next row
                        if(tile_row_num_r == 1) begin
                            tile_row_num_w = 0;
                        end
                    end
                end
                16: begin
                    tile_col_num_w = tile_col_num_r + 1;
                    if(tile_col_num_r == 3) begin
                        tile_row_num_w = tile_row_num_r + 1;
                        tile_col_num_w = 0; // Reset column for next row
                        if(tile_row_num_r == 3) begin
                            tile_row_num_w = 0;
                        end
                    end
                end
                endcase
            end
        end
        DONE: begin
            if(en_O) begin
                out_valid_w = 1;
                // odata_w = matrixO1_r[addr_O[7:4]][addr_O[3:0]];
                odata_w = matrixO1_r[addr_O]; // Flattened access
                if(addr_O == 255) begin
                    inst_num_w = inst_num_r + 1;
                    for(int i = 0; i < 256; i++) begin
                        matrixO1_w[i] = 0; // Reset output matrix after reading
                    end
                end
            end
            
        end
        endcase
    end
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            for(int i = 0; i < 256; i++) begin
                matrixO1_r[i] <= 0;
            end
        end
        else if(state_r == COMPUTE || state_r == DONE) begin
            for(int i = 0; i < 256; i++) begin
                matrixO1_r[i] <= matrixO1_w[i];
            end
        end
    end
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for(int i = 0; i < 64; i++) begin
                matrixA_r[i] <= 0;
                matrixB_r[i] <= 0;
            end
            for (int k = 0; k < 6; k++) begin
                inst_m_r[k] <= 0;
            end
        end else if(state_r == LOADING) begin

            for(int i = 0; i < 64; i++) begin
                matrixA_r[i] <= matrixA_w[i];
                matrixB_r[i] <= matrixB_w[i];
            end
            for (int k = 0; k < 6; k++) begin
                inst_m_r[k] <= inst_m_w[k];
            end
        end
    end

    always @(posedge clk or posedge rst) begin
        if(rst) begin
            odata_r <= 0;
        end
        else if(state_r == DONE) begin
            odata_r <= odata_w;
        end
    end

    always @(posedge clk or posedge rst) begin
        if(rst) begin
            out_valid_r    <= 0;
            load_num_r     <= 0;
            inst_num_r     <= 0;
            tile_row_num_r <= 0;
            tile_col_num_r <= 0;
        end else begin
            out_valid_r    <= out_valid_w;
            load_num_r     <= load_num_w;
            inst_num_r     <= inst_num_w;
            tile_row_num_r <= tile_row_num_w;
            tile_col_num_r <= tile_col_num_w;
        end
    end


endmodule


