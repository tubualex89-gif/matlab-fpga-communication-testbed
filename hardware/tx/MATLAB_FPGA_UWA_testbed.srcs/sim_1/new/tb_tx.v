`timescale 1ns/1ps
module tb_tx;
reg clk=0, rst_n=0, start=0, valid=1;
reg [31:0] length=3;
reg signed [15:0] data=16'sd1234;
wire ready, busy, done, underflow, zero_length, sample_valid, dac_clk, dac_wrt;
wire [13:0] sample;
reg [13:0] head_lfm [0:9999];
integer ticks=0, transfers=0;
time last_dac_rise=0;
always #5 clk=~clk;
Test_bed_tx dut(.clk_100m(clk), .rst_n(rst_n), .start(start), .payload_samples(length),
 .payload_data(data), .payload_valid(valid), .payload_ready(ready), .dac_sample(sample),
 .dac_sample_valid(sample_valid), .dac_clk(dac_clk), .dac_wrt(dac_wrt),
 .busy(busy), .done(done), .error_underflow(underflow), .error_zero_length(zero_length));
initial begin
 repeat(5) @(negedge clk); rst_n=1;
 @(negedge clk); start=1; @(negedge clk); start=0;
 wait(busy);
 while (!done) begin
  @(posedge clk);
  if (ready && valid) transfers=transfers+1;
  #1;
  if (sample_valid) begin
   ticks=ticks+1;
   if (ticks<=10000) head_lfm[ticks-1]=sample;
   else if (ticks<=40000) begin
    if (sample !== 14'd8192) $fatal(1,"first guard not silent at %0d",ticks);
   end else if (ticks<=40003) begin
    if (sample !== 14'd8500) $fatal(1,"payload mismatch at %0d",ticks);
   end else if (ticks<=70003) begin
    if (sample !== 14'd8192) $fatal(1,"second guard not silent at %0d",ticks);
   end else if (ticks<=80003) begin
    if (sample !== head_lfm[ticks-70004]) $fatal(1,"LFM mismatch at %0d",ticks);
   end else $fatal(1,"extra sample at %0d",ticks);
  end
 end
 if (ticks!=80003 || transfers!=3 || underflow || zero_length) $fatal(1,"frame length, transfers or error incorrect");
 $display("PASS: 10000 LFM + 30000 guard + 3 payload + 30000 guard + 10000 identical LFM");
 repeat(300) @(negedge clk);
 if (!done) $fatal(1,"done did not remain asserted");
 length=0; start=1; @(negedge clk); start=0;
 if (done || !zero_length) $fatal(1,"zero length check failed");
 $display("PASS: completion held and cleared on next start");
 $finish;
end
always @(posedge clk) begin
 #1; if (rst_n && dac_wrt !== dac_clk) $fatal(1,"DAC write clock mismatch");
end
always @(posedge dac_clk) begin
 if (rst_n) begin
  if (last_dac_rise != 0 && $time-last_dac_rise != 1000) $fatal(1,"DAC clock period is not 1 us");
  last_dac_rise = $time;
 end
end
initial begin #100000000; $fatal(1,"timeout"); end
endmodule
