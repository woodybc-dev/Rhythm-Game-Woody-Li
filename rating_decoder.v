// =====================================================
// rating_decoder
// - Input: score (0..1,000,000)
// - Output: two 4-bit codes for seven_segment (HEX5, HEX4)
//   using extended codes:
//     13 = F, 12 = C, 11 = b, 10 = A, 5 = "S", 14 = blank
// =====================================================
module rating_decoder (
    input  wire [19:0] score,
    output reg  [3:0]  rating_hi,   // HEX5
    output reg  [3:0]  rating_lo    // HEX4
);

    always @(*) begin
        // default: blank
        rating_hi = 4'd14;   // blank
        rating_lo = 4'd14;   // blank

        if (score == 20'd1000000) begin
            // SS -> "55"
            rating_hi = 4'd5;    // S
            rating_lo = 4'd5;    // S
        end
        else if (score >= 20'd900000) begin
            // S
            rating_hi = 4'd14;   // blank
            rating_lo = 4'd5;    // S (as 5)
        end
        else if (score >= 20'd850000) begin
            // A
            rating_hi = 4'd14;   // blank
            rating_lo = 4'd10;   // A
        end
        else if (score >= 20'd800000) begin
            // b
            rating_hi = 4'd14;   // blank
            rating_lo = 4'd11;   // b
        end
        else if (score >= 20'd700000) begin
            // C
            rating_hi = 4'd14;   // blank
            rating_lo = 4'd12;   // C
        end
        else begin
            // F
            rating_hi = 4'd14;   // blank
            rating_lo = 4'd13;   // F
        end
    end

endmodule