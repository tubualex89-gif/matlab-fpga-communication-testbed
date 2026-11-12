// 321-tap FIR. Four taps issued per clock, with registered computation stages.
// With continuous 1 MHz samples at 100 MHz, each output completes in <100 clocks.
module rx_fir(input wire clk, input wire rst_n, input wire in_valid,
 input wire signed [15:0] in_data, output reg out_valid,
 output reg signed [15:0] out_data, output reg overrun);
`include "rx_fir_coeff.vh"
reg signed [15:0] history [0:320];
reg [8:0] wr, base;
reg [6:0] group_index;
reg active, issuing;
reg va,vd,vp,vs,vt,la,ld,lp,ls,lt,final_valid;
reg [8:0] a0,a1,a2,a3,i0r,i1r,i2r,i3r;
reg signed [15:0] x0,x1,x2,x3,c0,c1,c2,c3;
reg signed [31:0] p0,p1,p2,p3;
reg signed [32:0] pair0,pair1;
reg signed [33:0] group_sum;
reg signed [47:0] accum,final_sum;
wire [8:0] i0={group_index,2'b00}, i1=i0+1'b1, i2=i0+2'd2, i3=i0+2'd3;
wire signed [47:0] group_extended={{14{group_sum[33]}},group_sum};
function [8:0] addr;
 input [8:0] b, i;
 begin
  if(i>320) addr=0;
  else if(b>=i) addr=b-i;
  else addr={1'b0,b}+10'd321-{1'b0,i};
 end
endfunction
integer j;
always @(posedge clk) begin
 if(!rst_n) begin
  wr<=0; base<=0; group_index<=0; active<=0; issuing<=0; accum<=0;
  va<=0; vd<=0; vp<=0; vs<=0; vt<=0;
  la<=0; ld<=0; lp<=0; ls<=0; lt<=0; final_valid<=0; final_sum<=0;
  out_valid<=0; out_data<=0; overrun<=0;
  for(j=0;j<321;j=j+1) history[j]<=0;
 end else begin
  out_valid<=0;
  if(in_valid) begin
   if(active) overrun<=1;
   else begin
    history[wr]<=in_data; base<=wr; wr <= (wr==320)?0:wr+1'b1;
    group_index<=0; accum<=0; active<=1; issuing<=1;
   end
  end
  va<=issuing;
  if(issuing) begin
   a0<=addr(base,i0); a1<=addr(base,i1); a2<=addr(base,i2); a3<=addr(base,i3);
   i0r<=i0; i1r<=i1; i2r<=i2; i3r<=i3; la<=group_index==80;
   if(group_index==80) issuing<=0; else group_index<=group_index+1'b1;
  end
  vd<=va;
  if(va) begin
   x0<=history[a0]; x1<=history[a1]; x2<=history[a2]; x3<=history[a3];
   c0<=fir_coef(i0r); c1<=fir_coef(i1r); c2<=fir_coef(i2r); c3<=fir_coef(i3r); ld<=la;
  end
  vp<=vd;
  if(vd) begin p0<=x0*c0; p1<=x1*c1; p2<=x2*c2; p3<=x3*c3; lp<=ld; end
  vs<=vp;
  if(vp) begin
   pair0<=$signed({p0[31],p0})+$signed({p1[31],p1});
   pair1<=$signed({p2[31],p2})+$signed({p3[31],p3}); ls<=lp;
  end
  vt<=vs;
  if(vs) begin group_sum<=$signed({pair0[32],pair0})+$signed({pair1[32],pair1}); lt<=ls; end
  final_valid<=0;
  if(vt) begin
   if(lt) begin final_sum<=accum+group_extended; final_valid<=1; end
   else accum<=accum+group_extended;
  end
  if(final_valid) begin
   active<=0; out_valid<=1;
   if ((final_sum >>> 15) > 32767) out_data<=16'sh7fff;
   else if ((final_sum >>> 15) < -32768) out_data<=-16'sd32768;
   else out_data<=final_sum >>> 15;
  end
 end
end
endmodule
