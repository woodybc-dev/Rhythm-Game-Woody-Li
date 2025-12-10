module chart_two #(
    parameter VIRTUAL_PIXEL_HEIGHT = 120,
    parameter NOTE_HEIGHT          = 8,
    parameter HIT_ROW              = 100,
    parameter FRAMES_PER_SECOND    = 60,
    parameter SPAWN_GAP_FRAMES     = 60
)(
    input         clk,
    input         rst,            // active LOW
    input         frame_done,     // from vga_frame_driver
    input  [3:0]  lane_keys,      // active HIGH
    input  [1:0]  note_speed,     // 1x,2x,3x

    output reg [6:0] note_row0,
    output reg [6:0] note_row1,
    output reg [6:0] note_row2,
    output reg [6:0] note_row3,

    output reg       note_active0,
    output reg       note_active1,
    output reg       note_active2,
    output reg       note_active3,

    output reg       note_hit0,
    output reg       note_hit1,
    output reg       note_hit2,
    output reg       note_hit3,

    // mark whether current lane note is double-hit type
    output reg       note_double0,
    output reg       note_double1,
    output reg       note_double2,
    output reg       note_double3,

    // 0 = READY, 1 = SET, 2 = GO, 3 = none
    output reg [1:0] visible_phase,

    // 1-clock pulse whenever note(s) are hit correctly
    // (double notes emit 2 pulses using extra_hit_pending)
    output reg       hit_pulse,

    // goes HIGH once all events spawned and notes gone
    output reg       chart_done
);

    // Now: 4 cycles * 3 events * 2 repetitions = 24
    parameter TOTAL_EVENTS = 24;

    // Frame tick & key edges
    reg        prev_frame_done;
    reg [3:0]  prev_lane_keys;

    always @(posedge clk or negedge rst) begin
        if (!rst)
            prev_frame_done <= 1'b0;
        else
            prev_frame_done <= frame_done;
    end

    wire frame_tick = (frame_done == 1'b1 && prev_frame_done == 1'b0);

    always @(posedge clk or negedge rst) begin
        if (!rst)
            prev_lane_keys <= 4'b0000;
        else if (frame_tick)
            prev_lane_keys <= lane_keys;
    end

    wire [3:0] key_edge = lane_keys & ~prev_lane_keys;

    // Speed step
    function [6:0] speed_step;
        input [1:0] s;
    begin
        case (s)
            2'd1: speed_step = 7'd1;
            2'd2: speed_step = 7'd2;
            2'd3: speed_step = 7'd3;
            default: speed_step = 7'd1;
        endcase
    end
    endfunction

    // Lane free helper
    function lane_is_free;
        input [1:0] ls;
        input       na0, na1, na2, na3;
    begin
        case (ls)
            2'd0: lane_is_free = ~na0;
            2'd1: lane_is_free = ~na1;
            2'd2: lane_is_free = ~na2;
            2'd3: lane_is_free = ~na3;
            default: lane_is_free = 1'b0;
        endcase
    end
    endfunction

    // Start sequence: 1s blank + READY/SET/GO
    reg [15:0] start_delay_frames;
    reg        start_delay_done;

    reg [1:0]  start_phase;
    reg [15:0] start_timer_frames;

    // Chart events and timers
    reg [15:0] spawn_timer_frames;
    reg [4:0]  event_index;     // 0..23

    reg [1:0]  ev_laneA;
    reg [1:0]  ev_laneB;
    reg        ev_double;

    // extra hit pulse for double notes
    reg extra_hit_pending;

    // base pattern index 0..11 (4 cycles * 3 events)
    always @(*) begin
        reg [3:0] base_idx;
        // wrap every 12 events so pattern repeats twice
        base_idx = (event_index < 5'd12) ? event_index[3:0] : (event_index - 5'd12);

        // defaults
        ev_laneA  = 2'd0;
        ev_laneB  = 2'd0;
        ev_double = 1'b0;

        case (base_idx)
            // Cycle 1: 1-2-3&4
            4'd0: begin ev_double = 1'b0; ev_laneA = 2'd0; ev_laneB = 2'd0; end // lane 1
            4'd1: begin ev_double = 1'b0; ev_laneA = 2'd1; ev_laneB = 2'd1; end // lane 2
            4'd2: begin ev_double = 1'b1; ev_laneA = 2'd2; ev_laneB = 2'd3; end // 3&4

            // Cycle 2: 1-3-2&4
            4'd3: begin ev_double = 1'b0; ev_laneA = 2'd0; ev_laneB = 2'd0; end // lane 1
            4'd4: begin ev_double = 1'b0; ev_laneA = 2'd2; ev_laneB = 2'd2; end // lane 3
            4'd5: begin ev_double = 1'b1; ev_laneA = 2'd1; ev_laneB = 2'd3; end // 2&4

            // Cycle 3: 3-4-1&2
            4'd6: begin ev_double = 1'b0; ev_laneA = 2'd2; ev_laneB = 2'd2; end // lane 3
            4'd7: begin ev_double = 1'b0; ev_laneA = 2'd3; ev_laneB = 2'd3; end // lane 4
            4'd8: begin ev_double = 1'b1; ev_laneA = 2'd0; ev_laneB = 2'd1; end // 1&2

            // Cycle 4: 4-2-1&3
            4'd9:  begin ev_double = 1'b0; ev_laneA = 2'd3; ev_laneB = 2'd3; end // lane 4
            4'd10: begin ev_double = 1'b0; ev_laneA = 2'd1; ev_laneB = 2'd1; end // lane 2
            4'd11: begin ev_double = 1'b1; ev_laneA = 2'd0; ev_laneB = 2'd2; end // 1&3

            default: begin ev_double = 1'b0; ev_laneA = 2'd0; ev_laneB = 2'd0; end
        endcase
    end

    // Hit-window helper
    function in_window;
        input [6:0] row;
    begin
        in_window = (row <= HIT_ROW) && (row + NOTE_HEIGHT > HIT_ROW);
    end
    endfunction

    // Main sequential logic
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            start_delay_frames <= 16'd0;
            start_delay_done   <= 1'b0;
            start_phase        <= 2'd0;
            start_timer_frames <= 16'd0;

            spawn_timer_frames <= 16'd0;
            event_index        <= 5'd0;

            note_row0          <= 7'd0;
            note_row1          <= 7'd0;
            note_row2          <= 7'd0;
            note_row3          <= 7'd0;

            note_active0       <= 1'b0;
            note_active1       <= 1'b0;
            note_active2       <= 1'b0;
            note_active3       <= 1'b0;

            note_hit0          <= 1'b0;
            note_hit1          <= 1'b0;
            note_hit2          <= 1'b0;
            note_hit3          <= 1'b0;

            note_double0       <= 1'b0;
            note_double1       <= 1'b0;
            note_double2       <= 1'b0;
            note_double3       <= 1'b0;

            visible_phase      <= 2'd3;
            hit_pulse          <= 1'b0;
            extra_hit_pending  <= 1'b0;
            chart_done         <= 1'b0;
        end else begin
            hit_pulse <= 1'b0;

            if (frame_tick) begin
                // If chart already done, keep the flag and stop updating notes
                if (chart_done) begin
                    visible_phase <= 2'd3;
                end
                else if (!start_delay_done) begin
                    // initial blank second
                    if (start_delay_frames >= FRAMES_PER_SECOND - 1) begin
                        start_delay_frames <= 16'd0;
                        start_delay_done   <= 1'b1;
                        start_phase        <= 2'd0;  // READY
                        start_timer_frames <= 16'd0;
                    end else begin
                        start_delay_frames <= start_delay_frames + 16'd1;
                    end
                    visible_phase <= 2'd3;
                end
                else if (start_phase != 2'd3) begin
                    // READY / SET / GO
                    visible_phase <= start_phase;

                    if (start_timer_frames >= FRAMES_PER_SECOND - 1) begin
                        start_timer_frames <= 16'd0;
                        if (start_phase < 2'd3)
                            start_phase <= start_phase + 2'd1;
                    end else begin
                        start_timer_frames <= start_timer_frames + 16'd1;
                    end
                end
                else begin
                    // chart running
                    visible_phase <= 2'd3;

                    // If a double note was hit last frame, emit second pulse now
                    if (extra_hit_pending) begin
                        hit_pulse         <= 1'b1;
                        extra_hit_pending <= 1'b0;
                    end

                    // Move notes
                    if (note_active0) begin
                        if (note_row0 >= VIRTUAL_PIXEL_HEIGHT-1 - speed_step(note_speed)) begin
                            note_active0 <= 1'b0;
                            note_hit0    <= 1'b0;
                            note_double0 <= 1'b0;
                        end else
                            note_row0    <= note_row0 + speed_step(note_speed);
                    end

                    if (note_active1) begin
                        if (note_row1 >= VIRTUAL_PIXEL_HEIGHT-1 - speed_step(note_speed)) begin
                            note_active1 <= 1'b0;
                            note_hit1    <= 1'b0;
                            note_double1 <= 1'b0;
                        end else
                            note_row1    <= note_row1 + speed_step(note_speed);
                    end

                    if (note_active2) begin
                        if (note_row2 >= VIRTUAL_PIXEL_HEIGHT-1 - speed_step(note_speed)) begin
                            note_active2 <= 1'b0;
                            note_hit2    <= 1'b0;
                            note_double2 <= 1'b0;
                        end else
                            note_row2    <= note_row2 + speed_step(note_speed);
                    end

                    if (note_active3) begin
                        if (note_row3 >= VIRTUAL_PIXEL_HEIGHT-1 - speed_step(note_speed)) begin
                            note_active3 <= 1'b0;
                            note_hit3    <= 1'b0;
                            note_double3 <= 1'b0;
                        end else
                            note_row3    <= note_row3 + speed_step(note_speed);
                    end

                    // Spawn (single or double) events
                    if (event_index < TOTAL_EVENTS) begin
                        if (spawn_timer_frames < SPAWN_GAP_FRAMES - 1) begin
                            spawn_timer_frames <= spawn_timer_frames + 16'd1;
                        end else begin
                            if (!ev_double) begin
                                // single note
                                if (lane_is_free(ev_laneA,
                                                 note_active0, note_active1,
                                                 note_active2, note_active3)) begin
                                    case (ev_laneA)
                                        2'd0: begin
                                                  note_active0 <= 1'b1;
                                                  note_row0    <= 7'd0;
                                                  note_hit0    <= 1'b0;
                                                  note_double0 <= 1'b0;
                                              end
                                        2'd1: begin
                                                  note_active1 <= 1'b1;
                                                  note_row1    <= 7'd0;
                                                  note_hit1    <= 1'b0;
                                                  note_double1 <= 1'b0;
                                              end
                                        2'd2: begin
                                                  note_active2 <= 1'b1;
                                                  note_row2    <= 7'd0;
                                                  note_hit2    <= 1'b0;
                                                  note_double2 <= 1'b0;
                                              end
                                        2'd3: begin
                                                  note_active3 <= 1'b1;
                                                  note_row3    <= 7'd0;
                                                  note_hit3    <= 1'b0;
                                                  note_double3 <= 1'b0;
                                              end
                                    endcase

                                    event_index        <= event_index + 5'd1;
                                    spawn_timer_frames <= 16'd0;
                                end
                            end else begin
                                // double note
                                if (lane_is_free(ev_laneA,
                                                 note_active0, note_active1,
                                                 note_active2, note_active3) &&
                                    lane_is_free(ev_laneB,
                                                 note_active0, note_active1,
                                                 note_active2, note_active3)) begin
                                    // lane A
                                    case (ev_laneA)
                                        2'd0: begin
                                                  note_active0 <= 1'b1;
                                                  note_row0    <= 7'd0;
                                                  note_hit0    <= 1'b0;
                                                  note_double0 <= 1'b1;
                                              end
                                        2'd1: begin
                                                  note_active1 <= 1'b1;
                                                  note_row1    <= 7'd0;
                                                  note_hit1    <= 1'b0;
                                                  note_double1 <= 1'b1;
                                              end
                                        2'd2: begin
                                                  note_active2 <= 1'b1;
                                                  note_row2    <= 7'd0;
                                                  note_hit2    <= 1'b0;
                                                  note_double2 <= 1'b1;
                                              end
                                        2'd3: begin
                                                  note_active3 <= 1'b1;
                                                  note_row3    <= 7'd0;
                                                  note_hit3    <= 1'b0;
                                                  note_double3 <= 1'b1;
                                              end
                                    endcase
                                    // lane B
                                    case (ev_laneB)
                                        2'd0: begin
                                                  note_active0 <= 1'b1;
                                                  note_row0    <= 7'd0;
                                                  note_hit0    <= 1'b0;
                                                  note_double0 <= 1'b1;
                                              end
                                        2'd1: begin
                                                  note_active1 <= 1'b1;
                                                  note_row1    <= 7'd0;
                                                  note_hit1    <= 1'b0;
                                                  note_double1 <= 1'b1;
                                              end
                                        2'd2: begin
                                                  note_active2 <= 1'b1;
                                                  note_row2    <= 7'd0;
                                                  note_hit2    <= 1'b0;
                                                  note_double2 <= 1'b1;
                                              end
                                        2'd3: begin
                                                  note_active3 <= 1'b1;
                                                  note_row3    <= 7'd0;
                                                  note_hit3    <= 1'b0;
                                                  note_double3 <= 1'b1;
                                              end
                                    endcase

                                    event_index        <= event_index + 5'd1;
                                    spawn_timer_frames <= 16'd0;
                                end
                            end
                        end
                    end

                    // Single-note hits
                    if (note_active0 && !note_hit0 && !note_double0 &&
                        in_window(note_row0) && key_edge[0]) begin
                        note_hit0 <= 1'b1;
                        hit_pulse <= 1'b1;
                    end

                    if (note_active1 && !note_hit1 && !note_double1 &&
                        in_window(note_row1) && key_edge[1]) begin
                        note_hit1 <= 1'b1;
                        hit_pulse <= 1'b1;
                    end

                    if (note_active2 && !note_hit2 && !note_double2 &&
                        in_window(note_row2) && key_edge[2]) begin
                        note_hit2 <= 1'b1;
                        hit_pulse <= 1'b1;
                    end

                    if (note_active3 && !note_hit3 && !note_double3 &&
                        in_window(note_row3) && key_edge[3]) begin
                        note_hit3 <= 1'b1;
                        hit_pulse <= 1'b1;
                    end

                    // Double-note hits (pairs)
                    // 2&3
                    if (note_active2 && note_active3 &&
                        note_double2 && note_double3 &&
                        !note_hit2 && !note_hit3 &&
                        in_window(note_row2) && in_window(note_row3) &&
                        key_edge[2] && key_edge[3]) begin
                        note_hit2         <= 1'b1;
                        note_hit3         <= 1'b1;
                        hit_pulse         <= 1'b1;
                        extra_hit_pending <= 1'b1;
                    end

                    // 1&3
                    if (note_active1 && note_active3 &&
                        note_double1 && note_double3 &&
                        !note_hit1 && !note_hit3 &&
                        in_window(note_row1) && in_window(note_row3) &&
                        key_edge[1] && key_edge[3]) begin
                        note_hit1         <= 1'b1;
                        note_hit3         <= 1'b1;
                        hit_pulse         <= 1'b1;
                        extra_hit_pending <= 1'b1;
                    end

                    // 0&1
                    if (note_active0 && note_active1 &&
                        note_double0 && note_double1 &&
                        !note_hit0 && !note_hit1 &&
                        in_window(note_row0) && in_window(note_row1) &&
                        key_edge[0] && key_edge[1]) begin
                        note_hit0         <= 1'b1;
                        note_hit1         <= 1'b1;
                        hit_pulse         <= 1'b1;
                        extra_hit_pending <= 1'b1;
                    end

                    // 0&2
                    if (note_active0 && note_active2 &&
                        note_double0 && note_double2 &&
                        !note_hit0 && !note_hit2 &&
                        in_window(note_row0) && in_window(note_row2) &&
                        key_edge[0] && key_edge[2]) begin
                        note_hit0         <= 1'b1;
                        note_hit2         <= 1'b1;
                        hit_pulse         <= 1'b1;
                        extra_hit_pending <= 1'b1;
                    end

                    // chart_done: all events spawned and all notes gone
                    if (!chart_done) begin
                        if (event_index >= TOTAL_EVENTS &&
                            !note_active0 && !note_active1 &&
                            !note_active2 && !note_active3) begin
                            chart_done <= 1'b1;
                        end
                    end
                end
            end
        end
    end

endmodule
