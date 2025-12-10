// =====================================================
// speed_selector
// - Uses SW[1:0] to choose note falling speed
//   SW1=0, SW0=0 -> 1x  -> display "10"
//   SW1=0, SW0=1 -> 2x  -> display "20"
//   SW1=1,   X   -> 3x  -> display "30"
// - Outputs:
//   note_speed = 1,2,3 (encoded as 2'd1, 2'd2, 2'd3)
//   digit_hi   = 1/2/3  for HEX3
//   digit_lo   = 0      for HEX2
// =====================================================
module speed_selector (
    input  wire [1:0] sw_speed,      // {SW1, SW0}
    output reg  [1:0] note_speed,    // 2'd1, 2'd2, 2'd3
    output reg  [3:0] digit_hi,      // HEX3
    output reg  [3:0] digit_lo       // HEX2
);

    always @(*) begin
        // default: 1.0x
        note_speed = 2'd1;
        digit_hi   = 4'd1;
        digit_lo   = 4'd0;

        if (sw_speed[1]) begin
            // 3.0x speed
            note_speed = 2'd3;
            digit_hi   = 4'd3;
            digit_lo   = 4'd0;
        end
        else if (sw_speed[0]) begin
            // 2.0x speed
            note_speed = 2'd2;
            digit_hi   = 4'd2;
            digit_lo   = 4'd0;
        end
        // else: keep default 1.0x
    end

endmodule
