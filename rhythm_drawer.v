module rhythm_drawer (
    input         clk,
    input         rst,           // active LOW
    input         frame_done,    // from vga_frame_driver

    input  [3:0]  lane_keys,     // active HIGH lane buttons
    input  [1:0]  note_speed,    // 1x, 2x, 3x

    input         chart_select,  // 0 = chart_one, 1 = chart_two

    // Full numeric score for end screen logic
    input  [19:0] score_value,

    // Hit count (for end screen "HIT AMOUNT")
    input  [6:0]  hit_count,

    // Score digits for VGA numeric overlay
    input  [3:0]  score_d6,
    input  [3:0]  score_d5,
    input  [3:0]  score_d4,
    input  [3:0]  score_d3,
    input  [3:0]  score_d2,
    input  [3:0]  score_d1,
    input  [3:0]  score_d0,

    // Framebuffer write port
    output reg [14:0] fb_addr,
    output reg [23:0] fb_data,
    output reg        fb_we,

    // Hit pulse goes to scoring system
    output reg        hit_pulse
);

    // Resolution and virtual grid must match vga_frame_driver
    parameter VGA_WIDTH            = 16'd640;
    parameter VGA_HEIGHT           = 16'd480;
    parameter PIXEL_VIRTUAL_SIZE   = 16'd4;
    parameter VIRTUAL_PIXEL_WIDTH  = VGA_WIDTH  / PIXEL_VIRTUAL_SIZE;  // 160
    parameter VIRTUAL_PIXEL_HEIGHT = VGA_HEIGHT / PIXEL_VIRTUAL_SIZE;  // 120
    parameter MEMORY_SIZE          = VIRTUAL_PIXEL_WIDTH * VIRTUAL_PIXEL_HEIGHT;

    parameter LANE_COUNT           = 4;
    parameter LANE_WIDTH           = VIRTUAL_PIXEL_WIDTH / LANE_COUNT; // 40

    parameter NOTE_HEIGHT          = 8;

    parameter HIT_ROW              = (VIRTUAL_PIXEL_HEIGHT * 5) / 6;   // ~5/6 down
	 
	  // start of playfield (everything above this is HUD only) 
    parameter GAME_TOP_Y           = 8;

    parameter FRAMES_PER_SECOND    = 16'd60;
    parameter SPAWN_GAP_FRAMES     = FRAMES_PER_SECOND;                // 1s gap

    parameter TOTAL_CYCLES         = 4;                                // chart_one cycles

    // Drawing FSM
    parameter S_IDLE               = 2'd0;
    parameter S_DRAW               = 2'd1;

    reg [1:0] state;
    reg [7:0] vx;
    reg [7:0] vy;

    // Frame tick just for the drawing FSM
    reg prev_frame_done_rd;
    always @(posedge clk or negedge rst) begin
        if (!rst)
            prev_frame_done_rd <= 1'b0;
        else
            prev_frame_done_rd <= frame_done;
    end

    wire frame_tick_rd = (frame_done == 1'b1 && prev_frame_done_rd == 1'b0);

    // chart_one instance (single-hit notes only)
    wire [6:0] c1_note_row0;
    wire [6:0] c1_note_row1;
    wire [6:0] c1_note_row2;
    wire [6:0] c1_note_row3;

    wire       c1_note_active0;
    wire       c1_note_active1;
    wire       c1_note_active2;
    wire       c1_note_active3;

    wire       c1_note_hit0;
    wire       c1_note_hit1;
    wire       c1_note_hit2;
    wire       c1_note_hit3;

    wire [1:0] c1_visible_phase;
    wire       c1_hit_pulse;
    wire       c1_chart_done;

    // chart_one has no double notes, so double flags are 0
    wire       c1_note_double0 = 1'b0;
    wire       c1_note_double1 = 1'b0;
    wire       c1_note_double2 = 1'b0;
    wire       c1_note_double3 = 1'b0;

