module chart_one #(
    parameter VIRTUAL_PIXEL_HEIGHT = 120,
    parameter NOTE_HEIGHT          = 8,
    parameter HIT_ROW              = 100,
    parameter FRAMES_PER_SECOND    = 60,
    parameter SPAWN_GAP_FRAMES     = 60,
    parameter TOTAL_CYCLES         = 4,   // <-- added for compatibility
    parameter LANE_COUNT           = 4    // <-- added for compatibility
)(
    input         clk,
    input         rst,            // active LOW
    input         frame_done,
    input  [3:0]  lane_keys,
    input  [1:0]  note_speed,     // 1x, 2x, 3x

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

    output reg [1:0] visible_phase,
    output reg       hit_pulse,
    output reg       chart_done
);

    // parameters for note spawning
    parameter TOTAL_EVENTS = 32;   

    // frame tick
    reg prev_frame_done;
    always @(posedge clk or negedge rst) begin
        if (!rst)
            prev_frame_done <= 1'b0;
        else
            prev_frame_done <= frame_done;
    end

    wire frame_tick = (frame_done == 1'b1 && prev_frame_done == 1'b0);

    // key edge per frame
    reg [3:0] prev_lane_keys;
    always @(posedge clk or negedge rst) begin
        if (!rst)
            prev_lane_keys <= 4'b0000;
        else if (frame_tick)
            prev_lane_keys <= lane_keys;
    end

    wire [3:0] key_edge = lane_keys & ~prev_lane_keys;

    // speed step
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

    // simple lane-free helper
    function lane_is_free;
        input [1:0] ln;
        input       a0, a1, a2, a3;
    begin
        case (ln)
            2'd0: lane_is_free = ~a0;
            2'd1: lane_is_free = ~a1;
            2'd2: lane_is_free = ~a2;
            2'd3: lane_is_free = ~a3;
            default: lane_is_free = 1'b0;
        endcase
    end
    endfunction

    // start sequence: 1s blank + READY / SET / GO
    reg [15:0] start_delay_frames;
    reg        start_delay_done;

    reg [1:0]  start_phase;        // 0=READY,1=SET,2=GO,3=none
    reg [15:0] start_timer_frames;

    // event spawning state
    reg [15:0] spawn_timer_frames;
    reg [5:0]  event_index;        // 0..31

    // decoded event lane
    reg [1:0]  ev_lane;

    // 16-note base pattern; we repeat it twice by wrapping event_index
    always @(*) begin
        reg [4:0] base_idx;
        base_idx = (event_index < 6'd16) ? event_index[4:0] : (event_index - 6'd16);

        // default lane
        ev_lane = 2'd0;

        case (base_idx)
            // cycle 1: 1,2,3,4 (0..3)
            5'd0: ev_lane = 2'd0;
            5'd1: ev_lane = 2'd1;
            5'd2: ev_lane = 2'd2;
            5'd3: ev_lane = 2'd3;

            // cycle 2: 1,2,3,4 (4..7)
            5'd4: ev_lane = 2'd0;
            5'd5: ev_lane = 2'd1;
            5'd6: ev_lane = 2'd2;
            5'd7: ev_lane = 2'd3;

            // cycle 3: 4,3,2,1 (8..11)
            5'd8:  ev_lane = 2'd3;
            5'd9:  ev_lane = 2'd2;
            5'd10: ev_lane = 2'd1;
            5'd11: ev_lane = 2'd0;

            // cycle 4: 4,3,2,1 (12..15)
            5'd12: ev_lane = 2'd3;
            5'd13: ev_lane = 2'd2;
            5'd14: ev_lane = 2'd1;
            5'd15: ev_lane = 2'd0;

            default: ev_lane = 2'd0;
        endcase
    end

    // hit-window helper
    function in_window;
        input [6:0] row;
    begin
        in_window = (row <= HIT_ROW) && (row + NOTE_HEIGHT > HIT_ROW);
    end
    endfunction

    // main sequential logic
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            start_delay_frames <= 16'd0;
            start_delay_done   <= 1'b0;
            start_phase        <= 2'd0;
            start_timer_frames <= 16'd0;

            spawn_timer_frames <= 16'd0;
            event_index        <= 6'd0;

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

            visible_phase      <= 2'd3;
            hit_pulse          <= 1'b0;
            chart_done         <= 1'b0;
        end else begin
            hit_pulse <= 1'b0;

            if (frame_tick) begin
                // 0) If already done, keep chart_done high and do nothing else
                if (chart_done) begin
                    visible_phase <= 2'd3;
                end
                else if (!start_delay_done) begin
                    // 1) initial 1-second blank
                    if (start_delay_frames >= (FRAMES_PER_SECOND - 1)) begin
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
                    // 2) READY / SET / GO sequence (1 second each)
                    visible_phase <= start_phase;

                    if (start_timer_frames >= (FRAMES_PER_SECOND - 1)) begin
                        start_timer_frames <= 16'd0;
                        if (start_phase < 2'd3)
                            start_phase <= start_phase + 2'd1;
                    end else begin
                        start_timer_frames <= start_timer_frames + 16'd1;
                    end
                end
                else begin
                    // 3) Chart running
                    visible_phase <= 2'd3;

                    // move notes
                    if (note_active0) begin
                        if (note_row0 >= VIRTUAL_PIXEL_HEIGHT-1 - speed_step(note_speed)) begin
                            note_active0 <= 1'b0;
                            note_hit0    <= 1'b0;
                        end else
                            note_row0    <= note_row0 + speed_step(note_speed);
                    end

                    if (note_active1) begin
                        if (note_row1 >= VIRTUAL_PIXEL_HEIGHT-1 - speed_step(note_speed)) begin
                            note_active1 <= 1'b0;
                            note_hit1    <= 1'b0;
                        end else
                            note_row1    <= note_row1 + speed_step(note_speed);
                    end

                    if (note_active2) begin
                        if (note_row2 >= VIRTUAL_PIXEL_HEIGHT-1 - speed_step(note_speed)) begin
                            note_active2 <= 1'b0;
                            note_hit2    <= 1'b0;
                        end else
                            note_row2    <= note_row2 + speed_step(note_speed);
                    end

                    if (note_active3) begin
                        if (note_row3 >= VIRTUAL_PIXEL_HEIGHT-1 - speed_step(note_speed)) begin
                            note_active3 <= 1'b0;
                            note_hit3    <= 1'b0;
                        end else
                            note_row3    <= note_row3 + speed_step(note_speed);
                    end

                    //spawn notes according to event_index
                    if (event_index < TOTAL_EVENTS) begin
                        if (spawn_timer_frames < SPAWN_GAP_FRAMES - 1) begin
                            spawn_timer_frames <= spawn_timer_frames + 16'd1;
                        end else begin
                            if (lane_is_free(ev_lane,
                                             note_active0, note_active1,
                                             note_active2, note_active3)) begin
                                case (ev_lane)
                                    2'd0: begin
                                              note_active0 <= 1'b1;
                                              note_row0    <= 7'd0;
                                              note_hit0    <= 1'b0;
                                          end
                                    2'd1: begin
                                              note_active1 <= 1'b1;
                                              note_row1    <= 7'd0;
                                              note_hit1    <= 1'b0;
                                          end
                                    2'd2: begin
                                              note_active2 <= 1'b1;
                                              note_row2    <= 7'd0;
                                              note_hit2    <= 1'b0;
                                          end
                                    2'd3: begin
                                              note_active3 <= 1'b1;
                                              note_row3    <= 7'd0;
                                              note_hit3    <= 1'b0;
                                          end
                                endcase

                                event_index        <= event_index + 6'd1;
                                spawn_timer_frames <= 16'd0;
                            end
                        end
                    end

                    // hit detection (single notes only)
                    if (note_active0 && !note_hit0 &&
                        in_window(note_row0) && key_edge[0]) begin
                        note_hit0 <= 1'b1;
                        hit_pulse <= 1'b1;
                    end
                    if (note_active1 && !note_hit1 &&
                        in_window(note_row1) && key_edge[1]) begin
                        note_hit1 <= 1'b1;
                        hit_pulse <= 1'b1;
                    end
                    if (note_active2 && !note_hit2 &&
                        in_window(note_row2) && key_edge[2]) begin
                        note_hit2 <= 1'b1;
                        hit_pulse <= 1'b1;
                    end
                    if (note_active3 && !note_hit3 &&
                        in_window(note_row3) && key_edge[3]) begin
                        note_hit3 <= 1'b1;
                        hit_pulse <= 1'b1;
                    end

                    // chart_done: all events spawned AND all notes cleared
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
