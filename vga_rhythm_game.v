// 4-lane rhythm game project by Xingyu Li (Silas) and Brooke Woody
// 1 top module, 15 sub modules in total (including a RAM: 1-PORT)
module vga_rhythm_game (
    input         CLOCK_50,
    input  [3:0]  KEY,        // pushbuttons, active LOW on DE1-SoC
    input  [9:0]  SW,         // SW[9] = reset-enable, SW[2] = chart select, SW[1:0] = speed
    output [9:0]  LEDR,
    output [6:0]  HEX0,
    output [6:0]  HEX1,
    output [6:0]  HEX2,
    output [6:0]  HEX3,
    output [6:0]  HEX4,
    output [6:0]  HEX5,

    // VGA
    output        VGA_BLANK_N,
    output [7:0]  VGA_B,
    output        VGA_CLK,
    output [7:0]  VGA_G,
    output        VGA_HS,
    output [7:0]  VGA_R,
    output        VGA_SYNC_N,
    output        VGA_VS
);

    // CLOCK / RESET
    wire clk = CLOCK_50;

    // SW[9] = 1 → KEY[0] is active-low reset
    // SW[9] = 0 → KEY[0] becomes gameplay key
    wire rst_n;
    assign rst_n = (SW[9]) ? KEY[0] : 1'b1;
	 

    // LANE KEYS (invert because DE1-SoC KEY is active-low)
    // lane 0 ← KEY[3]
    // lane 1 ← KEY[2]
    // lane 2 ← KEY[1]
    // lane 3 ← KEY[0]
    wire [3:0] lane_keys;
    assign lane_keys[0] = ~KEY[3];
    assign lane_keys[1] = ~KEY[2];
    assign lane_keys[2] = ~KEY[1];
    assign lane_keys[3] = ~KEY[0];
	 

    // FRAMEBUFFER SIGNALS
    wire        active_pixels;
    wire        frame_done;
    wire [9:0]  x;
    wire [9:0]  y;

    wire [14:0] fb_addr;
    wire [23:0] fb_data;
    wire        fb_we;


    // SCORING SIGNALS
    wire        hit_pulse;          // from rhythm_drawer
    wire [19:0] score_value;        // 0–1,000,000

	 
    // Score digits for VGA overlay
    wire [3:0] score_d6;
    wire [3:0] score_d5;
    wire [3:0] score_d4;
    wire [3:0] score_d3;
    wire [3:0] score_d2;
    wire [3:0] score_d1;
    wire [3:0] score_d0;


    // HIT COUNTER (HEX0 / HEX1)
    reg  [6:0] hit_count;
    reg  [3:0] hit_ones;
    reg  [3:0] hit_tens;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            hit_count <= 7'd0;
        else if (hit_pulse) begin
            if (hit_count < 7'd99)
                hit_count <= hit_count + 7'd1;
        end
    end

    always @(*) begin
        hit_tens = hit_count / 10;
        hit_ones = hit_count % 10;
    end


    // SCORE MANAGER—scaled to 1,000,000
    score_manager #(
        .TOTAL_NOTES(32),                
        .MAX_SCORE(1000000)
        ) u_score_manager (
        .clk(clk),
        .rst(rst_n),
        .hit_pulse(hit_pulse),
        .score(score_value)
    );



    // SCORE → DECIMAL DIGITS (for VGA)
    score_to_digits u_score_to_digits (
        .score(score_value),
        .d6(score_d6),
        .d5(score_d5),
        .d4(score_d4),
        .d3(score_d3),
        .d2(score_d2),
        .d1(score_d1),
        .d0(score_d0)
    );


    // VGA FRAME DRIVER (framebuffer)
    vga_frame_driver u_frame_driver (
        .clk(clk),
        .rst(rst_n),

        .active_pixels(active_pixels),
        .frame_done(frame_done),

        .x(x),
        .y(y),

        .VGA_BLANK_N(VGA_BLANK_N),
        .VGA_CLK(VGA_CLK),
        .VGA_HS(VGA_HS),
        .VGA_B(VGA_B),
        .VGA_G(VGA_G),
        .VGA_R(VGA_R),
        .VGA_SYNC_N(VGA_SYNC_N),
        .VGA_VS(VGA_VS),

        .the_vga_draw_frame_write_mem_address(fb_addr),
        .the_vga_draw_frame_write_mem_data(fb_data),
        .the_vga_draw_frame_write_a_pixel(fb_we)
    );


    // NOTE SPEED SELECTOR (HEX3 / HEX2)
    wire [1:0] note_speed;
    wire [3:0] speed_hi_digit;
    wire [3:0] speed_lo_digit;

    speed_selector u_speed_selector (
        .sw_speed({SW[1], SW[0]}),
        .note_speed(note_speed),
        .digit_hi(speed_hi_digit),
        .digit_lo(speed_lo_digit)
    );


    // CHART SELECT — SW2
    // 0 → chart_one (single-hit)
    // 1 → chart_two (single + double)
    wire chart_select = SW[2];


    // RATING DECODER (HEX4 / HEX5)
    wire [3:0] rating_hi_digit;
    wire [3:0] rating_lo_digit;

    rating_decoder u_rating_decoder (
        .score(score_value),
        .rating_hi(rating_hi_digit),
        .rating_lo(rating_lo_digit)
    );


    // RHYTHM DRAWER (gameplay + start + end screen)
    rhythm_drawer u_rhythm_drawer (
        .clk(clk),
        .rst(rst_n),
        .frame_done(frame_done),
    
        .lane_keys(lane_keys),
        .note_speed(note_speed),

        .chart_select(chart_select),     

        .score_value(score_value),       
        .hit_count(hit_count),           

        .score_d6(score_d6),
        .score_d5(score_d5),
        .score_d4(score_d4),
        .score_d3(score_d3),
        .score_d2(score_d2),
        .score_d1(score_d1),
        .score_d0(score_d0),

        .fb_addr(fb_addr),
        .fb_data(fb_data),
        .fb_we(fb_we),

        .hit_pulse(hit_pulse)
    );



    // HEX DISPLAYS
    //  - HEX0, HEX1: hit count
    //  - HEX2, HEX3: speed ("10","20","30")
    //  - HEX4, HEX5: rating (F,C,b,A,S,SS)
    seven_segment u_hex0 (.i(hit_ones),        .o(HEX0));
    seven_segment u_hex1 (.i(hit_tens),        .o(HEX1));
    seven_segment u_hex2 (.i(speed_lo_digit),  .o(HEX2));
    seven_segment u_hex3 (.i(speed_hi_digit),  .o(HEX3));
    seven_segment u_hex4 (.i(rating_lo_digit), .o(HEX4));
    seven_segment u_hex5 (.i(rating_hi_digit), .o(HEX5));


    // LEDs (for debugging or leave off)
    assign LEDR = 10'd0;

endmodule

