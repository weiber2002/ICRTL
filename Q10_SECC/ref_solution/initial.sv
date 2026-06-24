module SET ( clk , rst, en, central, radius, mode, busy, valid, candidate );

    input clk, rst;
    input en;
    input [23:0] central;
    input [11:0] radius;
    input [1:0] mode;
    output reg busy;
    output reg valid;
    output reg [7:0] candidate;


    typedef enum logic [2:0] { IDLE, CALC, DONE } state_t;
    state_t state_w, state_r;

    logic [3:0] Ax_w, Ax_r, Bx_w, Bx_r, Cx_w, Cx_r, Ay_w, Ay_r, By_w, By_r, Cy_w, Cy_r;
    logic [3:0] Ar_w, Ar_r, Br_w, Br_r, Cr_w, Cr_r;
    logic [1:0] mode_w, mode_r;

    logic [6:0] count_w, count_r;
    logic [3:0] x_coor_w, x_coor_r, y_coor_w, y_coor_r;

    logic [10:0] abc, abc2, abc3;
    logic [10:0] r2, r22, r222;
    logic cmp1, cmp2, cmp3;

    assign abc = abs(Ax_r, x_coor_r) * abs(Ax_r, x_coor_r) + abs(Ay_r, y_coor_r) * abs(Ay_r, y_coor_r);
    assign abc2 = abs(Bx_r, x_coor_r) * abs(Bx_r, x_coor_r) + abs(By_r, y_coor_r) * abs(By_r, y_coor_r);
    assign abc3 = abs(Cx_r, x_coor_r) * abs(Cx_r, x_coor_r) + abs(Cy_r, y_coor_r) * abs(Cy_r, y_coor_r);
    assign r2  = Ar_r * Ar_r;
    assign r22 = Br_r * Br_r;
    assign r222 = Cr_r * Cr_r;
    assign cmp1 = (abc <= r2);
    assign cmp2 = (abc2 <= r22);
    assign cmp3 = (abc3 <= r222);

    // mode 2 stage
    logic [2:0] stage_w, stage_r;

    always@(*) begin
        state_w = state_r;
        busy = 1;
        valid = 0;
        candidate = 0;

        Ax_w = Ax_r; Ay_w = Ay_r; Ar_w = Ar_r;
        Bx_w = Bx_r; By_w = By_r; Br_w = Br_r;
        Cx_w = Cx_r; Cy_w = Cy_r; Cr_w = Cr_r;
        mode_w = mode_r;

        count_w = count_r;
        x_coor_w = x_coor_r; y_coor_w = y_coor_r;

        stage_w = stage_r;

        case(state_r)
            IDLE: begin
                busy = 0;
                if(en) begin
                    state_w = CALC;
                    Ax_w = central[23:20]; Ay_w = central[19:16]; Ar_w = radius[11:8];
                    Bx_w = central[15:12]; By_w = central[11: 8]; Br_w = radius[7:4];
                    Cx_w = central[7 : 4]; Cy_w = central[3 : 0]; Cr_w = radius[3:0];
                    mode_w = mode;
                    case(mode)
                        0, 2: begin
                            x_coor_w = start(Ax_w, Ar_w); y_coor_w = start(Ay_w, Ar_w);
                        end
                        1: begin
                            if(Ar_w > Br_w) begin
                                x_coor_w = start(Bx_w, Br_w); y_coor_w = start(By_w, Br_w);
                            end else begin
                                x_coor_w = start(Ax_w, Ar_w); y_coor_w = start(Ay_w, Ar_w);
                            end
                        end
                        3: begin
                            x_coor_w = 1; y_coor_w = 1;
                        end
                    endcase
                end
            end
            CALC: begin
                if(mode_r == 0 || (mode_r == 2 && stage_r == 0)) begin
                    x_coor_w = x_coor_r + 1;
                    if(x_coor_r == finish(Ax_r, Ar_r)) begin
                        x_coor_w = start(Ax_r, Ar_r);
                        y_coor_w = y_coor_r + 1;
                        if(y_coor_r == finish(Ay_r, Ar_r)) begin
                            state_w = DONE;
                            if(mode_r == 2) begin
                                stage_w = 1;
                                state_w = CALC;
                                x_coor_w = start(Bx_r, Br_r);
                                y_coor_w = start(By_r, Br_r);
                            end
                        end
                    end               

                    if(cmp1) count_w = count_r + 1;
                end
                else if(mode_r == 1 || (mode_r == 2 && stage_r == 2)) begin
                    x_coor_w = x_coor_r + 1;
                    if((Ar_r > Br_r && x_coor_r == finish(Bx_r, Br_r)) || (Ar_r <= Br_r && x_coor_r == finish(Ax_r, Ar_r))) begin
                        x_coor_w = (Ar_r > Br_r) ? start(Bx_r, Br_r) : start(Ax_r, Ar_r);
                        y_coor_w = y_coor_r + 1;
                        if((Ar_r > Br_r && y_coor_r == finish(By_r, Br_r)) || (Ar_r <= Br_r && y_coor_r == finish(Ay_r, Ar_r))) begin
                            state_w = DONE;
                        end
                    end
                    if( cmp1 && cmp2) begin
                        if(mode_r == 1) count_w = count_r + 1;
                        else if(mode_r == 2) count_w = count_r - 2;
                    end
                end
                else if(mode_r == 2 && stage_r == 1) begin
                    x_coor_w = x_coor_r + 1;
                    if(x_coor_r == finish(Bx_r, Br_r)) begin
                        x_coor_w = start(Bx_r, Br_r);
                        y_coor_w = y_coor_r + 1;
                        if(y_coor_r == finish(By_r, Br_r)) begin
                            stage_w = 2;
                            state_w = CALC;
                            if(Ar_r > Br_r) begin
                                x_coor_w = start(Bx_r, Br_r); y_coor_w = start(By_r, Br_r);
                            end else begin
                                x_coor_w = start(Ax_r, Ar_r); y_coor_w = start(Ay_r, Ar_r);
                            end
                        end
                    end               
                    if(cmp2) count_w = count_r + 1;
                end
                else if(mode_r == 3) begin
                    x_coor_w = x_coor_r + 1;
                    if(x_coor_r == 8) begin
                        x_coor_w = 1;
                        y_coor_w = y_coor_r + 1;
                        if(y_coor_r == 8) begin
                            state_w = DONE;
                        end
                    end
                    if(cmp1 && cmp2 && !cmp3) count_w = count_r + 1;
                    else if(cmp1 && !cmp2 && cmp3) count_w = count_r + 1;
                    else if(!cmp1 && cmp2 && cmp3) count_w = count_r + 1;
                end
            end
            DONE: begin
                state_w = IDLE;
                valid = 1;
                candidate = count_r; 
                count_w = 0;
                stage_w = 0;
            end
        endcase
    end

    function automatic [3:0] abs;
        input [3:0] a, b;
        begin
            if( a > b) abs = a - b;
            else abs = b - a;
        end
    endfunction
    
    function automatic [3:0] start;
        input [3:0] a, r;
        reg signed [4:0] diff;  // 5-bit，足夠容納 a-r 最大值 15 和最小值 -15
        begin
            diff = a - r;
            if(diff > 1) start = diff;
            else start = 1;
        end
    endfunction

    function automatic [3:0] finish;
        input [3:0] a, r;
        reg [4:0] sum;  // 5-bit，足夠容納 a+r 最大值 30
        begin
            sum = a + r;
            if( sum > 8) finish = 8;
            else finish = sum[3:0];
        end
    endfunction

    always@(posedge clk or posedge rst) begin
        if(rst) begin
            state_r <= IDLE;
            Ax_r <= 0; Ay_r <= 0; Ar_r <= 0;
            Bx_r <= 0; By_r <= 0; Br_r <= 0;
            Cx_r <= 0; Cy_r <= 0; Cr_r <= 0;
            mode_r <= 0;
            count_r <= 0;
            x_coor_r <= 1; y_coor_r <= 1;
            stage_r <= 0;
        end else begin
            state_r <= state_w;
            Ax_r <= Ax_w; Ay_r <= Ay_w; Ar_r <= Ar_w;
            Bx_r <= Bx_w; By_r <= By_w; Br_r <= Br_w;
            Cx_r <= Cx_w; Cy_r <= Cy_w; Cr_r <= Cr_w;
            mode_r <= mode_w;
            count_r <= count_w;
            x_coor_r <= x_coor_w; y_coor_r <= y_coor_w;
            stage_r <= stage_w;
        end
    end
endmodule


