// 1 MHz sample enable, with a 22.5 kHz to 27.5 kHz frequency sweep.
module lfm_dds(input wire clk, input wire rst_n, input wire restart, input wire sample_en, output wire signed [15:0] sample);
localparam [47:0] START_WORD = 48'd6333186975990;
localparam [47:0] STEP_WORD  = 48'd140737488;
reg [47:0] phase_acc, freq_word;
sine_rom u_rom (.phase(phase_acc[47:38]), .sample(sample));
always @(posedge clk) begin
    if (!rst_n || restart) begin phase_acc <= 0; freq_word <= START_WORD; end
    else if (sample_en) begin phase_acc <= phase_acc + freq_word; freq_word <= freq_word + STEP_WORD; end
end
endmodule
