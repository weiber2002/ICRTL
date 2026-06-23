module TOP(
	input 				clk, 
	input				rst,
	output	reg			done , 
	output				sti_rd ,
	output	reg [9:0]	sti_addr ,
	input		[15:0]  sti_di,
	output				res_wr ,
	output				res_rd ,
	output	reg [13:0]	res_addr ,
	output	reg [7:0]	res_do,
	input		[7:0]	res_di
);

	integer i;

	reg [15:0] idata_buf;
	reg [3:0] dup_cnt;
	reg [2:0] cnt_calc;
	reg flag_fb;

	reg [6:0] y, x ;

	reg [7:0] mini;
	reg [7:0] res_input_buf;
	//================================================================
	//  FSM
	//================================================================
	localparam IDLE = 0, INPUT = 1, COMP = 2, OUTPUT = 3, READMEM = 4, DELAY = 5, COPY = 6, FINISH = 7;

	reg [2:0] state_r, state_w;

	always @(posedge clk or negedge rst) begin
		if( !rst ) state_r <= IDLE;
		else state_r <= state_w;
	end

	always @( * ) begin
		case( state_r ) 
			IDLE: state_w = INPUT;
			INPUT: state_w = COPY;
			COPY: begin
				if( dup_cnt == 0 ) begin
					if( sti_addr == 1023 ) state_w = READMEM;
					else state_w = INPUT;
				end
				else state_w = COPY;
			end
			READMEM: begin
				if ( res_addr == 0 && flag_fb ) state_w = FINISH;
				else if( res_addr == 16383 && !flag_fb ) state_w = DELAY;
				else state_w = ( res_di != 0 )? COMP : READMEM;
			end
			COMP: state_w = ( cnt_calc == 4 )? OUTPUT : COMP ;
			OUTPUT: state_w = READMEM;
			DELAY: state_w = READMEM;
			FINISH: state_w = FINISH;
			default: state_w = IDLE;
		endcase	
	end

	//================================================================
	//  INPUT
	//================================================================
	assign sti_rd = ( state_r == INPUT );

	always @(posedge clk or negedge rst ) begin
		if( !rst ) idata_buf <= 0;
		else if( state_r == INPUT ) begin
			for( i=0; i<16; i=i+1 ) idata_buf[15-i] <= sti_di[i];
		end
	end

	always @(posedge clk or negedge rst) begin
		if(!rst) res_input_buf <= 0;
		else if(state_r == READMEM) res_input_buf <= res_di;
	end
	//================================================================
	//  OUTPUT
	//================================================================
	always @( posedge clk or negedge rst ) begin
		if( !rst ) sti_addr <= 0;
		else if( state_r == COPY && dup_cnt == 0 ) sti_addr <= sti_addr + 1;
	end

	wire [3:0] addr_tmp;
	assign addr_tmp  = dup_cnt-1;

	always @( * ) begin
		case( state_r )
			COPY:  res_do = idata_buf[addr_tmp];
			OUTPUT: begin
				if(flag_fb) begin
					if( res_input_buf > mini+1 ) res_do = mini + 1;
					else res_do = res_input_buf;
				end
				else	res_do = mini + 1;
			end
			default: res_do = 0;
		endcase
	end

	always @(posedge clk or negedge rst ) begin
		if( !rst ) dup_cnt <= 0;
		else if( state_w == COPY ) dup_cnt <= dup_cnt + 1;
		else dup_cnt <= 0; 
	end

	reg [13:0] addr_forw[3:0];

	always @( * ) begin
		if( !flag_fb ) begin
			addr_forw[0] = {y-7'd1, x-7'd1} ;
			addr_forw[1] = {y-7'd1, x     } ;
			addr_forw[2] = {y-7'd1, x+7'd1} ;
			addr_forw[3] = {y     , x-7'd1} ;
		end
		else begin
			addr_forw[0] = {y     , x+7'd1} ;
			addr_forw[1] = {y+7'd1, x-7'd1} ;
			addr_forw[2] = {y+7'd1, x     } ;
			addr_forw[3] = {y+7'd1, x+7'd1} ;
		end
	end	


	always @(posedge clk or negedge rst) begin
		if( !rst ) 							res_addr <= 0;
		else if( state_w == COPY ) 			res_addr <= {sti_addr,dup_cnt};
		else if( state_w == READMEM ) 		res_addr <= {y,x};
		else if( state_w == COMP ) 			res_addr <= ( flag_fb )? addr_forw[cnt_calc] + 1:addr_forw[cnt_calc] - 1;
		else if( state_w == OUTPUT ) 		res_addr <= ( flag_fb )? {y,x} + 1:{y,x} - 1;
		else if( state_w == DELAY ) 		res_addr <= 16383;
	end

	always @( posedge clk or negedge rst ) begin
		if( !rst ) done <= 0;
		else if( state_r == FINISH ) done <= 1;
	end

	assign res_wr = ( state_r == COPY || state_r == OUTPUT );
	assign res_rd = ( state_r == READMEM  || state_r == COMP   );

	assign fw_finish = flag_fb;
	//================================================================
	//  x && y
	//================================================================
	always @(posedge clk or negedge rst) begin
		if(!rst) begin
			x <= 0; y <= 0;
		end
		else if( state_w == READMEM ) begin
			if( flag_fb ) begin
				x <= x - 1; y<= (x == 0)? y-1:y;
			end
			else begin
				x <= x + 1; y <= ( x == 127 )? y+1 : y; 
			end
		end
		else if( state_w == DELAY ) begin
			x <= 127; y <= 127;
		end 
	end

	always @( posedge clk or negedge rst ) begin
		if(!rst) cnt_calc <= 0;
		else if( state_w == COMP ) cnt_calc <= cnt_calc + 1; 
		else cnt_calc <= 0;
	end

	//================================================================
	//  flag
	//================================================================
	always @(posedge clk or negedge rst ) begin
		if(!rst) flag_fb <= 0;
		else if( state_r == READMEM ) begin
			if( res_addr == 16383 ) flag_fb <= 1;
		end
	end

	//================================================================
	//  mini
	//================================================================
	always @(posedge clk or negedge rst ) begin
		if(!rst) mini <= 0;
		else if( state_r == COMP ) begin
			if( cnt_calc == 1 ) mini <= res_di;
			else begin
				if( res_di < mini ) mini <= res_di;
			end
		end
	end

 
endmodule
