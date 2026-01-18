module  TOP(
	input			clk,
	input			rst,
	output reg		busy,	
	input			ready,				
	output reg[11:0]	iaddr,
	input signed[19:0]		idata,	
	output reg 	 	cwr,
	output reg[11:0] 	caddr_wr,
	output reg[19:0] 	cdata_wr,	
	output reg	 	crd,
	output reg[11:0]	caddr_rd,
	input	[19:0]		cdata_rd,
	output reg[2:0] 	csel
	);
//================================================================
//  Wires & Registers 
//================================================================
reg [5:0] x, y, L1_x, L1_y;
wire signed [39:0] bias;
assign bias = 40'h0013100000;

wire signed [19:0] conv_result;

reg [3:0] counter_data, counter_addr;
reg [2:0] counter_layer1;

reg [2:0] state_r, state_w;

localparam IDLE = 0, INPUT = 1, L0_MEM = 2, DELAY_CLK = 3, READ_L0_MEM = 4;
localparam L1_MEM = 5, DELAY_CLK_2 = 6, FINISH = 7;

localparam NOSEL = 3'b000, LAYER_0 = 3'b001, LAYER_1 = 3'b011;

//================================================================
//  iaddr 
//================================================================

always@( posedge clk or posedge rst ) begin
	if( rst ) iaddr <= 0;
	else if( state_w == INPUT ) begin
		case( counter_addr )
		4'd0: iaddr <= {y - 1'd1,x - 1'd1};
		4'd1: iaddr <= {y - 1'd1,x};
		4'd2: iaddr <= {y - 1'd1,x + 1'd1};
		4'd3: iaddr <= {y,x - 1'd1};
		4'd4: iaddr <= {y,x};
		4'd5: iaddr <= {y,x + 1'd1};
		4'd6: iaddr <= {y + 1'd1,x - 1'd1};
		4'd7: iaddr <= {y + 1'd1,x};
		4'd8: iaddr <= {y + 1'd1,x + 1'd1};
		endcase
	end
	else if( state_w == L0_MEM ) iaddr <= {y,x+1'd1};
end

//================================================================
//  x && y 
//================================================================
always@( posedge clk or posedge rst ) begin
	if( rst ) begin
		x <= 0; y <= 0;
	end
	else if( state_r == L0_MEM ) begin
		x <= x + 1; y <= ( x== 63 )? y + 1 : y;
	end
end

//================================================================
//  L1_x && L1_y
//================================================================
always@( posedge clk or posedge rst ) begin
	if( rst )  begin
		L1_x <= 0; L1_y <= 0;
	end
	else if( state_r == L1_MEM  ) begin
		L1_x <= ( L1_x == 62 )? 0 : L1_x + 2; L1_y <= ( L1_x == 62 )? L1_y + 2 : L1_y;	
	end
end


localparam Kernel_0 = 20'h0A89E,
		  Kernel_1 = 20'h092D5,
		  Kernel_2 = 20'h06D43,
		  Kernel_3 = 20'h01004,
		  Kernel_4 = 20'hF8F71,
		  Kernel_5 = 20'hF6E54,
		  Kernel_6 = 20'hFA6D7,
		  Kernel_7 = 20'hFC834,
		  Kernel_8 = 20'hFAC19;

reg signed [19:0] Kernel;	
	  
always@( * )
begin
	case( counter_data )
	4'd1: Kernel = Kernel_0;
	4'd2: Kernel = Kernel_1;
	4'd3: Kernel = Kernel_2;
	4'd4: Kernel = Kernel_3;
	4'd5: Kernel = Kernel_4;
	4'd6: Kernel = Kernel_5;
	4'd7: Kernel = Kernel_6;
	4'd8: Kernel = Kernel_7;
	4'd9: Kernel = Kernel_8;
	default: Kernel = 0;
	endcase
end

wire signed [39:0] data_conv;
reg  signed [39:0] data_conv_sum;
reg  signed [19:0] idata_tmp;
assign data_conv = idata_tmp * Kernel;
 
//================================================================
//  data_conv_sum && idata_tmp
//================================================================ 
always@( posedge clk or posedge rst ) begin
	if( rst ) idata_tmp <= 0;
	else if( state_r == INPUT ) begin
		case( counter_data )
		4'd0: idata_tmp <= ( x == 0 || y == 0 )? 0 : idata;
		4'd1: idata_tmp <= ( y == 0 )? 0: idata;
		4'd2: idata_tmp <= ( x == 63 || y == 0 )? 0: idata;	
		4'd3: idata_tmp <= ( x == 0 )? 0: idata;
		4'd4: idata_tmp <= idata;
		4'd5: idata_tmp <= ( x == 63 )? 0: idata;
		4'd6: idata_tmp <= ( x == 0 || y == 63 )? 0: idata;
		4'd7: idata_tmp <= ( y == 63 )? 0: idata;
		4'd8: idata_tmp <= ( x == 63 || y == 63 )? 0: idata;
		endcase
	end 
end

always@( posedge clk or posedge rst ) begin
	if( rst ) data_conv_sum <= 0;
	else if( state_r == INPUT ) begin
		if( counter_data == 0 ) data_conv_sum <= 0;
		else if( counter_data == 10 ) data_conv_sum <= data_conv_sum + bias;
		else data_conv_sum <= data_conv_sum + data_conv;
	end
end

//================================================================
//  cwr
//================================================================ 
always@( posedge clk or posedge rst ) begin
	if( rst ) cwr <= 0;
	else if( state_r == L0_MEM ) cwr <= 1;
	else if( state_r == L1_MEM ) cwr <= 1;
	else cwr <= 0;
end

//================================================================
//  crd
//================================================================ 
always@( posedge clk or posedge rst ) begin
	if( rst ) crd <= 0;
	else if( state_w == READ_L0_MEM ) crd <= 1;
	else crd <= 0;
end

//================================================================
//  caddr_rd
//================================================================ 

always@( posedge clk or posedge rst ) begin
	if( rst ) caddr_rd <= 0;
	else if( state_w == READ_L0_MEM )  begin
		case( counter_layer1 )
		3'd0: caddr_rd <= {L1_y,L1_x};
		3'd1: caddr_rd <= {L1_y,L1_x+1'd1};
		3'd2: caddr_rd <= {L1_y+1'd1,L1_x};
		3'd3: caddr_rd <= {L1_y+1'd1,L1_x+1'd1};
		endcase 
	end
