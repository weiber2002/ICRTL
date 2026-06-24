module sqrt (
    input             clk,
    input             rst,
    input  [23:0]     sqrt_in,
    input             sqrt_in_valid,
    output reg [11:0] sqrt_out,
    output reg        sqrt_out_valid
);
    localparam W_IN = 24;
    localparam ITER = W_IN/2;          // 12

    localparam IDLE = 1'b0, CALC = 1'b1;
    reg state_r, state_w;

    reg  [W_IN+1:0] R_r, R_w;          // remainder
    reg  [11:0]     Q_r, Q_w;          // root (floor)
    reg  [W_IN-1:0] X_r, X_w;          // input shift reg
    reg  [4:0]      count_r, count_w;

    wire [1:0]       two_bits = X_r[W_IN-1 -: 2];
    wire [W_IN+1:0]  shift_R  = (R_r << 2) | two_bits;
    wire [12:0]      trial    = (Q_r << 2) | 1;

    // 本拍計算後的 Q 與 remainder
    reg  [11:0]      q_next;
    reg  [W_IN+1:0]  r_next;

    always @(*) begin
        state_w = state_r; R_w = R_r; Q_w = Q_r; X_w = X_r; count_w = count_r;
        sqrt_out = Q_r; sqrt_out_valid = 1'b0;
        q_next = Q_r; r_next = R_r;

        case (state_r)
            IDLE: begin
                if (sqrt_in_valid) begin
                    X_w = sqrt_in; R_w = 0; Q_w = 0; count_w = 0;
                    state_w = CALC;
                end
            end
            CALC: begin
                if (shift_R >= trial) begin
                    r_next = shift_R - trial;
                    q_next = (Q_r << 1) | 12'd1;
                end else begin
                    r_next = shift_R;
                    q_next = (Q_r << 1);
                end
                R_w = r_next;
                Q_w = q_next;
                X_w = X_r << 2;

                if (count_r == ITER-1) begin
                    state_w = IDLE;
                    count_w = 0;
                    sqrt_out = (r_next > q_next) ? (q_next + 12'd1) : q_next;
                    sqrt_out_valid = 1'b1;
                end else begin
                    count_w = count_r + 1;
                end
            end
        endcase
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state_r<=IDLE; R_r<=0; Q_r<=0; X_r<=0; count_r<=0;
        end else begin
            state_r<=state_w; R_r<=R_w; Q_r<=Q_w; X_r<=X_w; count_r<=count_w;
        end
    end
endmodule