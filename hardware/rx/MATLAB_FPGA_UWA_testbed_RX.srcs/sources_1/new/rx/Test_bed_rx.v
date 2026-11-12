// Prototype RX chain: 100 MHz fabric clock, 1 MHz AD9238 clock, 12-bit
// offset-binary input. DAC/ADC board timing must be verified on hardware.
module Test_bed_rx #(
 parameter integer PRE_SAMPLES=16000,
 parameter integer MIN_SEPARATION=50000,
 parameter integer MAX_SAMPLES=10100000,
 parameter integer POST_SAMPLES=12000
)(
 (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk_100m CLK",
    X_INTERFACE_PARAMETER = "XIL_INTERFACENAME clk_100m, ASSOCIATED_BUSIF m_axis, ASSOCIATED_RESET rst_n, FREQ_HZ 100000000" *)
 input wire clk_100m,
 (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst_n RST",
    X_INTERFACE_PARAMETER = "XIL_INTERFACENAME rst_n, POLARITY ACTIVE_LOW" *)
 input wire rst_n,
 input wire [11:0] adc_data_raw,
 (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 adc_clk CLK",
    X_INTERFACE_PARAMETER = "XIL_INTERFACENAME adc_clk, FREQ_HZ 1000000" *)
 output reg adc_clk,
 input wire [15:0] corr_threshold_q15, input wire [39:0] corr_min_energy,
 output wire [15:0] m_axis_tdata, output wire m_axis_tvalid,
 input wire m_axis_tready, output wire m_axis_tlast,
 output wire busy, output wire done, output wire error_timeout,
 output wire error_overflow, output wire error_processing_overrun,
 output wire [31:0] sample_count, output wire lfm_detected,
 output wire [15:0] corr_metric_q15, output wire corr_metric_valid);
reg [6:0] div;
reg adc_valid;
reg signed [15:0] adc_signed;
wire fir_valid; wire signed [15:0] fir_data;
wire fir_overrun, corr_overrun;
always @(posedge clk_100m) begin
 if(!rst_n) begin div<=0; adc_clk<=0; adc_valid<=0; adc_signed<=0; end
 else begin
  adc_valid<=0;
  if(div==49) adc_clk<=1;
  if(div==99) begin
   div<=0; adc_clk<=0; adc_valid<=1;
   adc_signed <= $signed({1'b0,adc_data_raw}) - 16'sd2048;
  end else div<=div+1'b1;
 end
end
rx_fir u_filter(.clk(clk_100m),.rst_n(rst_n),.in_valid(adc_valid),
 .in_data(adc_signed),.out_valid(fir_valid),.out_data(fir_data),.overrun(fir_overrun));
rx_lfm_corr u_corr(.clk(clk_100m),.rst_n(rst_n),.in_valid(fir_valid),.in_data(fir_data),
 .threshold_q15(corr_threshold_q15),.min_energy(corr_min_energy),
 .metric_valid(corr_metric_valid),.metric_q15(corr_metric_q15),
 .detected(lfm_detected),.overrun(corr_overrun));
rx_capture #(.PRE_SAMPLES(PRE_SAMPLES),.MIN_SEPARATION(MIN_SEPARATION),
 .MAX_SAMPLES(MAX_SAMPLES),.POST_SAMPLES(POST_SAMPLES)) u_capture(
 .clk(clk_100m),.rst_n(rst_n),.in_valid(fir_valid),.in_data(fir_data),
 .detected(lfm_detected),.m_axis_tdata(m_axis_tdata),.m_axis_tvalid(m_axis_tvalid),
 .m_axis_tready(m_axis_tready),.m_axis_tlast(m_axis_tlast),.busy(busy),.done(done),
 .timeout(error_timeout),.overflow(error_overflow),.sample_count(sample_count));
assign error_processing_overrun=fir_overrun|corr_overrun;
endmodule
