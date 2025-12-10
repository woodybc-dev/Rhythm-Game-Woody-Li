module vga_end_screen_overlay #(
    parameter VIRTUAL_PIXEL_WIDTH  = 160,
    parameter VIRTUAL_PIXEL_HEIGHT = 120,
    parameter TEXT_X               = 24,   // left margin in virtual pixels
    parameter FIRST_LINE_Y         = 32,   // top line Y
    parameter CHAR_W               = 3,
    parameter CHAR_H               = 5,
    parameter CHAR_GAP             = 1,
    parameter LINE_GAP             = 1,
    parameter MAX_CHARS            = 24
)(
    input  wire        end_mode,       // 1: draw end screen
    input  wire [7:0]  vx,             // virtual x
    input  wire [7:0]  vy,             // virtual y

    // Info for text
    input  wire [19:0] score_value,    // raw score
    input  wire [3:0]  score_d6,
    input  wire [3:0]  score_d5,
    input  wire [3:0]  score_d4,
    input  wire [3:0]  score_d3,
    input  wire [3:0]  score_d2,
    input  wire [3:0]  score_d1,
    input  wire [3:0]  score_d0,

    input  wire [6:0]  hit_count,      // 0..99
    input  wire        chart_select,   // 0 = chart 1, 1 = chart 2
    input  wire [1:0]  note_speed,     // 1x,2x,3x

    output reg         overlay_on,
    output reg [7:0]   overlay_r,
    output reg [7:0]   overlay_g,
    output reg [7:0]   overlay_b
);

    // Derived constants
    localparam integer CELL_W     = CHAR_W + CHAR_GAP;
    localparam integer LINE_H     = CHAR_H + LINE_GAP;
    localparam integer NUM_LINES  = 6;

    // Is this an F rating? (FAILED)
    wire is_failed = (score_value < 20'd700000);

    // Hit count digits
    reg [3:0] hit_tens;
    reg [3:0] hit_ones;
    always @(*) begin
        hit_tens = hit_count / 10;
        hit_ones = hit_count % 10;
    end

    // Rating chars (two chars)
    reg [7:0] rating_c0;
    reg [7:0] rating_c1;
    always @(*) begin
        if (score_value == 20'd1000000) begin
            rating_c0 = "S";
            rating_c1 = "S";
        end else if (score_value >= 20'd900000) begin
            rating_c0 = "S";
            rating_c1 = " ";
        end else if (score_value >= 20'd850000) begin
            rating_c0 = "A";
            rating_c1 = " ";
        end else if (score_value >= 20'd800000) begin
            rating_c0 = "b"; // lower case b
            rating_c1 = " ";
        end else if (score_value >= 20'd700000) begin
            rating_c0 = "C";
            rating_c1 = " ";
        end else begin
            rating_c0 = "F";
            rating_c1 = " ";
        end
    end

    // Speed text "1.0","2.0","3.0"
    reg [7:0] sp_c0, sp_c1, sp_c2;
    always @(*) begin
        case (note_speed)
            2'd1: begin sp_c0 = "1"; sp_c1 = "."; sp_c2 = "0"; end
            2'd2: begin sp_c0 = "2"; sp_c1 = "."; sp_c2 = "0"; end
            2'd3: begin sp_c0 = "3"; sp_c1 = "."; sp_c2 = "0"; end
            default: begin sp_c0 = "1"; sp_c1 = "."; sp_c2 = "0"; end
        endcase
    end

    // chart number char
    wire [7:0] chart_char = (chart_select == 1'b0) ? "1" : "2";

    // Small 3x5 font: returns 1 if pixel on
    function glyph_pixel;
        input [7:0] ch;   // ASCII
        input [2:0] sx;   // 0..2
        input [2:0] sy;   // 0..4
        reg  [14:0] pattern;
        integer idx;
    begin
        case (ch)
            // space
            8'h20: pattern = 15'b000_000_000_000_000;

            // Digits '0'..'9'
            "0": pattern = 15'b111_101_101_101_111;
            "1": pattern = 15'b010_110_010_010_111;
            "2": pattern = 15'b111_001_111_100_111;
            "3": pattern = 15'b111_001_111_001_111;
            "4": pattern = 15'b101_101_111_001_001;
            "5": pattern = 15'b111_100_111_001_111;
            "6": pattern = 15'b111_100_111_101_111;
            "7": pattern = 15'b111_001_010_010_010;
            "8": pattern = 15'b111_101_111_101_111;
            "9": pattern = 15'b111_101_111_001_111;

            // Letters we need (3x5)
            "A": pattern = 15'b111_101_111_101_101;
            "C": pattern = 15'b111_100_100_100_111;
            "D": pattern = 15'b110_101_101_101_110;
            "E": pattern = 15'b111_100_111_100_111;
            "F": pattern = 15'b111_100_111_100_100;
            "G": pattern = 15'b111_100_101_101_111;
            "H": pattern = 15'b101_101_111_101_101;
            "I": pattern = 15'b111_010_010_010_111;
            "L": pattern = 15'b100_100_100_100_111;
            "M": pattern = 15'b101_111_111_101_101;
            "N": pattern = 15'b101_111_111_111_101;
            "O": pattern = 15'b111_101_101_101_111;
            "P": pattern = 15'b111_101_111_100_100;
            "R": pattern = 15'b110_101_110_101_101;
            "S": pattern = 15'b111_100_111_001_111;
            "T": pattern = 15'b111_010_010_010_010;
            "U": pattern = 15'b101_101_101_101_111;
            "b": pattern = 15'b100_100_110_101_110;  // lower b

            // ':' and '.'
            ":": pattern = 15'b010_000_000_010_000;
            ".": pattern = 15'b000_000_000_000_010;

            default: pattern = 15'b000_000_000_000_000;
        endcase

        idx = sy * CHAR_W + sx; // 0..14
        glyph_pixel = pattern[14 - idx];
    end
    endfunction

    // Main overlay logic
    integer line_idx;
    integer char_idx;
    reg [7:0] ch;
    reg [2:0] sx, sy;
    reg       pix_on;

    always @(*) begin
        overlay_on = 1'b0;
        overlay_r  = 8'h00;
        overlay_g  = 8'h00;
        overlay_b  = 8'h00;

        if (!end_mode) begin
            // not in end screen
        end else begin
            // Check if inside vertical block of lines
            if (vy >= FIRST_LINE_Y &&
                vy <  FIRST_LINE_Y + NUM_LINES*LINE_H) begin

                integer ly;
                ly       = vy - FIRST_LINE_Y;
                line_idx = ly / LINE_H;
                sy       = ly % LINE_H;

                if (sy < CHAR_H &&
                    line_idx >= 0 && line_idx < NUM_LINES &&
                    vx >= TEXT_X &&
                    vx < TEXT_X + MAX_CHARS*CELL_W) begin

                    integer cx;
                    cx       = vx - TEXT_X;
                    char_idx = cx / CELL_W;
                    sx       = cx % CELL_W;

                    if (sx < CHAR_W && char_idx < MAX_CHARS) begin
                        // Default space
                        ch = 8'h20;

                        case (line_idx)
                            // Line 0: CLEARED / FAILED
                            0: begin
                                if (is_failed) begin
                                    // "FAILED"
                                    case (char_idx)
                                        0: ch = "F";
                                        1: ch = "A";
                                        2: ch = "I";
                                        3: ch = "L";
                                        4: ch = "E";
                                        5: ch = "D";
                                        default: ch = " ";
                                    endcase
                                end else begin
                                    // "CLEAR"
                                    case (char_idx)
                                        0: ch = "C";
                                        1: ch = "L";
                                        2: ch = "E";
                                        3: ch = "A";
                                        4: ch = "R";
													 5: ch = "E";
                                        6: ch = "D";
                                        default: ch = " ";
                                    endcase
                                end
                            end

                            // Line 1: "SCORE: 1234567"
                            1: begin
                                case (char_idx)
                                    0: ch = "S";
                                    1: ch = "C";
                                    2: ch = "O";
                                    3: ch = "R";
                                    4: ch = "E";
                                    5: ch = ":";
                                    6: ch = " ";
                                    default: begin
                                        // digits start at index 7..13
                                        integer d_idx;
                                        reg [3:0] nib;
                                        d_idx = char_idx - 7;
                                        case (d_idx)
                                            0: nib = score_d6;
                                            1: nib = score_d5;
                                            2: nib = score_d4;
                                            3: nib = score_d3;
                                            4: nib = score_d2;
                                            5: nib = score_d1;
                                            6: nib = score_d0;
                                            default: nib = 4'd0;
                                        endcase
                                        if (d_idx >= 0 && d_idx < 7)
                                            ch = "0" + nib;
                                        else
                                            ch = " ";
                                    end
                                endcase
                            end

                            // Line 2: "RATING: XX"
                            2: begin
                                case (char_idx)
                                    0: ch = "R";
                                    1: ch = "A";
                                    2: ch = "T";
                                    3: ch = "I";
                                    4: ch = "N";
                                    5: ch = "G";
                                    6: ch = ":";
                                    7: ch = " ";
                                    8: ch = rating_c0;
                                    9: ch = rating_c1;
                                    default: ch = " ";
                                endcase
                            end

                            // Line 3: "CHART SELECTION: X"
                            3: begin
                                case (char_idx)
                                    0:  ch = "C";
                                    1:  ch = "H";
                                    2:  ch = "A";
                                    3:  ch = "R";
                                    4:  ch = "T";
                                    5:  ch = " ";
                                    6:  ch = "S";
                                    7:  ch = "E";
                                    8:  ch = "L";
                                    9:  ch = "E";
                                    10: ch = "C";
                                    11: ch = "T";
                                    12: ch = "I";
                                    13: ch = "O";
                                    14: ch = "N";
                                    15: ch = ":";
                                    16: ch = " ";
                                    17: ch = chart_char;
                                    default: ch = " ";
                                endcase
                            end

                            // Line 4: "HIT AMOUNT: XX"
                            4: begin
                                case (char_idx)
                                    0:  ch = "H";
                                    1:  ch = "I";
                                    2:  ch = "T";
                                    3:  ch = " ";
                                    4:  ch = "A";
                                    5:  ch = "M";
                                    6:  ch = "O";
                                    7:  ch = "U";
                                    8:  ch = "N";
                                    9:  ch = "T";
                                    10: ch = ":";
                                    11: ch = " ";
                                    12: ch = "0" + hit_tens;
                                    13: ch = "0" + hit_ones;
                                    default: ch = " ";
                                endcase
                            end

                            // Line 5: "SPEED: X.X"
                            5: begin
                                case (char_idx)
                                    0: ch = "S";
                                    1: ch = "P";
                                    2: ch = "E";
                                    3: ch = "E";
                                    4: ch = "D";
                                    5: ch = ":";
                                    6: ch = " ";
                                    7: ch = sp_c0;
                                    8: ch = sp_c1;
                                    9: ch = sp_c2;
                                    default: ch = " ";
                                endcase
                            end

                            default: ch = " ";
                        endcase

                        pix_on = glyph_pixel(ch, sx, sy);

                        if (pix_on) begin
                            overlay_on = 1'b1;

                            // Color: line 0 special (CLEAR green / FAILED red)
                            if (line_idx == 0) begin
                                if (is_failed) begin
                                    overlay_r = 8'hFF;
                                    overlay_g = 8'h00;
                                    overlay_b = 8'h00;
                                end else begin
                                    overlay_r = 8'h00;
                                    overlay_g = 8'hFF;
                                    overlay_b = 8'h00;
                                end
                            end else begin
                                overlay_r = 8'hFF;
                                overlay_g = 8'hFF;
                                overlay_b = 8'hFF;
                            end
                        end
                    end // sx < CHAR_W
                end // sy < CHAR_H
            end // vy range
        end
    end

endmodule
