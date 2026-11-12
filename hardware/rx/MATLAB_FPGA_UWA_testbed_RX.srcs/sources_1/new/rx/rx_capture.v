// Pre-trigger circular buffer and AXI-Stream-like output. All clocks are 100 MHz.
// Automatically monitors after reset and re-enters monitoring after each frame.
module rx_capture #(
 parameter integer BUFFER_BITS=15,
 parameter integer PRE_SAMPLES=16000,
 parameter integer MIN_SEPARATION=50000,
 parameter integer MAX_SAMPLES=10100000,
 parameter integer POST_SAMPLES=12000
)(input wire clk, input wire rst_n,
 input wire in_valid, input wire signed [15:0] in_data, input wire detected,
 output reg [15:0] m_axis_tdata, output reg m_axis_tvalid,
 input wire m_axis_tready, output reg m_axis_tlast,
 output wire busy, output reg done, output reg timeout, output reg overflow,
 output reg [31:0] sample_count);
localparam integer CAPACITY=1<<BUFFER_BITS;
localparam [2:0] WAIT_HEAD=1, RECORD=2, POST=3, DRAIN=4;
reg [2:0] state;
(* ram_style="block" *) reg [15:0] mem [0:CAPACITY-1];
reg [63:0] written, rd, stop_at;
reg [31:0] since_head, post_count, history_count;
// Assert busy on the head-detection cycle to interlock configuration commits.
assign busy=(state!=WAIT_HEAD) || detected;
// done is a one-clock event; errors persist until the next detected frame.
always @(posedge clk) begin
 if(!rst_n) begin
  state<=WAIT_HEAD; written<=0; rd<=0; stop_at<=0; since_head<=0; post_count<=0; history_count<=0;
  m_axis_tvalid<=0; m_axis_tdata<=0; m_axis_tlast<=0;
  done<=0; timeout<=0; overflow<=0; sample_count<=0;
 end else begin
  done<=0;
  if(state==WAIT_HEAD || state==RECORD || state==POST) begin
   if(in_valid) begin
    if(state!=WAIT_HEAD && written-rd>=CAPACITY) begin
     overflow<=1; stop_at<=written; state<=DRAIN;
    end else begin
     mem[written[BUFFER_BITS-1:0]]<=in_data; written<=written+1'b1;
     if(state==WAIT_HEAD && history_count<PRE_SAMPLES) history_count<=history_count+1'b1;
     if(state==RECORD || state==POST) begin
      since_head<=since_head+1'b1; sample_count<=sample_count+1'b1;
      if(since_head>=MAX_SAMPLES-1) begin
       timeout<=1; stop_at<=written+1'b1; state<=DRAIN;
      end else if(state==POST) begin
       if(post_count>=POST_SAMPLES-1) begin stop_at<=written+1'b1; state<=DRAIN; end
       else post_count<=post_count+1'b1;
      end
     end
    end
   end
   if(state==WAIT_HEAD && detected) begin
    state<=RECORD; since_head<=0; timeout<=0; overflow<=0;
    rd<=written-history_count; sample_count<=history_count+(in_valid ? 1 : 0);
   end else if(state==RECORD && detected && since_head>=MIN_SEPARATION &&
               !(in_valid && (since_head>=MAX_SAMPLES-1 || written-rd>=CAPACITY))) begin
    state<=POST; post_count<=0;
   end
  end
  // Keep the newest sample buffered until the final address is known, so TLAST
  // is never attached retroactively to an already-consumed sample.
  if(state==RECORD || state==POST || state==DRAIN) begin
   if(!m_axis_tvalid || m_axis_tready) begin
    if((state==DRAIN && rd<stop_at) || (state!=DRAIN && rd+1<written)) begin
     m_axis_tdata<=mem[rd[BUFFER_BITS-1:0]];
     m_axis_tvalid<=1; m_axis_tlast<=(state==DRAIN && rd+1==stop_at);
     rd<=rd+1'b1;
    end else begin m_axis_tvalid<=0; m_axis_tlast<=0; end
   end
   if(state==DRAIN && m_axis_tvalid && m_axis_tready && m_axis_tlast) begin
    state<=WAIT_HEAD; written<=0; rd<=0; history_count<=0; done<=1;
    m_axis_tvalid<=0; m_axis_tlast<=0;
   end
  end
 end
end
endmodule
