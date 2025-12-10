module vga_chart_label_overlay #(
    parameter VIRTUAL_PIXEL_WIDTH  = 160,
    parameter VIRTUAL_PIXEL_HEIGHT = 120,
    parameter LABEL_X              = 8'd4,   // text position X in virtual pixels
    parameter LABEL_Y              = 8'd14,  // text position Y (below score)
    parameter CHAR_W               = 3,      // 3x5 font width
    parameter CHAR_H               = 5,      // 3x5 font height
    parameter CHAR_GAP             = 1       // 1-pixel horizontal gap
)(
    input  wire [7:0] vx,   // virtual x (0..VIRTUAL_PIXEL_WIDTH-1)
    input  wire [7:0] vy,   // virtual y (0..VIRTUAL_PIXEL_HEIGHT-1)
    input  wire [3:0] chart_digit,   // 0..9, we will use 1 for "CHART 1"

    output reg        overlay_on,
    output reg [7:0]  overlay_r,
    output reg [7:0]  overlay_g,
    output reg [7:0]  overlay_b
);

    // 6 characters total: C H A R T [digit]
    parameter NUM_CHARS = 6;
    parameter CELL_W    = CHAR_W + CHAR_GAP;              // width of one char cell (glyph + gap)
    parameter TOTAL_W   = NUM_CHARS * CELL_W;             // total width in virtual pixels

    // glyph codes:
    //  0..9   : digits '0'..'9'
    //  10 = C
    //  11 = H
    //  12 = A
    //  13 = R
    //  14 = T
    function glyph_pixel;
        input [3:0] code;    // which glyph
        input [2:0] sx;      // 0..CHAR_W-1 (0..2)
        input [2:0] sy;      // 0..CHAR_H-1 (0..4)
        reg  [14:0] pattern; // 3x5 bits, row-major, [14] = top-left
        integer idx;
    begin
        case (code)
            // Digits 3x5 (row-major: row0,row1,... each 3 bits)
            // 0
            4'd0:  pattern = 15'b111_101_101_101_111;
            // 1
            4'd1:  pattern = 15'b010_110_010_010_111;
            // 2
            4'd2:  pattern = 15'b111_001_111_100_111;
            // 3
            4'd3:  pattern = 15'b111_001_111_001_111;
            // 4
            4'd4:  pattern = 15'b101_101_111_001_001;
            // 5
            4'd5:  pattern = 15'b111_100_111_001_111;
            // 6
            4'd6:  pattern = 15'b111_100_111_101_111;
            // 7
            4'd7:  pattern = 15'b111_001_010_010_010;
            // 8
            4'd8:  pattern = 15'b111_101_111_101_111;
            // 9
            4'd9:  pattern = 15'b111_101_111_001_111;

            // Letters 3x5
            // C
            4'd10: pattern = 15'b111_100_100_100_111;
            // H
            4'd11: pattern = 15'b101_101_111_101_101;
            // A
            4'd12: pattern = 15'b111_101_111_101_101;
            // R
            4'd13: pattern = 15'b110_101_110_101_101;
            // T
            4'd14: pattern = 15'b111_010_010_010_010;

            default: pattern = 15'b000_000_000_000_000;
        endcase

        idx = sy * CHAR_W + sx;  // 0..14
        glyph_pixel = pattern[14 - idx];
    end
    endfunction

    always @(*) begin
        overlay_on = 1'b0;
        overlay_r  = 8'h00;
        overlay_g  = 8'h00;
        overlay_b  = 8'h00;

        // Check if we're inside the "CHART X" bounding box
        if (vx >= LABEL_X && vx < LABEL_X + TOTAL_W &&
            vy >= LABEL_Y && vy < LABEL_Y + CHAR_H) begin

            reg [7:0] px;
            reg [7:0] py;
            reg [7:0] cell_x;
            reg [2:0] col_idx;
            reg [2:0] sx;
            reg [2:0] sy;
            reg [3:0] code;
            reg       pix_on;

            // Local coords inside the label
            px = vx - LABEL_X;      // 0 .. TOTAL_W-1
            py = vy - LABEL_Y;      // 0 .. CHAR_H-1

            // Which character cell are we in?
            cell_x  = px / CELL_W;          // 0..NUM_CHARS-1
            col_idx = cell_x[2:0];          // safe since NUM_CHARS=6

            // X inside the cell
            sx = px % CELL_W;              // 0..CELL_W-1

            // If we're in the gap area, no pixel
            if (sx >= CHAR_W) begin
                pix_on = 1'b0;
            end else begin
                sy = py[2:0];              // 0..4

                // Map char index to glyph code
                // "CHART" + digit
                case (col_idx)
                    3'd0: code = 4'd10;           // C
                    3'd1: code = 4'd11;           // H
                    3'd2: code = 4'd12;           // A
                    3'd3: code = 4'd13;           // R
                    3'd4: code = 4'd14;           // T
                    3'd5: code = chart_digit;     // digit
                    default: code = 4'd10;
                endcase

                pix_on = glyph_pixel(code, sx, sy);
            end

            if (pix_on) begin
                overlay_on = 1'b1;
                // Bright yellow-ish label color
                overlay_r  = 8'hFF;
                overlay_g  = 8'hE0;
                overlay_b  = 8'h40;
            end
        end
    end

endmodule

