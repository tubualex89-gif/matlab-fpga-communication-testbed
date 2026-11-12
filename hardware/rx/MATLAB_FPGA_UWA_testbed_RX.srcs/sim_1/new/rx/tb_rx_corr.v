`timescale 1ns/1ps
module tb_rx_corr;
reg clk=0,rst_n=0,restart=0,sample_en=0,valid=0;
wire signed [15:0] chirp;
reg signed [15:0] sample=0;
wire mv,hit,overrun,filter_overrun,filter_valid; wire [15:0] metric;
wire signed [15:0] filter_data;
integer n,hits=0; reg [15:0] peak=0, peak_strong=0;
always #5 clk=~clk;
lfm_dds tx(.clk(clk),.rst_n(rst_n),.restart(restart),.sample_en(sample_en),.sample(chirp));
rx_fir filt(.clk(clk),.rst_n(rst_n),.in_valid(valid),.in_data(sample),
 .out_valid(filter_valid),.out_data(filter_data),.overrun(filter_overrun));
rx_lfm_corr dut(.clk(clk),.rst_n(rst_n),.in_valid(filter_valid),.in_data(filter_data),
 .threshold_q15(16'd6554),.min_energy(40'd100000),.metric_valid(mv),.metric_q15(metric),.detected(hit),.overrun(overrun));
always @(posedge clk) begin if(hit) hits=hits+1; if(mv && metric>peak) peak=metric; end
task put(input signed [15:0] v, input advance);
 begin
  @(negedge clk); sample=v; valid=1; sample_en=advance;
  @(negedge clk); valid=0; sample_en=0; repeat(98) @(negedge clk);
 end
endtask
initial begin
 repeat(5) @(negedge clk); rst_n=1;
 for(n=0;n<1000;n=n+1) put(0,0);
 @(negedge clk); restart=1; @(negedge clk); restart=0;
 for(n=0;n<10000;n=n+1) put(chirp >>> 5,1);
 for(n=0;n<2000;n=n+1) put(0,0);
 repeat(600) @(negedge clk);
 if(hits==0 || peak<6554 || overrun || filter_overrun) $fatal(1,"corr failed hits=%d peak=%d overrun=%d",hits,peak,overrun);
 peak_strong=peak; peak=0; hits=0;
 @(negedge clk); restart=1; @(negedge clk); restart=0;
 for(n=0;n<10000;n=n+1) put(chirp >>> 7,1);
 for(n=0;n<2000;n=n+1) put(0,0);
 repeat(600) @(negedge clk);
 if(hits==0 || peak<6554 || peak+300<peak_strong || peak>peak_strong+300)
  $fatal(1,"normalization mismatch strong=%d weak=%d",peak_strong,peak);
 $display("PASS FIR and normalized LFM correlation: Q15 peaks strong=%0d weak=%0d",peak_strong,peak);
 hits=0;
 for(n=0;n<12000;n=n+1) put(1,0);
 repeat(600) @(negedge clk);
 if(hits!=0) $fatal(1,"low-energy floor did not suppress trigger");
 $display("PASS low-energy detection gating"); $finish;
end
initial begin #45000000; $fatal(1,"timeout"); end
endmodule
