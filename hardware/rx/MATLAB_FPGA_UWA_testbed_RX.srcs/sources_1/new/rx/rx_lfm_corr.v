// 1000-point complex matched correlation, Q1.15 normalized power.
// Two taps are issued each clock; registered pipeline stages isolate memory,
// coefficient lookup, multiplication, pair addition, and accumulation.
module rx_lfm_corr(input wire clk, input wire rst_n,
 input wire in_valid, input wire signed [15:0] in_data,
 input wire [15:0] threshold_q15, input wire [39:0] min_energy,
 output reg metric_valid, output reg [15:0] metric_q15,
 output reg detected, output reg overrun);
`include "rx_lfm_coeff.vh"
localparam [23:0] REF_ENERGY=24'd16137542;
localparam [2:0] IDLE=0, ABS_STAGE=1, POWER_STAGE=2, SUM_STAGE=3,
                 CHECK_STAGE=4, DIV_STAGE=5;
reg signed [15:0] memory [0:999];
reg [9:0] wr, base, pair_index, filled;
reg [3:0] decim;
reg active, issuing, above;
reg [2:0] stage;
reg va,vd,vp,vs, la,ld,lp,ls;
reg [9:0] a0_reg,a1_reg,ix0_reg,ix1_reg;
reg signed [15:0] x0_reg,x1_reg;
reg signed [7:0] ci0_reg,ci1_reg,cq0_reg,cq1_reg;
reg signed [23:0] pi0_reg,pi1_reg,pq0_reg,pq1_reg;
reg [31:0] en0_reg,en1_reg;
reg signed [24:0] isum_reg,qsum_reg;
reg [32:0] esum_reg;
reg signed [39:0] acc_i,acc_q,final_i,final_q;
reg [39:0] acc_energy, final_energy, current_energy;
reg [31:0] abs_i,abs_q;
reg [63:0] power_i,power_q,den_product;
reg [64:0] numerator,den_final;
reg [64:0] remainder,denominator;
reg [14:0] quotient;
reg [3:0] div_count;
wire [9:0] ix0={pair_index[8:0],1'b0};
wire [9:0] ix1=ix0+1'b1;
wire [9:0] a0=base>=ix0 ? base-ix0 : ({1'b0,base}+11'd1000-{1'b0,ix0});
wire [9:0] a1=base>=ix1 ? base-ix1 : ({1'b0,base}+11'd1000-{1'b0,ix1});
wire signed [39:0] isum_ext={{15{isum_reg[24]}},isum_reg};
wire signed [39:0] qsum_ext={{15{qsum_reg[24]}},qsum_reg};
wire [65:0] twice_rem={remainder,1'b0};
wire [66:0] diff={1'b0,twice_rem}-{2'b0,denominator};
wire bit_out=!diff[66];
wire [65:0] rem_next=bit_out ? diff[65:0] : twice_rem;
wire [14:0] quo_next={quotient[13:0],bit_out};

always @(posedge clk) begin
 if(!rst_n) begin
  wr<=0; base<=0; pair_index<=0; filled<=0; decim<=0;
  active<=0; issuing<=0; stage<=IDLE;
  va<=0; vd<=0; vp<=0; vs<=0; la<=0; ld<=0; lp<=0; ls<=0;
  acc_i<=0; acc_q<=0; acc_energy<=0; final_i<=0; final_q<=0;
  final_energy<=0; current_energy<=0; abs_i<=0; abs_q<=0;
  power_i<=0; power_q<=0; den_product<=0; numerator<=0; den_final<=0;
  remainder<=0; denominator<=0; quotient<=0; div_count<=0;
  metric_q15<=0; metric_valid<=0; detected<=0; above<=0; overrun<=0;
 end else begin
  metric_valid<=0; detected<=0;
  if(in_valid) begin
   if(decim==9) begin
    decim<=0; memory[wr]<=in_data; base<=wr; wr<=wr==999 ? 0 : wr+1'b1;
    if(filled<1000) filled<=filled+1'b1;
    if(filled>=999) begin
     if(active || stage!=IDLE) overrun<=1;
     else begin active<=1; issuing<=1; pair_index<=0; acc_i<=0; acc_q<=0; acc_energy<=0; end
    end
   end else decim<=decim+1'b1;
  end
  // Address and coefficient index, then memory and coefficient reads.
  va<=issuing;
  if(issuing) begin
   a0_reg<=a0; a1_reg<=a1; ix0_reg<=ix0; ix1_reg<=ix1; la<=pair_index==499;
   if(pair_index==499) issuing<=0; else pair_index<=pair_index+1'b1;
  end
  vd<=va;
  if(va) begin
   x0_reg<=memory[a0_reg]; x1_reg<=memory[a1_reg];
   ci0_reg<=lfm_i(10'd999-ix0_reg); ci1_reg<=lfm_i(10'd999-ix1_reg);
   cq0_reg<=lfm_q(10'd999-ix0_reg); cq1_reg<=lfm_q(10'd999-ix1_reg); ld<=la;
  end
  vp<=vd;
  if(vd) begin
   pi0_reg<=x0_reg*ci0_reg; pi1_reg<=x1_reg*ci1_reg;
   pq0_reg<=x0_reg*cq0_reg; pq1_reg<=x1_reg*cq1_reg;
   en0_reg<=x0_reg*x0_reg; en1_reg<=x1_reg*x1_reg; lp<=ld;
  end
  vs<=vp;
  if(vp) begin
   isum_reg<=$signed({pi0_reg[23],pi0_reg})+$signed({pi1_reg[23],pi1_reg});
   qsum_reg<=$signed({pq0_reg[23],pq0_reg})+$signed({pq1_reg[23],pq1_reg});
   esum_reg<={1'b0,en0_reg}+{1'b0,en1_reg}; ls<=lp;
  end
  if(vs) begin
   if(ls) begin
    final_i<=acc_i+isum_ext; final_q<=acc_q+qsum_ext;
    final_energy<=acc_energy+esum_reg; active<=0; stage<=ABS_STAGE;
   end else begin
    acc_i<=acc_i+isum_ext; acc_q<=acc_q+qsum_ext; acc_energy<=acc_energy+esum_reg;
   end
  end
  case(stage)
   ABS_STAGE: begin
    // The bounded correlation magnitude fits 32 bits, as in the original.
    abs_i<=final_i[39] ? -final_i : final_i;
    abs_q<=final_q[39] ? -final_q : final_q;
    current_energy<=final_energy; stage<=POWER_STAGE;
   end
   POWER_STAGE: begin
    power_i<=abs_i*abs_i; power_q<=abs_q*abs_q;
    den_product<=current_energy*REF_ENERGY; stage<=SUM_STAGE;
   end
   SUM_STAGE: begin
    numerator<={1'b0,power_i}+{1'b0,power_q};
    den_final<={1'b0,den_product}; stage<=CHECK_STAGE;
   end
   CHECK_STAGE: begin
    if(current_energy==0 || den_final==0) begin
     metric_q15<=0; metric_valid<=1; above<=0; stage<=IDLE;
    end else if(numerator>=den_final) begin
     metric_q15<=16'd32768; metric_valid<=1; stage<=IDLE;
     if(threshold_q15!=0 && threshold_q15<=32768 && current_energy>=min_energy) begin
      if(!above) detected<=1; above<=1;
     end else above<=0;
    end else begin
     remainder<=numerator; denominator<=den_final; quotient<=0; div_count<=0; stage<=DIV_STAGE;
    end
   end
   DIV_STAGE: begin
    remainder<=rem_next[64:0]; quotient<=quo_next;
    if(div_count==14) begin
     stage<=IDLE; metric_q15<={1'b0,quo_next}; metric_valid<=1;
     if(threshold_q15!=0 && {1'b0,quo_next}>=threshold_q15 && current_energy>=min_energy) begin
      if(!above) detected<=1; above<=1;
     end else above<=0;
    end else div_count<=div_count+1'b1;
   end
   default: begin end
  endcase
 end
end
endmodule
