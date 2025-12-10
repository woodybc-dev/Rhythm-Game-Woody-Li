// =====================================================
// score_to_digits
// - Converts binary score (0–1,000,000) into 7 decimal digits
//   d6 d5 d4 d3 d2 d1 d0
// - d6 is the millions digit (0 or 1 in this design)
// =====================================================
module score_to_digits (
    input  wire [19:0] score,   // 0–1,000,000 (fits in 20 bits)
    output reg  [3:0]  d6,      // millions
    output reg  [3:0]  d5,      // hundred-thousands
    output reg  [3:0]  d4,
    output reg  [3:0]  d3,
    output reg  [3:0]  d2,
    output reg  [3:0]  d1,
    output reg  [3:0]  d0       // ones
);

    reg [19:0] temp;

    always @(*) begin
        temp = score;

        d6 = temp / 20'd1000000; temp = temp % 20'd1000000;
        d5 = temp / 20'd100000;  temp = temp % 20'd100000;
        d4 = temp / 20'd10000;   temp = temp % 20'd10000;
        d3 = temp / 20'd1000;    temp = temp % 20'd1000;
        d2 = temp / 20'd100;     temp = temp % 20'd100;
        d1 = temp / 20'd10;      temp = temp % 20'd10;
        d0 = temp;
    end

endmodule