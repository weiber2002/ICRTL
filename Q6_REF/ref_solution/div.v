// Fixed-point divider for the optics datapath -- RADIX-8 (3 bits/cycle).
//
// Computes  Q4.12 of   ABC / (2^43 * D)  =  floor( (ABC >> 31) / D )
//
// Inputs:
//   div_abc : 94-bit  (A*B*C)
//   div_d   : 46-bit  (D)
// Output:
//   div_out : 16-bit  Q4.12  = low 16 bits of floor((ABC>>31)/D)
//
// Dividend (ABC>>31) is exactly 63 bits = 21*3, no padding needed.
// 63/3 = 21 iterations. Each consumes 3 dividend bits and emits one octal
// quotient digit by trial-subtracting the largest k*D (k in 1..7).
module divider_optics (
    input             clk,
    input             rst,
    input  [93:0]     div_abc,
    input  [45:0]     div_d,
    input             div_in_valid,
    output reg [15:0] div_out,        // Q4.12
    output reg        div_out_valid
);

    localparam DVD_W = 63;            // dividend width (= 21*3)
    localparam NITER = DVD_W/3;       // 21 iterations
    localparam QW    = 16;            // Q4.12
    localparam RW    = 50;            // remainder width (49 needed + 1 guard)

    localparam IDLE = 1'b0,
               CALC = 1'b1;
    reg state_r, state_w;

    reg  [DVD_W-1:0] dvd_r, dvd_w;    // 63-bit dividend
    reg  [RW-1:0]    R_r, R_w;        // partial remainder
    reg  [DVD_W-1:0] Q_r, Q_w;        // quotient (low 16 used)
    reg  [45:0]      D_r, D_w;        // latched divisor
    reg  [4:0]       count_r, count_w;// 0..20

    // current 3-bit group, MSB-first.  group index = NITER-1-count
    wire [4:0] grp_idx = (NITER-1) - count_r;             // 0..20
    wire [2:0] grp     = dvd_r[ (grp_idx*3) +: 3 ];       // dvd_r[3*idx +: 3]

    wire [RW-1:0] R_shift = (R_r << 3) | grp;

    // multiples k*D, k=1..7  (k*D up to 49 bits)
    wire [RW-1:0] D1 = {4'd0, D_r};
    wire [RW-1:0] D2 = D1 << 1;
    wire [RW-1:0] D3 = D2 + D1;
    wire [RW-1:0] D4 = D2 << 1;
    wire [RW-1:0] D5 = D4 + D1;
    wire [RW-1:0] D6 = D3 << 1;
    wire [RW-1:0] D7 = D6 + D1;

    reg  [2:0]    q_digit;
    reg  [RW-1:0] R_next;
    always @(*) begin
        if      (R_shift >= D7) begin q_digit = 3'd7; R_next = R_shift - D7; end
        else if (R_shift >= D6) begin q_digit = 3'd6; R_next = R_shift - D6; end
        else if (R_shift >= D5) begin q_digit = 3'd5; R_next = R_shift - D5; end
        else if (R_shift >= D4) begin q_digit = 3'd4; R_next = R_shift - D4; end
        else if (R_shift >= D3) begin q_digit = 3'd3; R_next = R_shift - D3; end
        else if (R_shift >= D2) begin q_digit = 3'd2; R_next = R_shift - D2; end
        else if (R_shift >= D1) begin q_digit = 3'd1; R_next = R_shift - D1; end
        else                    begin q_digit = 3'd0; R_next = R_shift;      end
    end

    always @(*) begin
        state_w       = state_r;
        dvd_w         = dvd_r;
        R_w           = R_r;
        Q_w           = Q_r;
        D_w           = D_r;
        count_w       = count_r;
        div_out       = Q_r[QW-1:0];
        div_out_valid = 1'b0;

        case (state_r)
            IDLE: begin
                if (div_in_valid) begin
                    dvd_w   = div_abc[93:31];   // ABC >> 31 (63 bits)
                    D_w     = div_d;
                    R_w     = {RW{1'b0}};
                    Q_w     = {DVD_W{1'b0}};
                    count_w = 5'd0;
                    state_w = CALC;
                end
            end

            CALC: begin
                R_w = R_next;
                Q_w = (Q_r << 3) | {{(DVD_W-3){1'b0}}, q_digit};

                if (count_r == NITER-1) begin
                    state_w       = IDLE;
                    count_w       = 5'd0;
                    div_out       = ((Q_r << 3) | {{(DVD_W-3){1'b0}}, q_digit}) & {QW{1'b1}};
                    div_out_valid = 1'b1;
                end else begin
                    count_w = count_r + 5'd1;
                end
            end
        endcase
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state_r <= IDLE;
            dvd_r   <= {DVD_W{1'b0}};
            R_r     <= {RW{1'b0}};
            Q_r     <= {DVD_W{1'b0}};
            D_r     <= 46'd0;
            count_r <= 5'd0;
        end else begin
            state_r <= state_w;
            dvd_r   <= dvd_w;
            R_r     <= R_w;
            Q_r     <= Q_w;
            D_r     <= D_w;
            count_r <= count_w;
        end
    end

endmodule