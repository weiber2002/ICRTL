module geofence (clk, reset, X, Y, R, valid, is_inside);
    input clk;
    input reset;
    input [9:0] X;
    input [9:0] Y;
    input [10:0] R;
    output reg valid;
    output reg is_inside;

    reg [9:0]  X_w [0:5], X_r [0:5], Y_w [0:5], Y_r [0:5];
    reg [10:0] R_w [0:5], R_r [0:5];

    typedef enum logic [3:0] {
        IDLE, INPUT, SORT,
        POLY,
        EDGE_REQ, EDGE_WAIT,
        HERON_REQ1, HERON_WAIT1,
        HERON_REQ2, HERON_WAIT2,
        TRI_ACC,
        OUTPUT
    } state_t;
    state_t state_r, state_w;

    reg [2:0] in_count_r, in_count_w;
    reg [2:0] sort_count_r, sort_count_w;
    reg [2:0] sort_loop_count_r, sort_loop_count_w;
    reg cmp;

    reg [2:0]  cal_count_r, cal_count_w;
    reg signed [26:0] poly_area_r, poly_area_w; 
    reg [27:0] tri_sum_r, tri_sum_w;   

    reg [11:0] edge_c_r, edge_c_w;               // c = sqrt(dx²+dy²)
    reg [11:0] heron1_r, heron1_w;               // sqrt(s(s-a))
    integer i;

    // ---------- sqrt(24-bit in / 12-bit out) ----------
    reg         sq_in_valid;
    reg  [23:0] sq_in;
    wire [11:0] sq_out;
    wire        sq_out_valid;

    sqrt u_sqrt (
        .clk(clk), .rst(reset),
        .sqrt_in(sq_in), .sqrt_in_valid(sq_in_valid),
        .sqrt_out(sq_out), .sqrt_out_valid(sq_out_valid)
    );

    wire [2:0] idx0 = cal_count_r;
    wire [2:0] idx1 = (cal_count_r == 5) ? 3'd0 : cal_count_r + 3'd1;

    wire [11:0] tri_a = R_r[idx0];
    wire [11:0] tri_b = R_r[idx1];
    wire [12:0] tri_s = (tri_a + tri_b + edge_c_r) >> 1;   // s = (a+b+c)/2

    // s(s-a), (s-b)(s-c) ; 
    wire signed [13:0] s_a = $signed({1'b0,tri_s}) - $signed({1'b0,tri_a});
    wire signed [13:0] s_b = $signed({1'b0,tri_s}) - $signed({1'b0,tri_b});
    wire signed [13:0] s_c = $signed({1'b0,tri_s}) - $signed({1'b0,edge_c_r});

    wire [23:0] heron_in1 = (s_a < 0) ? 24'd0 : tri_s * $unsigned(s_a[12:0]);
    wire [23:0] heron_in2 = (s_b < 0 || s_c < 0) ? 24'd0
                            : $unsigned(s_b[12:0]) * $unsigned(s_c[12:0]);

    // dx²+dy²
    wire signed [11:0] dx = $signed({1'b0,X_r[idx0]}) - $signed({1'b0,X_r[idx1]});
    wire signed [11:0] dy = $signed({1'b0,Y_r[idx0]}) - $signed({1'b0,Y_r[idx1]});
    wire [23:0] edge_in = dx*dx + dy*dy;

    // ================= combinational =================
    always@(*) begin
        valid = 0; is_inside = 0;
        state_w = state_r;
        for(i=0;i<6;i=i+1) begin
            X_w[i]=X_r[i]; Y_w[i]=Y_r[i]; R_w[i]=R_r[i];
        end
        in_count_w        = in_count_r;
        sort_count_w      = sort_count_r;
        sort_loop_count_w = sort_loop_count_r;
        cal_count_w       = cal_count_r;
        poly_area_w       = poly_area_r;
        tri_sum_w         = tri_sum_r;
        edge_c_w          = edge_c_r;
        heron1_w          = heron1_r;
        cmp               = 0;
        sq_in_valid       = 0;
        sq_in             = 24'd0;

        case(state_r)
            IDLE: begin
                state_w = INPUT;
                X_w[0]=X; Y_w[0]=Y; R_w[0]=R;
                in_count_w = 1;
            end
            INPUT: begin
                in_count_w = in_count_r + 1;
                if((Y < Y_r[0] || (Y == Y_r[0] && X < X_r[0]))) begin
                    X_w[0]=X; Y_w[0]=Y; R_w[0]=R;
                    X_w[in_count_r]=X_r[0]; Y_w[in_count_r]=Y_r[0]; R_w[in_count_r]=R_r[0];
                end else begin
                    X_w[in_count_r]=X; Y_w[in_count_r]=Y; R_w[in_count_r]=R;
                end
                if(in_count_r == 5) state_w = SORT;
            end

            // ---------- bubble sort:
            SORT: begin
                sort_loop_count_w = sort_loop_count_r + 1;
                if(sort_loop_count_r == 3 - sort_count_r) begin
                    sort_loop_count_w = 0;
                    sort_count_w = sort_count_r + 1;
                    if(sort_count_r == 3) begin
                        state_w = POLY;
                        sort_count_w = 0;
                    end
                end
                cmp = cross_product(X_r[sort_loop_count_r+1], Y_r[sort_loop_count_r+1],
                                    X_r[sort_loop_count_r+2], Y_r[sort_loop_count_r+2],
                                    X_r[0], Y_r[0]);
                if(!cmp) begin
                    X_w[sort_loop_count_r+1]=X_r[sort_loop_count_r+2];
                    Y_w[sort_loop_count_r+1]=Y_r[sort_loop_count_r+2];
                    R_w[sort_loop_count_r+1]=R_r[sort_loop_count_r+2];
                    X_w[sort_loop_count_r+2]=X_r[sort_loop_count_r+1];
                    Y_w[sort_loop_count_r+2]=Y_r[sort_loop_count_r+1];
                    R_w[sort_loop_count_r+2]=R_r[sort_loop_count_r+1];
                end
            end

            // ---------- shoelace: poly = Σ(xi·yj − xj·yi) = 2×面積 ----------
            POLY: begin
                if(cal_count_r == 5) begin
                    poly_area_w = poly_area_r + mult(X_r[5],Y_r[5],X_r[0],Y_r[0]);
                    cal_count_w = 0;
                    state_w = EDGE_REQ;
                end else begin
                    poly_area_w = poly_area_r +
                        mult(X_r[cal_count_r],Y_r[cal_count_r],
                             X_r[cal_count_r+1],Y_r[cal_count_r+1]);
                    cal_count_w = cal_count_r + 1;
                end
            end

            // ---------- c = sqrt(dx²+dy²) ----------
            EDGE_REQ: begin
                sq_in = edge_in;
                sq_in_valid = 1;
                state_w = EDGE_WAIT;
            end
            EDGE_WAIT: begin
                if(sq_out_valid) begin
                    edge_c_w = sq_out;
                    state_w = HERON_REQ1;
                end
            end

            // ---------- heron1 = sqrt(s(s-a)) ----------
            HERON_REQ1: begin
                sq_in = heron_in1;
                sq_in_valid = 1;
                state_w = HERON_WAIT1;
            end
            HERON_WAIT1: begin
                if(sq_out_valid) begin
                    heron1_w = sq_out;
                    state_w = HERON_REQ2;
                end
            end

            // ---------- heron2 = sqrt((s-b)(s-c)) ; tri = heron1×heron2 ----------
            HERON_REQ2: begin
                sq_in = heron_in2;
                sq_in_valid = 1;
                state_w = HERON_WAIT2;
            end
            HERON_WAIT2: begin
                if(sq_out_valid) begin
                    tri_sum_w = tri_sum_r + ((heron1_r * sq_out) << 1);
                    state_w = TRI_ACC;
                end
            end

            TRI_ACC: begin
                if(cal_count_r == 5) begin
                    state_w = OUTPUT;
                end else begin
                    cal_count_w = cal_count_r + 1;
                    state_w = EDGE_REQ;
                end
            end

            // ---------- 比較並輸出 ----------
            OUTPUT: begin
                valid = 1;
                if (tri_sum_r > poly_area_r)  
                    is_inside = 0;      // 三角形總和 > 多邊形 → 外
                else
                    is_inside = 1;      // 否則在內
                state_w = IDLE;
                poly_area_w = 0;
                tri_sum_w   = 0;
                cal_count_w = 0;
                for(i=0;i<6;i=i+1) begin X_w[i]=0; Y_w[i]=0; R_w[i]=0; end
                in_count_w        = 0;
                sort_count_w      = 0;
                sort_loop_count_w = 0;
                edge_c_w          = 0;
                heron1_w          = 0;
            end
        endcase
    end

    function automatic cross_product;
        input [9:0] x1, y1, x2, y2, x0, y0;
        reg signed [11:0] ax, ay, bx, by;
        reg signed [23:0] t1, t2;
        begin
            ax = $signed({1'b0,x1}) - $signed({1'b0,x0});
            ay = $signed({1'b0,y1}) - $signed({1'b0,y0});
            bx = $signed({1'b0,x2}) - $signed({1'b0,x0});
            by = $signed({1'b0,y2}) - $signed({1'b0,y0});
            t1 = ax*by; t2 = bx*ay;
            cross_product = (t1 > t2) ? 1'b1 : 1'b0;
        end
    endfunction

    function automatic signed [22:0] mult;
        input [9:0] x0, y0, x1, y1;
        begin
            mult = $signed({1'b0,x0})*$signed({1'b0,y1})
                 - $signed({1'b0,x1})*$signed({1'b0,y0});
        end
    endfunction

    // ================= sequential =================
    always@(posedge clk or posedge reset) begin
        if(reset) begin
            state_r <= IDLE;
            in_count_r <= 0; sort_count_r <= 0; sort_loop_count_r <= 0;
            cal_count_r <= 0; poly_area_r <= 0; tri_sum_r <= 0;
            edge_c_r <= 0; heron1_r <= 0;
            for(i=0;i<6;i=i+1) begin X_r[i]<=0; Y_r[i]<=0; R_r[i]<=0; end
        end else begin
            state_r <= state_w;
            in_count_r <= in_count_w;
            sort_count_r <= sort_count_w;
            sort_loop_count_r <= sort_loop_count_w;
            cal_count_r <= cal_count_w;
            poly_area_r <= poly_area_w;
            tri_sum_r <= tri_sum_w;
            edge_c_r <= edge_c_w;
            heron1_r <= heron1_w;
            for(i=0;i<6;i=i+1) begin X_r[i]<=X_w[i]; Y_r[i]<=Y_w[i]; R_r[i]<=R_w[i]; end
        end
    end
endmodule