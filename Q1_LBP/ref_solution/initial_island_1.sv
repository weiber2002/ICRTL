
`timescale 1ns/10ps
module LBP ( clk, reset, gray_addr, gray_req, gray_ready, gray_data, lbp_addr, lbp_valid, lbp_data, finish);
input   	clk;
input   	reset;
output  [13:0] 	gray_addr;
output         	gray_req;
input   	gray_ready;
input   [7:0] 	gray_data;
output  [13:0] 	lbp_addr;
output  	lbp_valid;
output  [7:0] 	lbp_data;
output  	finish;
//====================================================================
reg [13:0] gray_addr;
reg gray_req;
reg [13:0] lbp_addr;
reg lbp_valid;
reg [7:0] lbp_data;
reg finish;

reg [2:0] current_state,next_state; 
reg [6:0] x,y;
wire [6:0] x_b,x_f,y_b,y_f;
reg [3:0] counter_G;

assign x_b = x - 7'd1;
assign x_f = x + 7'd1;
assign y_b = y - 7'd1;
assign y_f = y + 7'd1;

wire [13:0] g0_addr,g1_addr,g2_addr,g3_addr,g4_addr,g5_addr,g6_addr,g7_addr;
reg [13:0] gc_addr;

assign g0_addr = {y_b,x_b};
assign g1_addr = {y_b,x};
assign g2_addr = {y_b,x_f};

assign g3_addr = {y,x_b};
assign g4_addr = {y,x_f};

assign g5_addr = {y_f,x_b};
assign g6_addr = {y_f,x};
assign g7_addr = {y_f,x_f};

reg [7:0] gc_data;

wire [3:0] counter_G_cutOne;
assign counter_G_cutOne = counter_G - 4'd1;
//state
parameter IDLE = 3'd0;
parameter READ_gc = 3'd1;
parameter READ_gp = 3'd2;
parameter RESULT = 3'd3;
parameter FINISH = 3'd4;

//switch state
always@(posedge clk or posedge reset)
begin
    if(reset) current_state <= IDLE;
    else current_state <= next_state;
end

//next state logic
always@(*)
begin
    case(current_state)
    IDLE: 
    begin
        if(gray_ready == 1'd1) next_state = READ_gc;
        else next_state = IDLE;
    end
    READ_gc: next_state = READ_gp;
    READ_gp:
    begin
        if(counter_G == 4'd8) next_state = RESULT;
        else next_state = READ_gp;
    end
    RESULT: 
    begin
        if(gc_addr == 14'd16254) next_state = FINISH; //128*128-128-1-1 = 162454
        else next_state = READ_gc;
    end
    FINISH: next_state = FINISH;
    default: next_state = IDLE;
    endcase
end

//index x y
always@(posedge clk or posedge reset)
begin
    if(reset) x <= 7'd1;
    else if(next_state == RESULT && x == 7'd126) x <= 7'd1;
    else if(next_state == RESULT) x <= x + 7'd1;
end

always@(posedge clk or posedge reset)
begin
    if(reset) y <= 7'd1;
    else if(next_state == RESULT && x == 7'd126) y <= y + 7'd1;
end

//counter_G
always@(posedge clk or posedge reset)
begin
    if(reset) counter_G <= 4'd0;
    else if(next_state == READ_gp) counter_G <= counter_G + 4'd1;
    else if(current_state == RESULT) counter_G <= 4'd0;
end

//gc_addr
always@(posedge clk or posedge reset)
begin
    if(reset) gc_addr <= 14'd129;
    else if(next_state == READ_gc) gc_addr <= {y,x};
end

//output

//gray_req
always@(posedge clk or posedge reset)
begin
    if(reset) gray_req <= 1'd0;
    else if(next_state == READ_gc || next_state == READ_gp) gray_req <= 1'd1;
    else gray_req <= 1'd0;
end

//lbp_valid
always@(posedge clk or posedge reset)
begin
    if(reset) lbp_valid <= 1'd0;
    else if(next_state == RESULT) lbp_valid <= 1'd1;
    else lbp_valid <= 1'd0;
end

//finish
always@(posedge clk or posedge reset)
begin
    if(reset) finish <= 1'd0;
    else if(current_state == FINISH) finish <= 1'd1;
end

//gray_addr
always@(posedge clk or posedge reset)
begin
    if(reset) gray_addr <= 14'd0;
    else if(next_state == READ_gc) gray_addr <= {y,x};
    else if(next_state == READ_gp)
    begin
        case(counter_G)
        4'd0: gray_addr <= g0_addr;
        4'd1: gray_addr <= g1_addr;
        4'd2: gray_addr <= g2_addr;
        
        4'd3: gray_addr <= g3_addr;
        4'd4: gray_addr <= g4_addr;
        
        4'd5: gray_addr <= g5_addr;
        4'd6: gray_addr <= g6_addr;
        4'd7: gray_addr <= g7_addr;
        endcase
    end
end

//lbp_addr
always@(posedge clk or posedge reset)
begin
    if(reset) lbp_addr <= 14'd0;
    else if(next_state == RESULT) lbp_addr <= gc_addr;
end

//lbp_data
always@(posedge clk or posedge reset)
begin
    if(reset) 
    begin
        lbp_data <= 8'd0;
        gc_data <= 8'd0;
    end
    else if(current_state == READ_gc) gc_data <= gray_data;
    else if(current_state == READ_gp)
    begin
        if(gray_data>=gc_data) lbp_data <= lbp_data + (8'd1 << counter_G_cutOne);
    end
    else if(current_state == RESULT) lbp_data <= 8'd0;
end

//====================================================================
endmodule