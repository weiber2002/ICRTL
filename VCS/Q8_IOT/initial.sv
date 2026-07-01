`timescale 1ns/10ps
module TOP( clk, rst, in_en, iot_in, fn_sel, busy, valid, iot_out);
    input          clk;
    input          rst;
    input          in_en;
    input  [7:0]   iot_in;
    input  [2:0]   fn_sel;
    output  reg    busy;
    output  reg    valid;
    output  reg [127:0] iot_out;

    // busy low, get new data at the next clock cycle

    typedef enum logic [1:0] { IDLE, INPUT, OUTPUT } state_t;
    state_t state_w, state_r;

    logic [3:0] num_count_w, num_count_r;
    logic [3:0] in_count_w, in_count_r;
    logic [1:0] first_count_w, first_count_r;
    logic [127-8:0] in_w, in_r;

    // F1 MAX, MIN
    logic [130:0] num_r, num_w;
    logic [127:0] num_temp;

    wire bigger, smaller;
    assign bigger = (num_temp > num_r) ? 1 : 0;
    assign smaller = (num_temp < num_r) ? 1 : 0;

    // F4
    localparam low_bound = 128'h6FFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF;
    localparam high_bound = 128'hAFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF;

    //F5
    localparam low_bound_f5 = 128'h7FFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF;
    localparam high_bound_f5 = 128'hBFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF;


    always@(*) begin
        state_w = state_r;
        busy = 1;
        num_count_w = num_count_r;
        in_count_w = in_count_r;
        first_count_w = first_count_r;
        in_w = in_r;
        num_w = num_r;
        num_temp = 0;
        valid = 0;
        iot_out = 0;
        case(state_r)
            IDLE: begin
                busy = 0;
                state_w = INPUT;
                if(fn_sel == 7) num_w = 128'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF;
            end
            INPUT: begin
                busy = 0;
                if(in_en) begin
                    in_count_w = in_count_r + 1;
                    in_w = {in_r, iot_in};
                    if(in_count_r == 15) begin
                        num_count_w = num_count_r + 1;
                        if(num_count_r == 7 && (fn_sel != 4) && (fn_sel != 5) && (fn_sel != 6) && (fn_sel != 7)) begin
                            busy = 1;
                            state_w = OUTPUT;
                            num_count_w = 0;
                        end
                        num_temp = {in_r, iot_in};
                        case(fn_sel)
                            1: begin
                                if(num_count_r == 0) num_w = num_temp;
                                else if(bigger) num_w = num_temp;
                                else num_w = num_r;
                            end
                            2: begin
                                if(num_count_r == 0) num_w = num_temp;
                                else if(smaller) num_w = num_temp;
                                else num_w = num_r;
                            end
                            3: begin
                                num_w = num_r + num_temp;
                            end
                            4: begin
                                if(num_temp > low_bound && num_temp < high_bound) begin
                                    valid = 1;
                                    iot_out = num_temp;
                                end
                            end
                            5: begin
                                if(num_temp < low_bound_f5 || num_temp > high_bound_f5) begin
                                    valid = 1;
                                    iot_out = num_temp;
                                end
                            end
                            6: begin
                                if(num_count_r == 7) begin
                                    num_count_w = 0;   
                                    first_count_w = 2; 
                                    if(bigger) begin
                                        valid = 1; iot_out = num_temp; num_w = num_temp;             
                                    end
                                    else if(first_count_r == 0 || first_count_r == 3) begin
                                        valid = 1; iot_out = num_r;
                                    end
                                end
                                else begin
                                    if(bigger) begin
                                        num_w = num_temp;
                                        first_count_w = 3;
                                    end
                                end
                            end
                            7: begin
                               if(num_count_r == 7) begin
                                    num_count_w = 0;   
                                    first_count_w = 2; 
                                    if(smaller) begin
                                        valid = 1; iot_out = num_temp; num_w = num_temp;            
                                    end
                                    else if(first_count_r == 0 || first_count_r == 3) begin
                                        valid = 1; iot_out = num_r;
                                    end
                                end
                                else begin
                                    if(smaller) begin
                                        num_w = num_temp;
                                        first_count_w = 3;
                                    end
                                end
                            end
                        endcase
                    end
                end
            end
            OUTPUT: begin
                valid = 1;
                iot_out = num_r;
                case(fn_sel)
                    1, 2: iot_out = num_r;
                    3: iot_out = num_r >> 3;
                endcase
                num_w = 0;
                state_w = IDLE;
            end
        endcase
    end

    always@(posedge clk or posedge rst) begin
        if(rst) begin
            state_r <= IDLE;
            num_count_r <= 0;
            in_count_r <= 0;
            first_count_r <= 0;
            in_r <= 0;
            num_r <= 0;
        end
        else begin
            state_r <= state_w;
            num_count_r <= num_count_w;
            in_count_r <= in_count_w;
            first_count_r <= first_count_w;
            in_r <= in_w;
            num_r <= num_w;
        end
    end
endmodule
