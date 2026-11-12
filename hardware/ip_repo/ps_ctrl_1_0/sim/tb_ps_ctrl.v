`timescale 1ns/1ps
module tb_ps_ctrl;
reg clk=0,rstn=0;
reg [6:0] awaddr=0,araddr=0; reg awvalid=0,wvalid=0,bready=0,arvalid=0,rready=0;
reg [31:0] wdata=0; reg [3:0] wstrb=0;
wire awready,wready,bvalid,arready,rvalid; wire [1:0] bresp,rresp; wire [31:0] rdata;
wire [15:0] threshold; wire [39:0] energy;
reg busy=0,done=0,timeout=0,overflow=0,processing=0,hit=0,mvalid=0;
reg [31:0] samples=0; reg [15:0] metric=0;
always #5 clk=~clk;
ps_ctrl dut(.rx_corr_threshold_q15(threshold),.rx_corr_min_energy(energy),
 .rx_busy(busy),.rx_done(done),.rx_error_timeout(timeout),.rx_error_overflow(overflow),
 .rx_error_processing_overrun(processing),.rx_sample_count(samples),
 .rx_corr_metric_q15(metric),.rx_corr_metric_valid(mvalid),
 .s00_axi_aclk(clk),.s00_axi_aresetn(rstn),.s00_axi_awaddr(awaddr),.s00_axi_awprot(3'd0),
 .s00_axi_awvalid(awvalid),.s00_axi_awready(awready),.s00_axi_wdata(wdata),.s00_axi_wstrb(wstrb),
 .s00_axi_wvalid(wvalid),.s00_axi_wready(wready),.s00_axi_bresp(bresp),.s00_axi_bvalid(bvalid),
 .s00_axi_bready(bready),.s00_axi_araddr(araddr),.s00_axi_arprot(3'd0),.s00_axi_arvalid(arvalid),
 .s00_axi_arready(arready),.s00_axi_rdata(rdata),.s00_axi_rresp(rresp),.s00_axi_rvalid(rvalid),.s00_axi_rready(rready));
task send_aw(input [6:0] addr, input integer delay_cycles);
 begin repeat(delay_cycles) @(negedge clk); @(negedge clk); awaddr=addr; awvalid=1;
  do @(posedge clk); while(!awready); @(negedge clk); awvalid=0; end
endtask
task send_w(input [31:0] data, input [3:0] st, input integer delay_cycles);
 begin repeat(delay_cycles) @(negedge clk); @(negedge clk); wdata=data; wstrb=st; wvalid=1;
  do @(posedge clk); while(!wready); @(negedge clk); wvalid=0; end
endtask
task write_reg(input [6:0] addr,input [31:0] data,input [3:0] st,input integer da,input integer dw,input [1:0] expected);
 begin
  fork send_aw(addr,da); send_w(data,st,dw); join
  wait(bvalid); if(bresp!==expected) $fatal(1,"bad BRESP addr %h got %b",addr,bresp);
  repeat(4) begin @(negedge clk); if(!bvalid || bresp!==expected) $fatal(1,"B response not held"); end
  bready=1; @(negedge clk); bready=0;
 end
endtask
task read_reg(input [6:0] addr,input [31:0] expected);
 begin @(negedge clk); araddr=addr; arvalid=1;
  do @(posedge clk); while(!arready); @(negedge clk); arvalid=0; wait(rvalid);
  if(rdata!==expected || rresp!=0) $fatal(1,"bad read %h: got %h expected %h",addr,rdata,expected);
  repeat(2) begin @(negedge clk); if(!rvalid || rdata!==expected) $fatal(1,"R not held"); end
  rready=1; @(negedge clk); rready=0;
 end
endtask
initial begin
 repeat(5) @(negedge clk); rstn=1;
 read_reg(7'h04,32'd6554); read_reg(7'h08,32'd100000);
 write_reg(7'h04,32'h00001234,4'b0011,0,5,0); read_reg(7'h04,32'h1234);
 write_reg(7'h04,32'h0000ab00,4'b0010,5,0,0); read_reg(7'h04,32'hab34);
 write_reg(7'h08,32'h12345678,4'hf,0,0,0); write_reg(7'h0c,32'h0000009a,4'h1,0,0,0);
 if(energy!==40'h9a12345678) $fatal(1,"energy incorrect");
 busy=1; timeout=1; overflow=1; processing=1; samples=32'd12345;
 @(negedge clk); done=1; @(negedge clk); done=0;
 read_reg(7'h10,32'h1f); read_reg(7'h14,32'd12345);
 write_reg(7'h04,32'd1,4'hf,0,0,2'b10);
 if(threshold!==16'hab34) $fatal(1,"busy write altered state");
 @(negedge clk); hit=1; mvalid=1; metric=16'd1234; @(negedge clk); hit=0; mvalid=0;
 read_reg(7'h18,32'd1234); read_reg(7'h1c,32'd1);
 write_reg(7'h10,32'hffffffff,4'hf,0,0,2'b10);
 busy=0; write_reg(7'h00,1,4'h1,0,0,0); read_reg(7'h10,32'h10); read_reg(7'h1c,1);
 write_reg(7'h04,32'd6554,4'hf,0,0,0); read_reg(7'h04,32'd6554);
 $display("PASS AXI ordering, byte enables, sticky completion, status clear, busy rejection"); $finish;
end
initial begin #100000; $fatal(1,"timeout"); end
endmodule
