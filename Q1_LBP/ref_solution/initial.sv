`timescale 1ns/10ps
module TOP ( clk, rst, gray_addr, gray_req, gray_ready, gray_data, lbp_addr, lbp_valid, lbp_data, finish);
input   	clk;
input   	rst;

// ask data 
output  reg       	gray_req;
output  reg [13:0] 	gray_addr;
input   	    gray_ready;
input   [7:0] 	gray_data;

// write data
output  reg [13:0] 	lbp_addr;
output  reg 	    lbp_valid;
output  reg [7:0] 	lbp_data;
output  reg  	    finish;

reg [7:0] buffer [8:0];
reg [1:0] state_r, state_w;

wire [13:0] minus = gray_addr - 255;
wire [13:0] plus  = gray_addr + 128;
wire valid = (lbp_addr[6:0]== 7'b111_1111 || lbp_addr[6:0]== 7'b000_0000);
wire fin = (lbp_addr==14'd16254);

localparam 	DATA1 = 0,
			DATA2 = 1,
			DATA3 = 2,
			WRITE_DATA   = 3;

always @(posedge clk or posedge rst) begin
	if (rst) begin
		state_r   <= DATA1;
		gray_addr <= 0;
		lbp_addr  <= 126;
		finish    <= 0;
	end
	else begin
		state_r  <= state_w;
		gray_req <= 1;
		case(state_r)
			DATA1:begin
				lbp_valid <= 0;
				gray_addr <= plus;
				buffer[2] <= gray_data;     // get 2
			end
			DATA2:begin
				gray_addr <= plus;
				buffer[5] <= gray_data;     // get 130
			end
			DATA3:begin
				gray_addr <= minus;
				buffer[8] <= gray_data;     // get 258
				lbp_addr  <= lbp_addr + 1;
			end
			WRITE_DATA:begin
				// shift
				lbp_valid   <= (valid)? 0 : 1;
				lbp_data[0] <= (buffer[0]>=buffer[4])? 1 : 0;
				lbp_data[1] <= (buffer[1]>=buffer[4])? 1 : 0;
				lbp_data[2] <= (buffer[2]>=buffer[4])? 1 : 0;
				lbp_data[3] <= (buffer[3]>=buffer[4])? 1 : 0;
				lbp_data[4] <= (buffer[5]>=buffer[4])? 1 : 0;
				lbp_data[5] <= (buffer[6]>=buffer[4])? 1 : 0;
				lbp_data[6] <= (buffer[7]>=buffer[4])? 1 : 0;
				lbp_data[7] <= (buffer[8]>=buffer[4])? 1 : 0;

				buffer[0] <= buffer[1];
				buffer[1] <= buffer[2];
				buffer[3] <= buffer[4];
				buffer[4] <= buffer[5];
				buffer[6] <= buffer[7];
				buffer[7] <= buffer[8];
				if(fin) finish <= 1;
			end
		endcase
	end
end

always@(*)begin
	case(state_r)
			DATA1: state_w = DATA2;
			DATA2: state_w = DATA3;
			DATA3: state_w = WRITE_DATA;
			WRITE_DATA: state_w = DATA1;
	endcase
end

endmodule