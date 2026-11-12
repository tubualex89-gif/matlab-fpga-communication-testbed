`timescale 1ns / 1ps
// 32-bit AXI4-Lite receiver control; all user signals use S_AXI_ACLK.
module ps_ctrl_slave_lite_v1_0_S00_AXI #(
 parameter integer C_S_AXI_DATA_WIDTH=32,
 parameter integer C_S_AXI_ADDR_WIDTH=7
)(
 output reg [15:0] rx_corr_threshold_q15,
 output reg [39:0] rx_corr_min_energy,
 input wire rx_busy, input wire rx_done, input wire rx_error_timeout,
 input wire rx_error_overflow, input wire rx_error_processing_overrun,
 input wire [31:0] rx_sample_count,
 input wire [15:0] rx_corr_metric_q15, input wire rx_corr_metric_valid,
 input wire S_AXI_ACLK, input wire S_AXI_ARESETN,
 input wire [C_S_AXI_ADDR_WIDTH-1:0] S_AXI_AWADDR, input wire [2:0] S_AXI_AWPROT,
 input wire S_AXI_AWVALID, output wire S_AXI_AWREADY,
 input wire [C_S_AXI_DATA_WIDTH-1:0] S_AXI_WDATA,
 input wire [(C_S_AXI_DATA_WIDTH/8)-1:0] S_AXI_WSTRB,
 input wire S_AXI_WVALID, output wire S_AXI_WREADY,
 output reg [1:0] S_AXI_BRESP, output reg S_AXI_BVALID, input wire S_AXI_BREADY,
 input wire [C_S_AXI_ADDR_WIDTH-1:0] S_AXI_ARADDR, input wire [2:0] S_AXI_ARPROT,
 input wire S_AXI_ARVALID, output wire S_AXI_ARREADY,
 output reg [C_S_AXI_DATA_WIDTH-1:0] S_AXI_RDATA,
 output wire [1:0] S_AXI_RRESP, output reg S_AXI_RVALID, input wire S_AXI_RREADY
);
// Byte offsets: 00 STATUS_CLEAR, 04 Q15, 08 ENERGY_LO, 0c ENERGY_HI,
// 10 STATUS, 14 LAST_SAMPLE_COUNT, 18 LAST_METRIC, 1c COMPLETED_COUNT.
// Configuration writes update shadows; write 1 to 20 to apply atomically when idle.
// 24: generation, 28/2c/30: active values, 34: configuration protocol ID.
// Undefined/read-only writes return SLVERR. Undefined reads return zero/OKAY.
reg aw_pending, w_pending;
reg [C_S_AXI_ADDR_WIDTH-1:0] aw_addr;
reg [31:0] w_data;
reg [3:0] w_strb;
reg [15:0] threshold_shadow;
reg [39:0] energy_shadow;
reg config_pending;
reg [31:0] config_generation;
reg [15:0] last_metric;
reg [31:0] completed_count, last_sample_count;
reg done_sticky, timeout_sticky, overflow_sticky;
assign S_AXI_AWREADY = !aw_pending && !S_AXI_BVALID;
assign S_AXI_WREADY  = !w_pending && !S_AXI_BVALID;
assign S_AXI_ARREADY = !S_AXI_RVALID;
assign S_AXI_RRESP = 2'b00;
wire wr_commit=aw_pending && w_pending && !S_AXI_BVALID;

always @(posedge S_AXI_ACLK) begin
 if(!S_AXI_ARESETN) begin
  aw_pending<=0; w_pending<=0; aw_addr<=0; w_data<=0; w_strb<=0;
  S_AXI_BRESP<=0; S_AXI_BVALID<=0; S_AXI_RDATA<=0; S_AXI_RVALID<=0;
  rx_corr_threshold_q15<=16'd6554; rx_corr_min_energy<=40'd100000;
  threshold_shadow<=16'd6554; energy_shadow<=40'd100000;
  config_pending<=0; config_generation<=0;
  last_metric<=0; completed_count<=0; last_sample_count<=0;
  done_sticky<=0; timeout_sticky<=0; overflow_sticky<=0;
 end else begin
  if(rx_corr_metric_valid) last_metric<=rx_corr_metric_q15;
  if(S_AXI_AWVALID && S_AXI_AWREADY) begin aw_addr<=S_AXI_AWADDR; aw_pending<=1; end
  if(S_AXI_WVALID && S_AXI_WREADY) begin w_data<=S_AXI_WDATA; w_strb<=S_AXI_WSTRB; w_pending<=1; end
  if(S_AXI_BVALID && S_AXI_BREADY) S_AXI_BVALID<=0;
  if(wr_commit) begin
   aw_pending<=0; w_pending<=0; S_AXI_BVALID<=1; S_AXI_BRESP<=2'b00;
   case(aw_addr)
    7'h00: begin
     if(w_strb[0] && w_data[0]) begin done_sticky<=0; timeout_sticky<=0; overflow_sticky<=0; end
    end
    7'h04: begin
     if(w_strb[0]) threshold_shadow[7:0]<=w_data[7:0];
     if(w_strb[1]) threshold_shadow[15:8]<=w_data[15:8];
    end
    7'h08: begin
     if(w_strb[0]) energy_shadow[7:0]<=w_data[7:0];
     if(w_strb[1]) energy_shadow[15:8]<=w_data[15:8];
     if(w_strb[2]) energy_shadow[23:16]<=w_data[23:16];
     if(w_strb[3]) energy_shadow[31:24]<=w_data[31:24];
    end
    7'h0c: if(w_strb[0]) energy_shadow[39:32]<=w_data[7:0];
    7'h20: if(w_strb[0] && w_data[0]) config_pending<=1;
    default: S_AXI_BRESP<=2'b10;
   endcase
  end
  // busy includes a head-detection pulse, so a capture cannot start in the
  // same cycle as a configuration commit. One request may be outstanding.
  if(config_pending && !rx_busy && !(wr_commit && aw_addr==7'h20 && w_strb[0] && w_data[0])) begin
   rx_corr_threshold_q15<=threshold_shadow; rx_corr_min_energy<=energy_shadow;
   config_pending<=0; config_generation<=config_generation+1'b1;
  end
  if(S_AXI_RVALID && S_AXI_RREADY) S_AXI_RVALID<=0;
  if(S_AXI_ARVALID && S_AXI_ARREADY) begin
   S_AXI_RVALID<=1;
   case(S_AXI_ARADDR)
    7'h00: S_AXI_RDATA<=0;
    7'h04: S_AXI_RDATA<={16'd0,threshold_shadow};
    7'h08: S_AXI_RDATA<=energy_shadow[31:0];
    7'h0c: S_AXI_RDATA<={24'd0,energy_shadow[39:32]};
    7'h10: S_AXI_RDATA<={27'd0,rx_error_processing_overrun,overflow_sticky,timeout_sticky,done_sticky,rx_busy};
    7'h14: S_AXI_RDATA<=last_sample_count;
    7'h18: S_AXI_RDATA<={16'd0,last_metric};
    7'h1c: S_AXI_RDATA<=completed_count;
    7'h20: S_AXI_RDATA<={31'd0,config_pending};
    7'h24: S_AXI_RDATA<=config_generation;
    7'h28: S_AXI_RDATA<={16'd0,rx_corr_threshold_q15};
    7'h2c: S_AXI_RDATA<=rx_corr_min_energy[31:0];
    7'h30: S_AXI_RDATA<={24'd0,rx_corr_min_energy[39:32]};
    7'h34: S_AXI_RDATA<=32'h52584331;
    default: S_AXI_RDATA<=0;
   endcase
  end
  // Event wins over a simultaneous software clear; retain count and length.
  if(rx_done) begin
   done_sticky<=1; timeout_sticky<=timeout_sticky|rx_error_timeout;
   overflow_sticky<=overflow_sticky|rx_error_overflow;
   last_sample_count<=rx_sample_count;
   if(completed_count!=32'hffffffff) completed_count<=completed_count+1'b1;
  end
 end
end
endmodule
