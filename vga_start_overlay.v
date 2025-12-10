// =====================================================
// vga_start_overlay
// - Draws "READY", "SET", or "GO" centered on virtual
//   screen depending on phase:
//     phase = 2'd0 -> "READY"
//     phase = 2'd1 -> "SET"
//     phase = 2'd2 -> "GO"
//     phase = 2'd3 -> no overlay
// - Uses 8x8 bitmaps for each letter
// - Color: #14C9FF
// =====================================================
module vga_start_overlay #(
    parameter VIRTUAL_PIXEL_WIDTH  = 160,
    parameter VIRTUAL_PIXEL_HEIGHT = 120
)(
    input  wire [7:0] vx,    // virtual x (0..VIRTUAL_PIXEL_WIDTH-1)
    input  wire [7:0] vy,    // virtual y (0..VIRTUAL_PIXEL_HEIGHT-1)
    input  wire [1:0] phase, // 0=READY, 1=SET, 2=GO, 3=none

    output reg        overlay_on,
    output reg [7:0]  overlay_r,
    output reg [7:0]  overlay_g,
    output reg [7:0]  overlay_b
);

    // Letter codes:
    //  0 = R, 1 = E, 2 = A, 3 = D, 4 = Y,
    //  5 = S, 6 = T, 7 = G, 8 = O
    function letter_pixel_on;
        input [3:0] letter;
        input [2:0] sx;   // 0..7
        input [2:0] sy;   // 0..7
        reg [63:0] pattern;
        integer idx;
    begin
        // 8x8 patterns, row-major, bit[63] = top-left
        case (letter)
            // R
            4'd0: pattern = 64'b11110000_10001000_10001000_11110000_10100000_10010000_10001000_00000000;
            // E
            4'd1: pattern = 64'b11111000_10000000_10000000_11110000_10000000_10000000_11111000_00000000;
            // A
            4'd2: pattern = 64'b01110000_10001000_10001000_11111000_10001000_10001000_10001000_00000000;
            // D
            4'd3: pattern = 64'b11110000_10001000_10001000_10001000_10001000_10001000_11110000_00000000;
            // Y
            4'd4: pattern = 64'b10001000_01010000_00100000_00100000_00100000_00100000_00100000_00000000;
            // S
            4'd5: pattern = 64'b01111000_10000000_10000000_01110000_00001000_00001000_11110000_00000000;
            // T
            4'd6: pattern = 64'b11111000_00100000_00100000_00100000_00100000_00100000_00100000_00000000;
            // G
            4'd7: pattern = 64'b01111000_10000000_10000000_10111000_10001000_10001000_01110000_00000000;
            // O
            4'd8: pattern = 64'b01110000_10001000_10001000_10001000_10001000_10001000_01110000_00000000;
            default: pattern = 64'b0;
        endcase

        idx = sy * 8 + sx;  // 0..63
        letter_pixel_on = pattern[63 - idx];
    end
    endfunction

    parameter CHAR_W = 8;
    parameter CHAR_H = 8;

    reg [2:0] num_chars;
    reg [3:0] letter_code;
    reg [7:0] text_width;
    reg [7:0] start_x;
    reg [7:0] start_y;

    reg [7:0] px;
    reg [7:0] py;
    reg [2:0] char_idx;
    reg [2:0] sx_char;
    reg [2:0] sy_char;
    reg       pix_on;

    always @(*) begin
        overlay_on = 1'b0;
        overlay_r  = 8'h00;
        overlay_g  = 8'h00;
        overlay_b  = 8'h00;
        pix_on     = 1'b0;
        letter_code= 4'd0;

        // No overlay when phase == 3
        if (phase == 2'd3) begin
            // nothing
        end else begin
            // Choose word length
            case (phase)
                2'd0: num_chars = 3'd5; // READY
                2'd1: num_chars = 3'd3; // SET
                2'd2: num_chars = 3'd2; // GO
                default: num_chars = 3'd0;
            endcase

            text_width = num_chars * CHAR_W;
            start_x    = (VIRTUAL_PIXEL_WIDTH  - text_width)  >> 1;
            start_y    = (VIRTUAL_PIXEL_HEIGHT - CHAR_H)      >> 1;

            if (vx >= start_x && vx < start_x + text_width &&
                vy >= start_y && vy < start_y + CHAR_H) begin

                px = vx - start_x;         // 0..text_width-1
                py = vy - start_y;         // 0..7

                char_idx = px[7:3];        // divide by 8 (CHAR_W)
                sx_char  = px[2:0];        // mod 8
                sy_char  = py[2:0];        // 0..7

                // Map (phase, char_idx) -> letter code
                case (phase)
                    2'd0: begin
                        // "READY"
                        case (char_idx)
                            3'd0: letter_code = 4'd0; // R
                            3'd1: letter_code = 4'd1; // E
                            3'd2: letter_code = 4'd2; // A
                            3'd3: letter_code = 4'd3; // D
                            3'd4: letter_code = 4'd4; // Y
                            default: letter_code = 4'd0;
                        endcase
                    end
                    2'd1: begin
                        // "SET"
                        case (char_idx)
                            3'd0: letter_code = 4'd5; // S
                            3'd1: letter_code = 4'd1; // E
                            3'd2: letter_code = 4'd6; // T
                            default: letter_code = 4'd5;
                        endcase
                    end
                    2'd2: begin
                        // "GO"
                        case (char_idx)
                            3'd0: letter_code = 4'd7; // G
                            3'd1: letter_code = 4'd8; // O
                            default: letter_code = 4'd7;
                        endcase
                    end
                    default: letter_code = 4'd0;
                endcase

                pix_on = letter_pixel_on(letter_code, sx_char, sy_char);

                if (pix_on) begin
                    overlay_on = 1'b1;
                    // #14C9FF
                    overlay_r  = 8'h14;
                    overlay_g  = 8'hC9;
                    overlay_b  = 8'hFF;
                end
            end
        end
    end

endmodule