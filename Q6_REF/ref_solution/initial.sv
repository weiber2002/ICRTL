module TOP(
    input  wire        CLK,
    input  wire        RST,
    input  wire [3:0]  RI,   
    output reg  [8:0]  SRAM_A,
    output reg  [15:0] SRAM_D,
    input  wire [15:0] SRAM_Q,   // unused
    output reg         SRAM_WE,
    output reg         DONE
);
    
    typedef enum logic [2:0] {IDLE, CONST, SQRT, CONST_2, DIV, OUTPUT, FINISH} state_t;
    state_t state_r, state_w;

    reg [3:0]  x_r, x_w;
    reg [3:0]  y_r, y_w;
    reg [3:0]  RI_r, RI_w;
    
    reg [3:0]  x_abs_r, x_abs_w;
    reg [3:0]  y_abs_r, y_abs_w;
    reg        sX_r, sX_w;
    reg        sY_r, sY_w;

    reg [21:0] X7_r, X7_w;
    reg [21:0] Y7_r, Y7_w;
    reg [24:0] X8_r, X8_w;
    reg [24:0] Y8_r, Y8_w;
    reg [42:0] X14_r, X14_w;
    reg [42:0] Y14_r, Y14_w;

    wire [51:0] sqrt_temp;
    assign sqrt_temp = (X14_r + Y14_r + {1'b1, 40'd0}) * (RI_r*RI_r - 1) + {1'b1, 40'd0};
    reg sqrt_valid_r, sqrt_valid_w;
    wire [25:0] sqrt_out;
    wire        sqrt_out_valid;
    // Dsqrt = sqrt( (X^14+Y^14+2^40)·(RI^2-1) + 2^40 )             - 26 bits unsigned

    sqrt sqrt_inst (
        .clk            (CLK),
        .rst            (RST),
        .sqrt_in        (sqrt_temp),
        .sqrt_in_valid  (sqrt_valid_r),
        .sqrt_out       (sqrt_out),
        .sqrt_out_valid (sqrt_out_valid)
    );

    reg [25:0] B_r, B_w;
    reg [45:0] C_r, C_w;
    reg [45:0] D_r, D_w;

    reg [71:0] BC_temp;


    reg [93:0] x_div_abc_r, x_div_abc_w, y_div_abc_r, y_div_abc_w;
    reg [45:0] div_d_r, div_d_w;
    reg        div_in_valid_r, div_in_valid_w;
    wire [15:0] x_div_out, y_div_out;
    wire        div_out_valid;
    reg [15:0]  y_delay_r, y_delay_w; // delay y_div_out by 1 cycle to match SRAM_D assignment

    divider_optics x_div_inst (
        .clk            (CLK),
        .rst            (RST),
        .div_abc        (x_div_abc_r),
        .div_d          (div_d_r),
        .div_in_valid   (div_in_valid_r),
        .div_out        (x_div_out),
        .div_out_valid  (div_out_valid)
    );

    divider_optics y_div_inst (
        .clk            (CLK),
        .rst            (RST),
        .div_abc        (y_div_abc_r),
        .div_d          (div_d_r),
        .div_in_valid   (div_in_valid_r),
        .div_out        (y_div_out),
        .div_out_valid  (y_div_out_valid)
    );

    always@(*) begin
        state_w = state_r;
        x_w = x_r;
        y_w = y_r;
        RI_w = RI_r;
        sqrt_valid_w = 0;
        x_abs_w = x_abs_r;
        y_abs_w = y_abs_r;
        sX_w = sX_r;
        sY_w = sY_r;
        X7_w = X7_r;
        Y7_w = Y7_r;
        X8_w = X8_r;
        Y8_w = Y8_r;
        X14_w = X14_r;
        Y14_w = Y14_r;
        B_w = B_r;
        C_w = C_r;
        D_w = D_r;
        x_div_abc_w = x_div_abc_r;
        y_div_abc_w = y_div_abc_r;
        div_d_w = div_d_r;
        div_in_valid_w = 0;
        y_delay_w = y_delay_r;
        SRAM_A = 9'd0;
        SRAM_D = 16'd0;
        SRAM_WE = 0;
        DONE = 0;

        
        case(state_r)
            IDLE: begin
                RI_w = RI;
                state_w = CONST;
                x_abs_w = x_r <= 8 ? 8 - x_r : x_r - 8;
                y_abs_w = y_r <= 8 ? 8 - y_r : y_r - 8;
                sX_w = x_r <= 8 ? 1'b1 : 1'b0;
                sY_w = y_r <= 8 ? 1'b1 : 1'b0;

                X7_w = x_abs_w * x_abs_w; // temporarily store x^2 in X7
                Y7_w = y_abs_w * y_abs_w;
                X8_w = X7_w * X7_w; // temporarily store x^4 in X8
                Y8_w = Y7_w * Y7_w;
                X14_w = x_abs_w * X7_w; // temporarily store x^3 in X14
                Y14_w = y_abs_w * Y7_w;
            end
            CONST: begin
                state_w = SQRT;
                X7_w = X14_r * X8_r; // x^7 = x^3 * x^4
                Y7_w = Y14_r * Y8_r;
                X8_w = X8_r * X8_r;  // x^8 = (x^4)^2
                Y8_w = Y8_r * Y8_r;
                X14_w = X7_w * X7_w; // x^14 = (x^7)^2
                Y14_w = Y7_w * Y7_w;
                
                sqrt_valid_w = 1'b1;
            end
            SQRT: begin
               if (sqrt_out_valid) begin
                    state_w = CONST_2;
                    B_w = 3 * (1 << 24) - X8_r - Y8_r; // B = 3*2^24 - X^8 - Y^8
                    C_w = (1 << 20) * sqrt_out - (1 << 40); // C = 2^20 * Dsqrt - 2^40
                    D_w = (1 << 20) * sqrt_out + X14_r + Y14_r; // D = 2^20 * Dsqrt + X^14 + Y^14
                end
            end
            CONST_2: begin
                state_w = DIV;
                BC_temp = B_r * C_r; // B*C
                x_div_abc_w = X7_r * BC_temp; // ABC = X^7 * B * C
                y_div_abc_w = Y7_r * BC_temp; // ABC = Y^7 * B * C
                div_d_w = D_r; // D
                div_in_valid_w = 1'b1; // start division
            end    
            DIV : begin
                if (div_out_valid) begin
                    state_w = OUTPUT;
                    SRAM_D = (x_r << 12) + (sX_r ? x_div_out : -x_div_out);  // zx = x - (X^7 * B * C) / (2^43 * D)
                    SRAM_A = 2*(16*y_r + x_r);
                    SRAM_WE = 1'b1; // write enable
                    y_delay_w = y_div_out; // delay y_div_out by 1 cycle to match SRAM_D assignment
                end
            end
            OUTPUT: begin
                state_w = IDLE;
                SRAM_D = (y_r << 12) + (sY_r ? y_delay_r : -y_delay_r); // zy = y - (Y^7 * B * C) / (2^43 * D)
                SRAM_A = 2*(16*y_r + x_r) + 1;
                SRAM_WE = 1'b1; // write enable

                x_w = x_r == 4'd15 ? 4'd0 : x_r + 4'd1; // increment x
                y_w = x_r == 4'd15 ? (y_r == 4'd15 ? 4'd0 : y_r + 4'd1) : y_r; // increment y if x wraps around
                if (x_r == 4'd15 && y_r == 4'd15) begin
                    DONE = 1'b0; // done when x and y both reach 15
                    state_w = FINISH; // transition to FINISH state
                end else begin
                    DONE = 1'b0;
                end
            end
            FINISH: begin
                DONE = 1'b1; // stay in DONE state
            end
        endcase
    end

    always @(posedge CLK or posedge RST) begin
        if (RST) begin
            state_r <= IDLE;
            x_r <= 4'd0;
            y_r <= 4'd0;
            RI_r <= 4'd0;
            x_abs_r <= 4'd0;
            y_abs_r <= 4'd0;
            sX_r <= 1'b0;
            sY_r <= 1'b0;
            X7_r <= 22'd0;
            Y7_r <= 22'd0;
            X8_r <= 25'd0;
            Y8_r <= 25'd0;
            X14_r <= 43'd0;
            Y14_r <= 43'd0;
            sqrt_valid_r <= 1'b0;
            B_r <= 26'd0;
            C_r <= 46'd0;
            D_r <= 46'd0;
            x_div_abc_r <= 94'd0;
            y_div_abc_r <= 94'd0;
            div_d_r <= 46'd0;
            div_in_valid_r <= 1'b0;
            y_delay_r <= 16'd0; 
        end else begin
            state_r <= state_w;
            x_r <= x_w;
            y_r <= y_w;
            RI_r <= RI_w;
            x_abs_r <= x_abs_w;
            y_abs_r <= y_abs_w;
            sX_r <= sX_w;
            sY_r <= sY_w;
            X7_r <= X7_w;
            Y7_r <= Y7_w;
            X8_r <= X8_w;
            Y8_r <= Y8_w;
            X14_r <= X14_w;
            Y14_r <= Y14_w;
            sqrt_valid_r <= sqrt_valid_w;
            B_r <= B_w;
            C_r <= C_w;
            D_r <= D_w;
            x_div_abc_r <= x_div_abc_w;
            y_div_abc_r <= y_div_abc_w;
            div_d_r <= div_d_w;
            div_in_valid_r <= div_in_valid_w;
            y_delay_r <= y_delay_w;
        end
    end

