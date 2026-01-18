module top (
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
    reg  [15:0] tileA_data_0, tileA_data_1, tileA_data_2, tileA_data_3;
    reg  [15:0] tileB_data_0, tileB_data_1, tileB_data_2, tileB_data_3;
    wire [15:0] tileO_data [0:15];
    wire [15:0] tileO_data_0, tileO_data_1, tileO_data_2, tileO_data_3, tileO_data_4, tileO_data_5, tileO_data_6, tileO_data_7, tileO_data_8, tileO_data_9, tileO_data_10, tileO_data_11, tileO_data_12, tileO_data_13, tileO_data_14, tileO_data_15;
    wire o_valid;

    assign tileA_data_0 = tileA_data[0];
    assign tileA_data_1 = tileA_data[1];
    assign tileA_data_2 = tileA_data[2];
    assign tileA_data_3 = tileA_data[3];

    assign tileB_data_0 = tileB_data[0];
    assign tileB_data_1 = tileB_data[1];
    assign tileB_data_2 = tileB_data[2];
    assign tileB_data_3 = tileB_data[3];

    assign tileO_data[0]  = tileO_data_0;
    assign tileO_data[1]  = tileO_data_1;
    assign tileO_data[2]  = tileO_data_2;
    assign tileO_data[3]  = tileO_data_3;
    assign tileO_data[4]  = tileO_data_4;
    assign tileO_data[5]  = tileO_data_5;
    assign tileO_data[6]  = tileO_data_6;
    assign tileO_data[7]  = tileO_data_7;
    assign tileO_data[8]  = tileO_data_8;
    assign tileO_data[9]  = tileO_data_9;
    assign tileO_data[10] = tileO_data_10;
    assign tileO_data[11] = tileO_data_11;
    assign tileO_data[12] = tileO_data_12;
    assign tileO_data[13] = tileO_data_13;
    assign tileO_data[14] = tileO_data_14;
    assign tileO_data[15] = tileO_data_15;

    systolic systolic_inst (
        .clk(clk),
        .rst(rst),
        .tile_en(tile_en),
        // .tileA_data(tileA_data),
        .tileA_data_0(tileA_data_0),
        .tileA_data_1(tileA_data_1),
        .tileA_data_2(tileA_data_2),
        .tileA_data_3(tileA_data_3),
        // .tileB_data(tileB_data),
        .tileB_data_0(tileB_data_0),
        .tileB_data_1(tileB_data_1),
        .tileB_data_2(tileB_data_2),
        .tileB_data_3(tileB_data_3),
        // .tileO_data(tileO_data),
        .tileO_data_0(tileO_data_0),
        .tileO_data_1(tileO_data_1),
        .tileO_data_2(tileO_data_2),
        .tileO_data_3(tileO_data_3),
        .tileO_data_4(tileO_data_4),
        .tileO_data_5(tileO_data_5),
        .tileO_data_6(tileO_data_6),
        .tileO_data_7(tileO_data_7),
        .tileO_data_8(tileO_data_8),
        .tileO_data_9(tileO_data_9),
        .tileO_data_10(tileO_data_10),
        .tileO_data_11(tileO_data_11),
        .tileO_data_12(tileO_data_12),
        .tileO_data_13(tileO_data_13),
        .tileO_data_14(tileO_data_14),
        .tileO_data_15(tileO_data_15),
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


