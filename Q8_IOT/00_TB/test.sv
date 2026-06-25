`timescale 1ns/10ps
`define SDFFILE     "./IOTDF_syn.sdf"     //Modify your sdf file name
`define CYCLE       10                   //Modify your CYCLE
`define DEL         1.0
`define PAT_NUM     96
`define F1_NUM      12
`define F4_NUM      25
`define F5_NUM      73
`define F6_NUM      3
`define F7_NUM      4
`define WATCHDOG    4000000

module test;
reg           clk;
reg           rst;
reg           in_en;
reg  [7:0]    iot_in;
reg  [2:0]    fn_sel;
wire          busy;
wire          valid;
wire [127:0]  iot_out;

reg  [127:0]  pat_mem[0:`PAT_NUM-1];
reg  [127:0]  f1_mem [0:`F1_NUM-1];
reg  [127:0]  f2_mem [0:`F1_NUM-1];
reg  [127:0]  f3_mem [0:`F1_NUM-1];
reg  [127:0]  f4_mem [0:`F4_NUM-1];
reg  [127:0]  f5_mem [0:`F5_NUM-1];
reg  [127:0]  f6_mem [0:`F6_NUM-1];
reg  [127:0]  f7_mem [0:`F7_NUM-1];
reg  [127:0]  in_tmp;
reg  [127:0]  out_tmp;
integer       i, j, x, in_h, in_l, pass, err, fn_i, cnt_cur;
reg           over2;
reg  [31:0]   cycle_cnt;


TOP u_IOTDF( .clk        (clk        ),
               .rst        (rst        ),
               .in_en      (in_en      ),
               .iot_in     (iot_in     ),
               .fn_sel     (fn_sel     ),
               .busy       (busy       ),
               .valid      (valid      ),
               .iot_out    (iot_out    )
             );

`ifdef SDF
   initial       $sdf_annotate(`SDFFILE, u_IOTDF );
`endif

always begin #(`CYCLE/2)  clk = ~clk; end

// Total cycle counter (accumulates across all 7 functions -> sum)
initial cycle_cnt = 0;
always @(posedge clk) cycle_cnt = cycle_cnt + 1;

// Output checker: active for the current function until cnt_cur outputs have
// been collected (over2). Selects the golden memory by the current fn_i.
always @(posedge clk) begin
   if(!over2 && valid) begin
      case (fn_i)
         2: out_tmp = f2_mem[x];
         3: out_tmp = f3_mem[x];
         4: out_tmp = f4_mem[x];
         5: out_tmp = f5_mem[x];
         6: out_tmp = f6_mem[x];
         7: out_tmp = f7_mem[x];
         default: out_tmp = f1_mem[x]; // f1
      endcase
      if(iot_out !== out_tmp) begin
         $display("F%0d P%02d: iot_out=%032h != expect %032h", fn_i, x, iot_out, out_tmp);
         err = err + 1;
      end
      else begin
         pass = pass + 1;
      end
      x = x + 1;
      if(x > cnt_cur-1) over2 = 1;
   end
end


initial begin
   clk = 1'b0; rst = 1'b0; in_en = 1'b0; iot_in = 8'h0;
   pass = 0; err = 0;
   over2 = 1'b1;   // checker idle until a function starts
   x = 0; i = 0; j = 0; cnt_cur = 0; fn_i = 0;

   $readmemh ("./00_TB/pattern1.dat", pat_mem);
   $readmemh ("./00_TB/f1.dat", f1_mem);
   $readmemh ("./00_TB/f2.dat", f2_mem);
   $readmemh ("./00_TB/f3.dat", f3_mem);
   $readmemh ("./00_TB/f4.dat", f4_mem);
   $readmemh ("./00_TB/f5.dat", f5_mem);
   $readmemh ("./00_TB/f6.dat", f6_mem);
   $readmemh ("./00_TB/f7.dat", f7_mem);

   $display("-----------------------------------------------------");
   $display("Start to Send IOT Data & Compare ...");

   // Sweep all 7 functions in a single simulation.
   for(fn_i = 1; fn_i <= 7; fn_i = fn_i + 1) begin
      case (fn_i)
         4: cnt_cur = `F4_NUM;
         5: cnt_cur = `F5_NUM;
         6: cnt_cur = `F6_NUM;
         7: cnt_cur = `F7_NUM;
         default: cnt_cur = `F1_NUM; // f1, f2, f3
      endcase

      fn_sel = fn_i[2:0];
      i = 0; j = 0; x = 0; in_h = 0; in_l = 0;
      in_en = 1'b0; iot_in = 8'h0;

      // Reset DUT for this function, then enable the checker.
      @(posedge clk) #`DEL rst = 1'b1;
      #`CYCLE              rst = 1'b0;
      over2 = 1'b0;
      $display("----------------- Function %0d (fn_sel=%0d) -----------------", fn_i, fn_i);

      // Stream the input pattern (8 bits/cycle when the DUT is not busy).
      @(posedge clk);
      while (i < `PAT_NUM) begin
         if(!busy) begin
            in_tmp = pat_mem[i];
            in_h = 128-(j*8+1);
            in_l = 128-(j+1)*8;
            #`DEL;
            iot_in = in_tmp[in_h -: 8];
            in_en  = 1'b1;
            if(j<15) j=j+1;
            else begin j=0; i=i+1; end
         end
         else begin
            #`DEL;
            iot_in = 8'h0;
            in_en  = 1'b0;
         end
         @(posedge clk);
      end
      if(busy) begin
         #`DEL;
         iot_in = 8'h0;
         in_en  = 1'b0;
      end

      // Wait until the checker has collected all expected outputs.
      wait (over2 == 1'b1);
      repeat (2) @(posedge clk);
   end

   $display("-----------------------------------------------------");
   $display("Pass: %0d", pass);
   $display("Total Error: %0d", err);
   if(err == 0)
      $display("All tests PASS");
   else
      $display("FAIL: %0d errors", err);
   $display("total time: %0d cycles", cycle_cnt);
   $display("-----------------------------------------------------");
   $finish;
end

// Global watchdog so a hung DUT cannot stall the sweep forever.
initial begin
   #`WATCHDOG;
   $display("WATCHDOG: simulation did not finish in time");
   $display("Total Error: %0d", err);
   $display("total time: %0d cycles", cycle_cnt);
   $finish;
end

endmodule
