`timescale 1ns/1ps
module tb_rx_capture;
reg clk=0,rst_n=0,valid=0,hit=0,ready=1;
reg signed [15:0] din=0;
wire [15:0] data; wire v,last,busy,done,timeout,overflow; wire [31:0] count;
integer n=0,received=0,lasts=0,finished=0; reg signed [15:0] prev; reg [31:0] counts[0:1];
always #5 clk=~clk;
rx_capture #(.BUFFER_BITS(5),.PRE_SAMPLES(8),.MIN_SEPARATION(12),.MAX_SAMPLES(100),.POST_SAMPLES(3)) dut(
 .clk(clk),.rst_n(rst_n),.in_valid(valid),.in_data(din),.detected(hit),
 .m_axis_tdata(data),.m_axis_tvalid(v),.m_axis_tready(ready),.m_axis_tlast(last),
 .busy(busy),.done(done),.timeout(timeout),.overflow(overflow),.sample_count(count));
always @(posedge clk) begin
 if(v&&ready) begin
  if(received>0 && $signed(data)!==prev+1) $fatal(1,"data discontinuity");
  prev=data; received=received+1;
  if(last) begin counts[lasts]=received; lasts=lasts+1; received=0; end
 end
 if(done) begin if(busy || timeout || overflow) $fatal(1,"bad completed status"); finished=finished+1; end
end
task tick_sample;
 begin @(negedge clk); valid=1; din=n; n=n+1; @(negedge clk); valid=0; repeat(4) @(negedge clk); end
endtask
task trigger;
 begin @(negedge clk); hit=1; @(negedge clk); hit=0; end
endtask
task frame;
 integer target;
 begin
  target=finished+1;
  repeat(12) tick_sample; trigger; if(!busy) $fatal(1,"capture did not start");
  repeat(6) tick_sample; ready=0; repeat(4) tick_sample; ready=1;
  repeat(6) tick_sample; trigger; repeat(3) tick_sample;
  wait(finished>=target); repeat(3) @(negedge clk); if(busy) $fatal(1,"monitoring did not resume");
 end
endtask
initial begin
 repeat(5) @(negedge clk); rst_n=1; repeat(3) @(negedge clk);
 if(busy) $fatal(1,"receiver not listening after reset");
 frame; frame;
 if(finished!=2 || lasts!=2 || counts[0]!=27 || counts[1]!=27)
  $fatal(1,"wrong frames finished=%d last=%d counts=%d/%d",finished,lasts,counts[0],counts[1]);
 $display("PASS continuous monitoring: two frames, TLAST and independent re-entry"); $finish;
end
initial begin #1000000; $fatal(1,"timeout"); end
endmodule

