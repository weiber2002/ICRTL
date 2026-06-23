
module sqrt (
    input             clk,
    input             rst,
    input  [51:0]     sqrt_in,
    input             sqrt_in_valid,
    output reg [25:0] sqrt_out,
    output reg        sqrt_out_valid
);


// function ISQRT(N, W):
//     R = 0                      // (remainder)
//     Q = 0                      // (root)
//     X = N                      // (shift register for input)
//     ITER = W / 2               // number of iterations (W is the bit width of N)

//     for i in 0 .. ITER-1:
//         two_bits = top 2 bits of X    
//         X = X << 2                       

//         R = (R << 2) | two_bits         
//         trial = (Q << 2) | 1        

//         if R >= trial:
//             R = R - trial
//             Q = (Q << 1) | 1       
//         else:
//             Q = (Q << 1)        
//     return Q, R

// optimize by ignorong last 13 bits


    localparam W_IN = 52;
    localparam ITER = W_IN/2;          // 26
    localparam EARLY_STOP = 13;        // 26 - 13 = 13 bits of precision


    localparam IDLE = 1'b0,
               CALC = 1'b1;
    reg state_r, state_w;

    // R needs W_IN+2 bits to hold (R<<2)|two_bits during the last steps.
    reg  [W_IN+1:0] R_r, R_w;          // 52 bits
    reg  [25:0]     Q_r, Q_w;          // result
    reg  [W_IN-1:0] X_r, X_w;          // input shift register
    reg  [5:0]      count_r, count_w;  // 0..25

    // top two bits of the remaining input
    wire [1:0]      two_bits;
    wire [W_IN+1:0] shift_R;
    wire [26:0]     trial;
    assign two_bits = X_r[W_IN-1 -: 2];
    assign shift_R  = (R_r << 2) | two_bits;
    assign trial    = (Q_r << 2) | 1;

    reg [25:0] early_stop_temp;

    always @(*) begin
        // defaults: hold
        state_w        = state_r;
        R_w            = R_r;
        Q_w            = Q_r;
        X_w            = X_r;
        count_w        = count_r;
        sqrt_out       = Q_r;
        sqrt_out_valid = 1'b0;

        early_stop_temp = 0;

        case (state_r)
            IDLE: begin
                if (sqrt_in_valid) begin
                    X_w     = sqrt_in;
                    R_w     = {(W_IN+2){1'b0}};
                    Q_w     = 26'd0;
                    count_w = 6'd0;
                    state_w = CALC;
                end
            end

            CALC: begin
                if (shift_R >= {2'd0, trial}) begin
                    R_w = shift_R - {26'd0, trial};
                    Q_w = (Q_r << 1) | 26'd1;
                end else begin
                    R_w = shift_R;
                    Q_w = (Q_r << 1);
                end
                X_w = X_r << 2;        

                if (count_r == ITER-1-EARLY_STOP) begin     // 25th iteration (0..24)
                    
                    state_w        = IDLE;
                    count_w        = 6'd0;
                    early_stop_temp = (shift_R >= {2'd0, trial}) ? (Q_r << 1) | 26'd1 : (Q_r << 1);
                    sqrt_out        = early_stop_temp << EARLY_STOP;  // shift left to fill the lower bits with zero
                    sqrt_out_valid = 1'b1;
                end else begin
                    count_w = count_r + 6'd1;
                end
            end
        endcase
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state_r <= IDLE;
            R_r     <= {(W_IN+2){1'b0}};
            Q_r     <= 26'd0;
            X_r     <= {W_IN{1'b0}};
            count_r <= 6'd0;
        end else begin
            state_r <= state_w;
            R_r     <= R_w;
            Q_r     <= Q_w;
            X_r     <= X_w;
            count_r <= count_w;
        end
    end

endmodule