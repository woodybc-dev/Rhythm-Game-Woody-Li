// =====================================================
// vga_score_overlay
// - Draws 7-digit score using 3x5 font on virtual VGA
// - Works in "virtual pixels" (e.g., 160x120)
// - Digits: d6 d5 d4 d3 d2 d1 d0
// =====================================================
module vga_score_overlay #(
    parameter VIRTUAL_PIXEL_WIDTH  = 160,
    parameter VIRTUAL_PIXEL_HEIGHT = 120,

    // Top-left position of the first digit (d6) in virtual pixels
    parameter SCORE_X = 4,
    parameter SCORE_Y = 4,

    // Font size in virtual pixels
    parameter DIGIT_W = 3,
    parameter DIGIT_H = 5
)(
    input  wire [7:0] vx,   // current virtual x (0..VIRTUAL_PIXEL_WIDTH-1)
    input  wire [7:0] vy,   // current virtual y (0..VIRTUAL_PIXEL_HEIGHT-1)

    // Score digits: d6 d5 d4 d3 d2 d1 d0
    input  wire [3:0] d6,
    input  wire [3:0] d5,
    input  wire [3:0] d4,
    input  wire [3:0] d3,
    input  wire [3:0] d2,
    input  wire [3:0] d1,
    input  wire [3:0] d0,

    output reg        overlay_on,
    output reg [7:0]  overlay_r,
    output reg [7:0]  overlay_g,
    output reg [7:0]  overlay_b
);

    // 3x5 digit font: 15 bits, row-major, 3 bits per row
    // row0 = bits [14:12], row1 = [11:9], row2 = [8:6], row3 = [5:3], row4 = [2:0]
    function digit_pixel_on;
        input [3:0] digit;
        input [2:0] sx;   // 0..2
        input [2:0] sy;   // 0..4
        reg [14:0] pattern;
        integer idx;
    begin
        case (digit)
            4'd0: pattern = 15'b111_101_101_101_111;
            4'd1: pattern = 15'b001_001_001_001_001;
            4'd2: pattern = 15'b111_001_111_100_111;
            4'd3: pattern = 15'b111_001_111_001_111;
            4'd4: pattern = 15'b101_101_111_001_001;
            4'd5: pattern = 15'b111_100_111_001_111;
            4'd6: pattern = 15'b111_100_111_101_111;
            4'd7: pattern = 15'b111_001_001_001_001;
            4'd8: pattern = 15'b111_101_111_101_111;
            4'd9: pattern = 15'b111_101_111_001_111;
            default: pattern = 15'b000_000_000_000_000;
        endcase

        idx = sy * 3 + sx;        // 0..14
        digit_pixel_on = pattern[14 - idx];
    end
    endfunction

    // We'll draw 7 digits horizontally, each digit is 3 columns, plus 1 column spacing
    parameter DIGIT_STRIDE = DIGIT_W + 1;            // 4
    parameter TOTAL_WIDTH  = DIGIT_STRIDE * 7;       // 28 columns

    reg [7:0] px;          // x relative to SCORE_X
    reg [7:0] py;          // y relative to SCORE_Y
    reg [2:0] sx_digit;    // 0..2
    reg [2:0] sy_digit;    // 0..4
    reg [2:0] which_digit; // 0..6
    reg        pixel_on;
    reg [3:0]  cur_digit;

    always @(*) begin
        overlay_on = 1'b0;
        overlay_r  = 8'h00;
        overlay_g  = 8'h00;
        overlay_b  = 8'h00;
        pixel_on   = 1'b0;
        cur_digit  = 4'd0;

        // Check if we're inside the vertical span of the score text
        if (vy >= SCORE_Y && vy < (SCORE_Y + DIGIT_H) &&
            vx >= SCORE_X && vx < (SCORE_X + TOTAL_WIDTH)) begin

            px = vx - SCORE_X;     // 0..TOTAL_WIDTH-1
            py = vy - SCORE_Y;     // 0..DIGIT_H-1

            // which_digit = px / 4 (since DIGIT_STRIDE=4)
            which_digit = px[7:2];     // divide by 4
            sx_digit    = px[1:0];     // remainder mod 4 (0..3)

            // Only columns 0..2 inside the digit glyph;
            // column 3 is the spacing.
            if (which_digit < 7 && sx_digit < DIGIT_W) begin
                sy_digit = py[2:0];    // 0..4

                // Select the digit to draw
                case (which_digit)
                    3'd0: cur_digit = d6;
                    3'd1: cur_digit = d5;
                    3'd2: cur_digit = d4;
                    3'd3: cur_digit = d3;
                    3'd4: cur_digit = d2;
                    3'd5: cur_digit = d1;
                    3'd6: cur_digit = d0;
                    default: cur_digit = 4'd0;
                endcase

                pixel_on = digit_pixel_on(cur_digit, sx_digit, sy_digit);

                if (pixel_on) begin
                    overlay_on = 1'b1;
                    overlay_r  = 8'hFF;
                    overlay_g  = 8'hA0;
                    overlay_b  = 8'h20;  // orange-ish score color
                end
            end
        end
    end

endmodule