end

//================================================================
//  caddr_wr
//================================================================ 
always@( posedge clk or posedge rst ) begin
	if( rst ) caddr_wr <= 0;
	else if( state_r == L0_MEM ) caddr_wr <= {y,x};
	else if( state_r == L1_MEM ) caddr_wr <= {L1_y[5:1],L1_x[5:1]};
end

//================================================================
//  cdata_wr
//================================================================ 
assign conv_result = ( data_conv_sum[15] )? {data_conv_sum[35:16]} + 1 : {data_conv_sum[35:16]}  ;

always@( posedge clk or posedge rst ) begin
	if( rst ) cdata_wr <= 0;
	else if( state_r == L0_MEM ) cdata_wr <= ( data_conv_sum[39] )? 0 : conv_result;
	else if( state_r == READ_L0_MEM ) begin
		if( counter_layer1 == 3'd1 ) cdata_wr <= cdata_rd;
		else cdata_wr <= ( cdata_rd > cdata_wr )? cdata_rd: cdata_wr; 
	end
end

//================================================================
//  counter_addr
//================================================================ 
always@( posedge clk or posedge rst ) begin
	if( rst ) counter_addr <= 0;
	else if( state_w == INPUT ) counter_addr <= counter_addr + 1;
	else if( state_w == L0_MEM ) counter_addr <= 0;
end

//================================================================
//  counter_data
//================================================================ 
always@( posedge clk or posedge rst ) begin
	if( rst ) counter_data <= 0;
	else counter_data <= counter_addr;
end

//================================================================
//  counter_layer1
//================================================================ 
always@( posedge clk or posedge rst ) begin
	if( rst ) counter_layer1 <= 0;
	else if( state_w == READ_L0_MEM ) counter_layer1 <= counter_layer1 + 1;
	else counter_layer1 <= 0;
end

//================================================================
//  busy 
//================================================================
always@( posedge clk or posedge rst )  begin
	if( rst ) busy <= 0;
	else if( ready ) busy <= 1; 
	else if( state_r == FINISH ) busy <= 0;
end

//================================================================
//  csel
//================================================================
always@( posedge clk or posedge rst ) begin
	if( rst ) csel <= NOSEL;
	else if( state_r == L0_MEM ) csel <= LAYER_0;
	else if( state_r == L1_MEM ) csel <= LAYER_1;
	else if( state_w == READ_L0_MEM ) csel <= LAYER_0;
	else csel <= NOSEL;
end

//================================================================
//  FSM
//================================================================
always@( posedge clk or posedge rst ) begin
	if( rst ) state_r <= IDLE;
	else state_r <= state_w;
end

always@( * ) begin
	case( state_r )
	IDLE: 		state_w = INPUT;
	INPUT: 		state_w = ( counter_data == 10 )? L0_MEM : INPUT ;
	L0_MEM:		state_w = DELAY_CLK;
	DELAY_CLK: 	state_w = ( x == 0 && y == 0 )? READ_L0_MEM : INPUT;
	READ_L0_MEM: 	state_w = ( counter_layer1 == 4 )? L1_MEM : READ_L0_MEM ;
	L1_MEM: 		state_w = DELAY_CLK_2;
	DELAY_CLK_2: 	state_w = ( L1_x == 0 && L1_y == 0 )? FINISH : READ_L0_MEM;
	FINISH: 		state_w = FINISH;
	default: 			state_w = IDLE;
	endcase
end

endmodule
