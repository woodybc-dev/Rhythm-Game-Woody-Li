module seven_segment(
    input  wire [3:0] i,
    output reg  [6:0] o
);

// HEX out - rewire DE1
//  ---0---
// |       |
// 5       1
// |       |
//  ---6---
// |       |
// 4       2
// |       |
//  ---3---

always @(*) begin
    case (i)          // abcdefg (active-low: 0=ON, 1=OFF)
        4'd0:  o = 7'b1000000; // 0
        4'd1:  o = 7'b1111001; // 1
        4'd2:  o = 7'b0100100; // 2
        4'd3:  o = 7'b0110000; // 3
        4'd4:  o = 7'b0011001; // 4
        4'd5:  o = 7'b0010010; // 5
        4'd6:  o = 7'b0000010; // 6
        4'd7:  o = 7'b1111000; // 7
        4'd8:  o = 7'b0000000; // 8
        4'd9:  o = 7'b0010000; // 9

        // Codes for letters:
        4'd10: o = 7'b0001000; // A
        4'd11: o = 7'b0000011; // b
        4'd12: o = 7'b1000110; // C
        4'd13: o = 7'b0001110; // F
        4'd14: o = 7'b1111111; // blank

        default: o = 7'b1111111; // blank
    endcase
end

endmodule