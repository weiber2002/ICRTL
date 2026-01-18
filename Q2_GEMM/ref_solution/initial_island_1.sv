// no multi-dimensional arrays
module systolic (
    input clk, 
    input rst, 
    input tile_en,
    // input [15:0] tileA_data [0:3], 
    // input [15:0] tileB_data [0:3],
    input [15:0] tileA_data_0, 
    input [15:0] tileA_data_1,
    input [15:0] tileA_data_2,
    input [15:0] tileA_data_3,
    input [15:0] tileB_data_0,
    input [15:0] tileB_data_1,
    input [15:0] tileB_data_2,
    input [15:0] tileB_data_3,
    output reg   o_valid,
    // output reg [15:0] tileO_data [0:15]
    output reg [15:0] tileO_data_0, 
    output reg [15:0] tileO_data_1,
    output reg [15:0] tileO_data_2,
    output reg [15:0] tileO_data_3,
    output reg [15:0] tileO_data_4,
    output reg [15:0] tileO_data_5,
    output reg [15:0] tileO_data_6,
    output reg [15:0] tileO_data_7,
    output reg [15:0] tileO_data_8,
    output reg [15:0] tileO_data_9,
    output reg [15:0] tileO_data_10,
    output reg [15:0] tileO_data_11,
    output reg [15:0] tileO_data_12,
    output reg [15:0] tileO_data_13,
    output reg [15:0] tileO_data_14,
    output reg [15:0] tileO_data_15

);
    reg [15:0] tileA_data [0:3];
    reg [15:0] tileB_data [0:3];
    reg [15:0] tileO_data [0:15];
    assign tileA_data[0] = tileA_data_0;
    assign tileA_data[1] = tileA_data_1;
    assign tileA_data[2] = tileA_data_2;
    assign tileA_data[3] = tileA_data_3;
    assign tileB_data[0] = tileB_data_0;
    assign tileB_data[1] = tileB_data_1;
    assign tileB_data[2] = tileB_data_2;
    assign tileB_data[3] = tileB_data_3;
    assign tileO_data_0 = tileO_data[0];
    assign tileO_data_1 = tileO_data[1];
    assign tileO_data_2 = tileO_data[2];
    assign tileO_data_3 = tileO_data[3];
    assign tileO_data_4 = tileO_data[4];
    assign tileO_data_5 = tileO_data[5];
    assign tileO_data_6 = tileO_data[6];
    assign tileO_data_7 = tileO_data[7];
    assign tileO_data_8 = tileO_data[8];
    assign tileO_data_9 = tileO_data[9];
    assign tileO_data_10 = tileO_data[10];
    assign tileO_data_11 = tileO_data[11];
    assign tileO_data_12 = tileO_data[12];
    assign tileO_data_13 = tileO_data[13];
    assign tileO_data_14 = tileO_data[14];
    assign tileO_data_15 = tileO_data[15];
    // input buffers
    reg [15:0] tileA_w [0:27], tileA_r [0:27];
    reg [15:0] tileB_w [0:27], tileB_r [0:27];
    
    // state machine 
    // typedef enum logic [1:0] {
    //     LOADING, 
    //     COMPUTE,
    //     DONE
    // } state_t;
    localparam LOADING = 2'b00, COMPUTE = 2'b01, DONE = 2'b10;
    // state_t state_w, state_r;
    reg [1:0] state_w, state_r;

    reg [1:0] load_num_w, load_num_r;
    reg [4:0] propagate_num_w, propagate_num_r;

    always@(*) begin
        state_w = state_r;
        case (state_r)
            LOADING: begin
                if (tile_en && load_num_r == 3) begin
                    state_w = COMPUTE;
                end
            end
            COMPUTE: begin
                // Assuming some condition to go to DONE state
                if(propagate_num_r == 11) begin
                    state_w = DONE;
                end
            end
            DONE: begin
                state_w = LOADING; // Loop back to LOADING for next tile
            end
        endcase
    end

    // logic [15:0] next_a [0:3][0:3], next_b [0:3][0:3];
    reg [15:0] next_a [0:15], next_b [0:15];
    reg [15:0] tileA_in [0:3], tileB_in [0:3];
    reg PE_clear, PE_en, PE_out;
    wire  [15:0] o [0:15];
    wire PE_input_gate;
    assign PE_input_gate = (state_r == LOADING || state_r == COMPUTE) && PE_en;

    integer i;
    always@(*) begin
        for(i=0; i<16; i++) begin
            tileO_data[i] = o[i];
        end
    end    

    // systolic array 

    //                 tileB_in[0]  tileB_in[1] tileB_in[2] tileB_in[3]
    //  tileA_in[0]    PE00         PE01        PE02        PE03
    //  tileA_in[1]    PE10         PE11        PE12        PE13
    //  tileA_in[2]    PE20         PE21        PE22        PE23
    //  tileA_in[3]    PE30         PE31        PE32        PE33
    PE pe00 (
        .clk(clk),
        .rst(rst), 
        .PE_clear(PE_clear),
        .PE_en(PE_en),
        .PE_out(PE_out),
        .PE_input_gate(PE_input_gate),
        .a(tileA_in[0]), 
        .b(tileB_in[0]),
        .next_a(next_a[0]),
        .next_b(next_b[0]),
        .o(o[0])
    );
    PE pe01 (
        .clk(clk),
        .rst(rst), 
        .PE_clear(PE_clear),
        .PE_en(PE_en),
        .PE_out(PE_out),
        .PE_input_gate(PE_input_gate),
        .a(next_a[0]),
        .b(tileB_in[1]),
        .next_a(next_a[1]), 
        .next_b(next_b[1]),
        .o(o[1])
    );
    PE pe02 (
        .clk(clk),
        .rst(rst), 
        .PE_clear(PE_clear),
        .PE_en(PE_en),
        .PE_out(PE_out),
        .PE_input_gate(PE_input_gate),
        .a(next_a[1]),
        .b(tileB_in[2]),
        .next_a(next_a[2]),
        .next_b(next_b[2]),
        .o(o[2])
    );
    PE pe03 (
        .clk(clk),
        .rst(rst), 
        .PE_clear(PE_clear),
        .PE_en(PE_en),
        .PE_out(PE_out),
        .PE_input_gate(PE_input_gate),
        .a(next_a[2]),
        .b(tileB_in[3]),
        .next_a(),
        .next_b(next_b[3]),
        .o(o[3])
    );
    PE pe10 (
        .clk(clk),
        .rst(rst), 
        .PE_clear(PE_clear),
        .PE_en(PE_en),
        .PE_out(PE_out),
        .PE_input_gate(PE_input_gate),
        .a(tileA_in[1]), 
        .b(next_b[0]),
        .next_a(next_a[4]), 
        .next_b(next_b[4]),
        .o(o[4])
    );
    PE pe11 (
        .clk(clk),
        .rst(rst), 
        .PE_clear(PE_clear),
        .PE_en(PE_en),
        .PE_out(PE_out),
        .PE_input_gate(PE_input_gate),
        .a(next_a[4]),
        .b(next_b[1]),
        .next_a(next_a[5]),
        .next_b(next_b[5]),
        .o(o[5])
    );
    PE pe12 (
        .clk(clk),
        .rst(rst), 
        .PE_clear(PE_clear),
        .PE_en(PE_en),
        .PE_out(PE_out),
        .PE_input_gate(PE_input_gate),
        .a(next_a[5]),
        .b(next_b[2]),
        .next_a(next_a[6]),
        .next_b(next_b[6]),
        .o(o[6])
    );
    PE pe13 (
        .clk(clk),
        .rst(rst), 
        .PE_clear(PE_clear),
        .PE_en(PE_en),
        .PE_out(PE_out),
        .PE_input_gate(PE_input_gate),
        .a(next_a[6]), 
        .b(next_b[3]),
        .next_a(),
        .next_b(next_b[7]),
        .o(o[7])
    );
    PE pe20 (
        .clk(clk),
        .rst(rst), 
        .PE_clear(PE_clear),
        .PE_en(PE_en),
        .PE_out(PE_out),
        .PE_input_gate(PE_input_gate),
        .a(tileA_in[2]), 
        .b(next_b[4]),
        .next_a(next_a[8]),
        .next_b(next_b[8]),
        .o(o[8])
    );
    PE pe21 (
        .clk(clk),
        .rst(rst), 
        .PE_clear(PE_clear),
        .PE_en(PE_en),
        .PE_out(PE_out),
        .PE_input_gate(PE_input_gate),
        .a(next_a[8]),
        .b(next_b[5]),
        .next_a(next_a[9]),
        .next_b(next_b[9]),
        .o(o[9])
    );
    PE pe22 (
        .clk(clk),
        .rst(rst), 
        .PE_clear(PE_clear),
        .PE_en(PE_en),
        .PE_out(PE_out),
        .PE_input_gate(PE_input_gate),
        .a(next_a[9]), 
        .b(next_b[6]),
        .next_a(next_a[10]),
        .next_b(next_b[10]),
        .o(o[10])
    );
    PE pe23 (
        .clk(clk),
        .rst(rst), 
        .PE_clear(PE_clear),
        .PE_en(PE_en),
        .PE_out(PE_out),
        .PE_input_gate(PE_input_gate),
        .a(next_a[10]),
        .b(next_b[7]),
        .next_a(),
        .next_b(next_b[11]),
        .o(o[11])
    );
    PE pe30 (
        .clk(clk),
        .rst(rst), 
        .PE_clear(PE_clear),
        .PE_en(PE_en),
        .PE_out(PE_out),
        .PE_input_gate(PE_input_gate),
        .a(tileA_in[3]), 
        .b(next_b[8]),
        .next_a(next_a[12]),
        .next_b(),
        .o(o[12])
    );
    PE pe31 (
        .clk(clk),
        .rst(rst), 
        .PE_clear(PE_clear),
        .PE_en(PE_en),
        .PE_out(PE_out),
        .PE_input_gate(PE_input_gate),
        .a(next_a[12]), 
        .b(next_b[9]),
        .next_a(next_a[13]),
        .next_b(),
        .o(o[13])
    );
    PE pe32 (
        .clk(clk),
        .rst(rst), 
        .PE_clear(PE_clear),
        .PE_en(PE_en),
        .PE_out(PE_out),
        .PE_input_gate(PE_input_gate),
        .a(next_a[13]), 
        .b(next_b[10]),
        .next_a(next_a[14]),
        .next_b(),
        .o(o[14])
    );
    PE pe33 (
        .clk(clk),
        .rst(rst), 
        .PE_clear(PE_clear),
        .PE_en(PE_en),
        .PE_out(PE_out),
        .PE_input_gate(PE_input_gate),
        .a(next_a[14]), 
        .b(next_b[11]),
        .next_a(),
        .next_b(),
        .o(o[15])
    );



    always@(*) begin
        load_num_w = load_num_r;
        propagate_num_w = propagate_num_r;
        for(i=0; i<28; i++) begin
            tileA_w[i] = tileA_r[i];
            tileB_w[i] = tileB_r[i];
        end
        PE_clear = 0;
        PE_en = 0;
        PE_out = 0;
        o_valid = 0;
        for(i=0; i<4; i++) begin
            tileA_in[i] = 0;
            tileB_in[i] = 0;
        end
        case(state_r)
            LOADING: begin
                if(tile_en) begin
                    // tile
                    // 05 04 03 02 01 00
                    // 15 14 13 12 11 10
                    // 25 24 23 22 21 20
                    // 35 34 33 32 31 30
                    load_num_w = load_num_r + 1;
                    case(load_num_r)
                    0: begin
                        tileA_w[0] = tileA_data[0];
                        tileA_w[1] = tileA_data[1];
                        tileA_w[2] = tileA_data[2];
                        tileA_w[3] = tileA_data[3];
                        tileB_w[0] = tileB_data[0];
                        tileB_w[8] = tileB_data[1];
                        tileB_w[16] = tileB_data[2];
                        tileB_w[24] = tileB_data[3];
                    end
                    1: begin
                        tileA_w[8] = tileA_data[0];
                        tileA_w[9] = tileA_data[1];
                        tileA_w[10] = tileA_data[2];
                        tileA_w[11] = tileA_data[3];
                        tileB_w[1] = tileB_data[0];
                        tileB_w[9] = tileB_data[1];
                        tileB_w[17] = tileB_data[2];
                        tileB_w[25] = tileB_data[3];
                    end
                    2: begin
                        tileA_w[16] = tileA_data[0];
                        tileA_w[17] = tileA_data[1];
                        tileA_w[18] = tileA_data[2];
                        tileA_w[19] = tileA_data[3];
                        tileB_w[2] = tileB_data[0];
                        tileB_w[10] = tileB_data[1];
                        tileB_w[18] = tileB_data[2];
                        tileB_w[26] = tileB_data[3];
                    end
                    3: begin
                        load_num_w = 0;
                        tileA_w[24] = tileA_data[0];
                        tileA_w[25] = tileA_data[1];
                        tileA_w[26] = tileA_data[2];
                        tileA_w[27] = tileA_data[3];
                        tileB_w[3] = tileB_data[0];
                        tileB_w[11] = tileB_data[1];
                        tileB_w[19] = tileB_data[2];
                        tileB_w[27] = tileB_data[3];
                    end
                    endcase
                end
            end
            COMPUTE: begin
                propagate_num_w = propagate_num_r + 1;
                case(propagate_num_r)
                0,1,2,3,4,5,6: begin
                    for(i=0; i<4; i++) begin
                        tileA_in[i] = tileA_r[i * 7 + propagate_num_r];
                        tileB_in[i] = tileB_r[i * 7 + propagate_num_r];
                    end
                    PE_en = 1;
                end
                11: begin // last cycle
                    PE_en = 1;
                    propagate_num_w = 0; // Reset for next tile
                end                    
                default: begin
                    PE_en = 1;
                end
                endcase
            end
            DONE: begin
                PE_out  = 1;
                o_valid = 1;
                PE_clear = 1;
            end
        endcase
    end

    // systolic array 

    //                 tileB_in[0]  tileB_in[1] tileB_in[2] tileB_in[3]
    //  tileA_in[0]    PE00         PE01        PE02        PE03
    //  tileA_in[1]    PE10         PE11        PE12        PE13
    //  tileA_in[2]    PE20         PE21        PE22        PE23
    //  tileA_in[3]    PE30         PE31        PE32        PE33

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for(i = 0; i < 28; i++) begin
                tileA_r[i] <= 0;
                tileB_r[i] <= 0;
            end
        end
        else if(state_r == LOADING) begin
            // Load the tileA and tileB data
            for(i = 0; i < 28; i++) begin
                tileA_r[i] <= tileA_w[i];
                tileB_r[i] <= tileB_w[i];
            end
        end
    end
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            // Reset logic
            state_r <= LOADING;
            load_num_r <= 0;
            propagate_num_r <= 0;
        end else begin 
            // Write logic
            state_r <= state_w;
            load_num_r <= load_num_w;
            propagate_num_r <= propagate_num_w;
        end
    end