chart_one #(
    .VIRTUAL_PIXEL_HEIGHT(VIRTUAL_PIXEL_HEIGHT),
    .NOTE_HEIGHT        (NOTE_HEIGHT),
    .HIT_ROW            (HIT_ROW),
    .FRAMES_PER_SECOND  (FRAMES_PER_SECOND),
    .SPAWN_GAP_FRAMES   (SPAWN_GAP_FRAMES),
    .TOTAL_CYCLES       (TOTAL_CYCLES),  
    .LANE_COUNT         (LANE_COUNT)      
    ) u_chart_one (
        .clk          (clk),
        .rst          (rst),
        .frame_done   (frame_done),
        .lane_keys    (lane_keys),
        .note_speed   (note_speed),

        .note_row0    (c1_note_row0),
        .note_row1    (c1_note_row1),
        .note_row2    (c1_note_row2),
        .note_row3    (c1_note_row3),

        .note_active0 (c1_note_active0),
        .note_active1 (c1_note_active1),
        .note_active2 (c1_note_active2),
        .note_active3 (c1_note_active3),

        .note_hit0    (c1_note_hit0),
        .note_hit1    (c1_note_hit1),
        .note_hit2    (c1_note_hit2),
        .note_hit3    (c1_note_hit3),

        .visible_phase(c1_visible_phase),
        .hit_pulse    (c1_hit_pulse),

        .chart_done   (c1_chart_done)
    );

    // chart_two instance (single + double-hit notes)
    wire [6:0] c2_note_row0;
    wire [6:0] c2_note_row1;
    wire [6:0] c2_note_row2;
    wire [6:0] c2_note_row3;

    wire       c2_note_active0;
    wire       c2_note_active1;
    wire       c2_note_active2;
    wire       c2_note_active3;

    wire       c2_note_hit0;
    wire       c2_note_hit1;
    wire       c2_note_hit2;
    wire       c2_note_hit3;

    wire       c2_note_double0;
    wire       c2_note_double1;
    wire       c2_note_double2;
    wire       c2_note_double3;

    wire [1:0] c2_visible_phase;
    wire       c2_hit_pulse;
    wire       c2_chart_done;

    chart_two #(
        .VIRTUAL_PIXEL_HEIGHT(VIRTUAL_PIXEL_HEIGHT),
        .NOTE_HEIGHT        (NOTE_HEIGHT),
        .HIT_ROW            (HIT_ROW),
        .FRAMES_PER_SECOND  (FRAMES_PER_SECOND),
        .SPAWN_GAP_FRAMES   (SPAWN_GAP_FRAMES)
    ) u_chart_two (
        .clk          (clk),
        .rst          (rst),
        .frame_done   (frame_done),
        .lane_keys    (lane_keys),
        .note_speed   (note_speed),

        .note_row0    (c2_note_row0),
        .note_row1    (c2_note_row1),
        .note_row2    (c2_note_row2),
        .note_row3    (c2_note_row3),

        .note_active0 (c2_note_active0),
        .note_active1 (c2_note_active1),
        .note_active2 (c2_note_active2),
        .note_active3 (c2_note_active3),

        .note_hit0    (c2_note_hit0),
        .note_hit1    (c2_note_hit1),
        .note_hit2    (c2_note_hit2),
        .note_hit3    (c2_note_hit3),

        .note_double0 (c2_note_double0),
        .note_double1 (c2_note_double1),
        .note_double2 (c2_note_double2),
        .note_double3 (c2_note_double3),

        .visible_phase(c2_visible_phase),
        .hit_pulse    (c2_hit_pulse),

        .chart_done   (c2_chart_done)
    );

    // MUX between chart_one and chart_two
    wire [6:0] note_row0  = chart_select ? c2_note_row0  : c1_note_row0;
    wire [6:0] note_row1  = chart_select ? c2_note_row1  : c1_note_row1;
    wire [6:0] note_row2  = chart_select ? c2_note_row2  : c1_note_row2;
    wire [6:0] note_row3  = chart_select ? c2_note_row3  : c1_note_row3;

    wire       note_active0 = chart_select ? c2_note_active0 : c1_note_active0;
    wire       note_active1 = chart_select ? c2_note_active1 : c1_note_active1;
    wire       note_active2 = chart_select ? c2_note_active2 : c1_note_active2;
    wire       note_active3 = chart_select ? c2_note_active3 : c1_note_active3;

    wire       note_hit0    = chart_select ? c2_note_hit0    : c1_note_hit0;
    wire       note_hit1    = chart_select ? c2_note_hit1    : c1_note_hit1;
    wire       note_hit2    = chart_select ? c2_note_hit2    : c1_note_hit2;
    wire       note_hit3    = chart_select ? c2_note_hit3    : c1_note_hit3;

    wire       note_double0 = chart_select ? c2_note_double0 : c1_note_double0;
    wire       note_double1 = chart_select ? c2_note_double1 : c1_note_double1;
    wire       note_double2 = chart_select ? c2_note_double2 : c1_note_double2;
    wire       note_double3 = chart_select ? c2_note_double3 : c1_note_double3;

    wire [1:0] visible_phase_mux = chart_select ? c2_visible_phase : c1_visible_phase;
    wire       hit_pulse_mux     = chart_select ? c2_hit_pulse     : c1_hit_pulse;

    wire       chart_done_mux    = chart_select ? c2_chart_done    : c1_chart_done;

    // End-mode latch
    reg end_mode;

    always @(posedge clk or negedge rst) begin
        if (!rst)
            end_mode <= 1'b0;
        else if (chart_done_mux)
            end_mode <= 1'b1;
    end

    // Score overlay (draws numeric score on top of lanes)
    wire       score_overlay_on;
    wire [7:0] score_r, score_g, score_b;

    vga_score_overlay #(
        .VIRTUAL_PIXEL_WIDTH (VIRTUAL_PIXEL_WIDTH),
        .VIRTUAL_PIXEL_HEIGHT(VIRTUAL_PIXEL_HEIGHT),
        .SCORE_X(8'd4),
        .SCORE_Y(8'd4),
        .DIGIT_W(3),
        .DIGIT_H(5)
    ) u_score_overlay (
        .vx(vx),
        .vy(vy),
        .d6(score_d6),
        .d5(score_d5),
        .d4(score_d4),
        .d3(score_d3),
        .d2(score_d2),
        .d1(score_d1),
        .d0(score_d0),
        .overlay_on(score_overlay_on),
        .overlay_r(score_r),
        .overlay_g(score_g),
        .overlay_b(score_b)
    );

    // READY / SET / GO overlay
    wire       start_overlay_on;
    wire [7:0] start_r, start_g, start_b;

    vga_start_overlay #(
        .VIRTUAL_PIXEL_WIDTH (VIRTUAL_PIXEL_WIDTH),
        .VIRTUAL_PIXEL_HEIGHT(VIRTUAL_PIXEL_HEIGHT)
    ) u_start_overlay (
        .vx(vx),
        .vy(vy),
        .phase(visible_phase_mux),
        .overlay_on(start_overlay_on),
        .overlay_r(start_r),
        .overlay_g(start_g),
        .overlay_b(start_b)
    );

    // CHART label overlay: "CHART 1" or "CHART 2"
    wire       chart_label_on;
    wire [7:0] chart_label_r, chart_label_g, chart_label_b;

    wire [3:0] chart_digit = chart_select ? 4'd2 : 4'd1;

    vga_chart_label_overlay #(
        .VIRTUAL_PIXEL_WIDTH (VIRTUAL_PIXEL_WIDTH),
        .VIRTUAL_PIXEL_HEIGHT(VIRTUAL_PIXEL_HEIGHT),
        .LABEL_X(8'd4),
        .LABEL_Y(8'd14),
        .CHAR_W(3),
        .CHAR_H(5),
        .CHAR_GAP(1)
    ) u_chart_label (
        .vx(vx),
        .vy(vy),
        .chart_digit(chart_digit),
        .overlay_on(chart_label_on),
        .overlay_r(chart_label_r),
        .overlay_g(chart_label_g),
        .overlay_b(chart_label_b)
    );

    // End-screen overlay
    wire       end_overlay_on;
    wire [7:0] end_r, end_g, end_b;

    vga_end_screen_overlay #(
        .VIRTUAL_PIXEL_WIDTH (VIRTUAL_PIXEL_WIDTH),
        .VIRTUAL_PIXEL_HEIGHT(VIRTUAL_PIXEL_HEIGHT),
        .TEXT_X(24),
        .FIRST_LINE_Y(32),
        .CHAR_W(3),
        .CHAR_H(5),
        .CHAR_GAP(1),
        .LINE_GAP(1),
        .MAX_CHARS(24)
    ) u_end_overlay (
        .end_mode   (end_mode),
        .vx         (vx),
        .vy         (vy),
        .score_value(score_value),
        .score_d6   (score_d6),
        .score_d5   (score_d5),
        .score_d4   (score_d4),
        .score_d3   (score_d3),
        .score_d2   (score_d2),
        .score_d1   (score_d1),
        .score_d0   (score_d0),
        .hit_count  (hit_count),
        .chart_select(chart_select),
        .note_speed (note_speed),
        .overlay_on (end_overlay_on),
        .overlay_r  (end_r),
        .overlay_g  (end_g),
        .overlay_b  (end_b)
    );

    // Base color (lanes + hit line + notes)
    reg [23:0] base_color;

    // Main FSM: drawing
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            state     <= S_IDLE;
            vx        <= 8'd0;
            vy        <= 8'd0;
            fb_addr   <= 15'd0;
            fb_data   <= 24'h000000;
            fb_we     <= 1'b0;
            hit_pulse <= 1'b0;
        end else begin
            fb_we     <= 1'b0;
            hit_pulse <= hit_pulse_mux;  // chart hit pulses

            case (state)
                //----------------------------------------------
                S_IDLE: begin
                    if (frame_tick_rd) begin
                        vx    <= 8'd0;
                        vy    <= 8'd0;
                        state <= S_DRAW;
                    end
                end

                //----------------------------------------------
                S_DRAW: begin
                    fb_addr <= (vx * VIRTUAL_PIXEL_HEIGHT) + vy;

                    if (end_mode) begin
                        // END SCREEN: black background + overlay
                        if (end_overlay_on)
                            fb_data <= {end_r, end_g, end_b};
                        else
                            fb_data <= 24'h000000; // black
                    end else begin
                        // Normal gameplay drawing
                        base_color <= pixel_color_for(
                            vx, vy,
                            note_row0, note_hit0, note_active0, note_double0,
                            note_row1, note_hit1, note_active1, note_double1,
                            note_row2, note_hit2, note_active2, note_double2,
                            note_row3, note_hit3, note_active3, note_double3
                        );

                        // Priority:
                        // 1) READY/SET/GO overlay
                        // 2) SCORE overlay
                        // 3) CHART label
                        // 4) base lanes/notes
                        if (visible_phase_mux != 2'd3 && start_overlay_on) begin
                            fb_data <= {start_r, start_g, start_b};
                        end else if (score_overlay_on) begin
                            fb_data <= {score_r, score_g, score_b};
                        end else if (chart_label_on) begin
                            fb_data <= {chart_label_r, chart_label_g, chart_label_b};
                        end else begin
                            fb_data <= base_color;
                        end
                    end

                    fb_we <= 1'b1;

                    if (vy == VIRTUAL_PIXEL_HEIGHT-1) begin
                        vy <= 8'd0;
                        if (vx == VIRTUAL_PIXEL_WIDTH-1) begin
                            vx    <= 8'd0;
                            state <= S_IDLE;
                        end else begin
                            vx <= vx + 1'b1;
                        end
                    end else begin
                        vy <= vy + 1'b1;
                    end
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

    // pixel_color_for: lanes, hit line, notes
    function [23:0] pixel_color_for;
        input [7:0] vx_f;
        input [7:0] vy_f;

        input [6:0] note_row0_f;
        input       note_hit0_f;
        input       note_active0_f;
        input       note_double0_f;

        input [6:0] note_row1_f;
        input       note_hit1_f;
        input       note_active1_f;
        input       note_double1_f;

        input [6:0] note_row2_f;
        input       note_hit2_f;
        input       note_active2_f;
        input       note_double2_f;

        input [6:0] note_row3_f;
        input       note_hit3_f;
        input       note_active3_f;
        input       note_double3_f;

        reg [7:0] r;
        reg [7:0] g;
        reg [7:0] b;

        reg in_lane_sep;
        reg in_hit_line;

        reg in_note_lane0, in_note_lane1, in_note_lane2, in_note_lane3;
        reg in_note_vert0, in_note_vert1, in_note_vert2, in_note_vert3;
    begin
        // Background
        r = 8'h20; g = 8'h20; b = 8'h20;

        // Lane separators (vertical white lines)
        in_lane_sep =
            (vx_f == LANE_WIDTH) ||
            (vx_f == (2*LANE_WIDTH)) ||
            (vx_f == (3*LANE_WIDTH));

        if (in_lane_sep) begin
            r = 8'hFF; g = 8'hFF; b = 8'hFF;
        end

        // Hit line (green)
        in_hit_line = (vy_f >= HIT_ROW && vy_f < HIT_ROW + 2);
        if (in_hit_line) begin
            r = 8'h00; g = 8'hFF; b = 8'h00;
        end

        // Notes in each lane
        in_note_lane0 = (vx_f < LANE_WIDTH);
        in_note_lane1 = (vx_f >= LANE_WIDTH     && vx_f < 2*LANE_WIDTH);
        in_note_lane2 = (vx_f >= 2*LANE_WIDTH   && vx_f < 3*LANE_WIDTH);
        in_note_lane3 = (vx_f >= 3*LANE_WIDTH   && vx_f < 4*LANE_WIDTH);

        in_note_vert0 = (vy_f >= note_row0_f) && (vy_f < note_row0_f + NOTE_HEIGHT);
        in_note_vert1 = (vy_f >= note_row1_f) && (vy_f < note_row1_f + NOTE_HEIGHT);
        in_note_vert2 = (vy_f >= note_row2_f) && (vy_f < note_row2_f + NOTE_HEIGHT);
        in_note_vert3 = (vy_f >= note_row3_f) && (vy_f < note_row3_f + NOTE_HEIGHT);

        // Active, not yet hit → color
        // single: orange (FF,80,00)
        // double: cyan   (00,FF,FF)

        if (note_active0_f && !note_hit0_f && in_note_lane0 && in_note_vert0) begin
            if (note_double0_f) begin
                r = 8'h00; g = 8'hFF; b = 8'hFF;
            end else begin
                r = 8'hFF; g = 8'h80; b = 8'h00;
            end
        end

        if (note_active1_f && !note_hit1_f && in_note_lane1 && in_note_vert1) begin
            if (note_double1_f) begin
                r = 8'h00; g = 8'hFF; b = 8'hFF;
            end else begin
                r = 8'hFF; g = 8'h80; b = 8'h00;
            end
        end

        if (note_active2_f && !note_hit2_f && in_note_lane2 && in_note_vert2) begin
            if (note_double2_f) begin
                r = 8'h00; g = 8'hFF; b = 8'hFF;
            end else begin
                r = 8'hFF; g = 8'h80; b = 8'h00;
            end
        end

        if (note_active3_f && !note_hit3_f && in_note_lane3 && in_note_vert3) begin
            if (note_double3_f) begin
                r = 8'h00; g = 8'hFF; b = 8'hFF;
            end else begin
                r = 8'hFF; g = 8'h80; b = 8'h00;
            end
        end

        pixel_color_for = {r, g, b};
    end
    endfunction

endmodule
