// 100 MHz synchronous output: signed 16-bit payload to unsigned 14-bit offset binary.
module Test_bed_tx (
    input wire clk_100m, input wire rst_n,
    input wire start, input wire [31:0] payload_samples,
    input wire signed [15:0] payload_data, input wire payload_valid,
    output wire payload_ready,
    output reg [13:0] dac_sample, output reg dac_sample_valid,
    output reg dac_clk, // 1 MHz: DAC rising edge 500 ns after data update
    output wire dac_wrt, // second synchronous clock output for the DAC write input
    output wire busy, output reg done, output reg error_underflow,
    output reg error_zero_length
);
localparam [2:0] IDLE=3'd0, LFM_HEAD=3'd1, GUARD_HEAD=3'd2, DATA=3'd3, GUARD_TAIL=3'd4, LFM_TAIL=3'd5;
reg [2:0] state;
reg [6:0] divider;
reg [13:0] lfm_count;
reg [14:0] guard_count;
reg [31:0] data_count, latched_length;
wire sample_tick = (divider == 7'd99);
// Empirical calibration: measured 2.5 Vpp at gain 7373; target 1.8 Vpp.
// 5309 / 7373 ~= 1.8 / 2.5; adjust after oscilloscope verification.
localparam signed [15:0] LFM_GAIN_Q15 = 16'sd5309;
wire signed [15:0] lfm_sample;
// Register the ROM output at 100 MHz to split the ROM-to-DSP timing path.
// The phase is held for 100 clocks per DAC sample, leaving ample settling time.
reg signed [15:0] lfm_sample_pipe;
always @(posedge clk_100m) begin
    if (!rst_n) lfm_sample_pipe <= 16'sd0;
    else lfm_sample_pipe <= lfm_sample;
end
wire signed [31:0] lfm_product = lfm_sample_pipe * LFM_GAIN_Q15;
wire signed [15:0] lfm_scaled = lfm_product >>> 15;
wire accept_start = (state == IDLE) && start && (payload_samples != 0);
wire restart_tail_lfm = (state == GUARD_TAIL) && sample_tick && (guard_count == 15'd29999);
assign dac_wrt = dac_clk;
assign busy = (state != IDLE);
assign payload_ready = (state == DATA) && sample_tick;
lfm_dds u_lfm (.clk(clk_100m), .rst_n(rst_n), .restart(accept_start || restart_tail_lfm),
                .sample_en(((state == LFM_HEAD) || (state == LFM_TAIL)) && sample_tick), .sample(lfm_sample));
always @(posedge clk_100m) begin
    if (!rst_n) begin
        divider <= 0; dac_clk <= 1'b0; state <= IDLE; lfm_count <= 0; guard_count <= 0; data_count <= 0;
        latched_length <= 0; dac_sample <= 14'd8192; dac_sample_valid <= 0;
        done <= 0; error_underflow <= 0; error_zero_length <= 0;
    end else begin
        if (sample_tick) begin
            divider <= 0;
            dac_clk <= 1'b0; // data changes on this edge
        end else begin
            divider <= divider + 1'b1;
            if (divider == 7'd49) dac_clk <= 1'b1;
        end
        dac_sample_valid <= 0;
        case (state)
            IDLE: begin
                if (sample_tick) begin dac_sample <= 14'd8192; dac_sample_valid <= 1; end
                if (start) begin
                    done <= 0; // hold completion until the next idle-state start or reset
                    error_underflow <= 0; error_zero_length <= (payload_samples == 0);
                    if (payload_samples != 0) begin
                        latched_length <= payload_samples;
                        lfm_count <= 0; guard_count <= 0; data_count <= 0; state <= LFM_HEAD;
                    end
                end
            end
            LFM_HEAD: if (sample_tick) begin
                // Phase zero produces midscale; bypass stale pipeline on the first tick.
                dac_sample <= (lfm_count == 0) ? 14'd8192 : {~lfm_scaled[15], lfm_scaled[14:2]}; dac_sample_valid <= 1;
                if (lfm_count == 14'd9999) begin guard_count <= 0; state <= GUARD_HEAD; end
                else lfm_count <= lfm_count + 1'b1;
            end
            GUARD_HEAD: if (sample_tick) begin
                dac_sample <= 14'd8192; dac_sample_valid <= 1;
                if (guard_count == 15'd29999) begin guard_count <= 0; state <= DATA; end
                else guard_count <= guard_count + 1'b1;
            end
            DATA: if (sample_tick) begin
                dac_sample_valid <= 1;
                if (!payload_valid) begin
                    dac_sample <= 14'd8192; error_underflow <= 1; state <= IDLE;
                end else begin
                    dac_sample <= {~payload_data[15], payload_data[14:2]};
                    if (data_count == latched_length - 1'b1) begin guard_count <= 0; state <= GUARD_TAIL; end
                    else data_count <= data_count + 1'b1;
                end
            end
            GUARD_TAIL: if (sample_tick) begin
                dac_sample <= 14'd8192; dac_sample_valid <= 1;
                if (guard_count == 15'd29999) begin lfm_count <= 0; state <= LFM_TAIL; end
                else guard_count <= guard_count + 1'b1;
            end
            LFM_TAIL: if (sample_tick) begin
                // Phase zero produces midscale; bypass stale pipeline on the first tick.
                dac_sample <= (lfm_count == 0) ? 14'd8192 : {~lfm_scaled[15], lfm_scaled[14:2]}; dac_sample_valid <= 1;
                if (lfm_count == 14'd9999) begin state <= IDLE; done <= 1; end
                else lfm_count <= lfm_count + 1'b1;
            end
            default: state <= IDLE;
        endcase
    end
end
endmodule
