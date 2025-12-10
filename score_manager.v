module score_manager #(
    parameter integer TOTAL_NOTES = 32,          // total hit_pulses for full combo
    parameter integer MAX_SCORE   = 1000000      // target max = 1_000_000
)(
    input  wire clk,
    input  wire rst,         // active LOW 
    input  wire hit_pulse,   // 1-clock pulse per "hit unit"
    output reg  [19:0] score // 20 bits is enough for up to 1_048_575
);

    // Per-hit increment: must divide MAX_SCORE exactly!
    // For TOTAL_NOTES = 32 and MAX_SCORE = 1_000_000:
    // SCORE_STEP = 31_250 → 31_250 * 32 = 1_000_000
    parameter integer SCORE_STEP = MAX_SCORE / TOTAL_NOTES;

    // Use extended width to detect overflow and saturate at MAX_SCORE
    reg [20:0] next_score_ext;

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            score <= 20'd0;
        end else begin
            if (hit_pulse) begin
                // compute extended sum
                next_score_ext = score + SCORE_STEP;

                if (next_score_ext >= MAX_SCORE) begin
                    // saturate at MAX_SCORE
                    score <= MAX_SCORE[19:0];
                end else begin
                    score <= next_score_ext[19:0];
                end
            end
        end
    end

endmodule