endmodule

module PE (
    input clk, 
    input rst, 
    input signed [15:0] a, 
    input signed [15:0] b, 
    input PE_clear, 
    input PE_en, 
    input PE_out,
    input PE_input_gate,
    output  signed [15:0] next_a, 
    output  signed [15:0] next_b,
    output reg  signed [15:0] o
);
    reg signed [35:0] o_w, o_r;
    reg signed [15:0] a_r, b_r, a_w, b_w;
    
    assign a_w = a;
    assign b_w = b;
    assign next_a = a_r;
    assign next_b = b_r;
    
    localparam signed [35:0] NEG_MAX = -(1<<30);
    localparam signed [35:0] POS_MAX = (1<<30) - 1;

    wire [14:0] o_r_upper;
    assign o_r_upper = o_r[29-:15]; // Extract the upper 15 bits of o_r
    
    always@(*) begin
        o = 0;
        if (PE_out) begin
            if(o_r > 0) begin
                if(o_r >= POS_MAX) begin // > 1
                    o = 16'h7FFF; // Saturate to max positive value
                end else begin
                    o = {1'b0, o_r_upper}; // Take the upper 15 bits and sign extend
                end
            end
            else begin
                if(o_r <= NEG_MAX) begin // < -1
                    o = 16'h8000; // Saturate to max negative value
                    
                end else begin
                    o = {1'b1, o_r_upper}; // Take the upper 15 bits and sign extend
                end
            end
        end
    end
    always@(*) begin
        o_w = o_r;
        if (PE_clear) begin
            o_w = 0;
        end else if (PE_en) begin
            o_w = o_r + a * b;
        end
    end
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            o_r <= 0;
        end
        else if(PE_en || PE_clear)begin 
            o_r <= o_w;
        end
    end
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            a_r <= 0;
            b_r <= 0;
        end
        else if(PE_input_gate) begin 
            a_r <= a_w;
            b_r <= b_w;
        end
    end

endmodule