endmodule


// =====================================================================
//  calculate zx, zy
//  input:   x, y  (0..15, 4-bit unsigned)
//           RI    (2..15)
//  output:  zx, zy  (Q4.12 signed, 16-bit)
//
//  zx = x - (X^7 · B · C) / (2^43 · D)
//  zy = y - (Y^7 · B · C) / (2^43 · D)
//    X = x-8, Y = y-8
//    B = 3·2^24 - X^8 - Y^8          >0 恆正  (因 8^8 = 2^24)
//    C = 2^20·Dsqrt - 2^40           >0 恆正  (因 Dsqrt >= 2^21)
//    D = 2^20·Dsqrt + X^14 + Y^14    >0 恆正
//    Dsqrt = sqrt( (X^14+Y^14+2^40)·(RI^2-1) + 2^40 )
//
// =====================================================================
// elements for B, C, D
// x_abs_r = abs(x-8), y_abs_r = abs(y-8) - 4 bits
// sx_r = sign(x-8), sy_r = sign(y-8)     - 1 bit
// X7_r = x^7, Y7_r = y^7                 - 22 bits
// X8_r = x^8, Y8_r = y^8                 - 25 bits
// X14_r = x^14, Y14_r = y^14             - 43 bits   
//    zx = x - (X^7 · B · C) / (2^43 · D)
//    zy = y - (Y^7 · B · C) / (2^43 · D)
//    X = x-8, Y = y-8
//    B = 3·2^24 - X^8 - Y^8          >0   (8^8 = 2^24)     - 26 bits unsigned
//    C = 2^20·Dsqrt - 2^40           >0   (Dsqrt >= 2^21)  - 46 bits unsigned
//    D = 2^20·Dsqrt + X^14 + Y^14    >0                    - 46 bits unsigned
//    Dsqrt = sqrt( (X^14+Y^14+2^40)·(RI^2-1) + 2^40 )      - 25 bits unsigned

// Fixed-point divider for the optics datapath.
//
// Computes  Q4.12 of   ABC / (2^43 * D)
//   = floor( ABC * 2^12 / (2^43 * D) )
//   = floor( ABC / (2^31 * D) )
//   = floor( (ABC >> 31) / D )        <-- Method A
//
// Inputs:
//   div_abc : 94-bit  (product A*B*C, A=22b * B=26b * C=46b)
//   div_d   : 46-bit  (divisor D)
// Output:
//   div_out : 16-bit  Q4.12  ( = low 16 bits of floor((ABC>>31)/D) )
//



// ===== bundled module: sqrt (from sqrt.v) =====

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

// ===== bundled module: div (from div.v) =====
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