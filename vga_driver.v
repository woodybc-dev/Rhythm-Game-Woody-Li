// =====================================================
// vga_driver: 640x480@60Hz timing generator
// - Generates xPixel, yPixel, hsync, vsync, active_pixels, frame_done
// - Pixel clock is vga_clk (clk/2)
// =====================================================
module vga_driver(
    input         clk,
    input         rst,

    output reg    vga_clk,

    output reg    hsync,
    output reg    vsync,

    output reg    active_pixels,
    output reg    frame_done,

    output reg [9:0] xPixel,
    output reg [9:0] yPixel,

    output reg    VGA_BLANK_N,
    output reg    VGA_SYNC_N
);

    // 640x480 timings (from your example)
    parameter HA_END = 10'd639;
    parameter HS_STA = HA_END + 16;
    parameter HS_END = HS_STA + 96;
    parameter WIDTH  = 10'd799;

    parameter VA_END = 10'd479;
    parameter VS_STA = VA_END + 10;
    parameter VS_END = VS_STA + 2;
    parameter HEIGHT = 10'd524;

    // Combinational timing signals
    always @(*) begin
        hsync         = ~((xPixel >= HS_STA) && (xPixel < HS_END));
        vsync         = ~((yPixel >= VS_STA) && (yPixel < VS_END));
        active_pixels = (xPixel <= HA_END && yPixel <= VA_END);
        frame_done    = (yPixel >= VA_END);

        VGA_BLANK_N   = active_pixels;
        VGA_SYNC_N    = 1'b1;
    end

    // Pixel counters and pixel clock
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            vga_clk <= 1'b0;
            xPixel  <= 10'd0;
            yPixel  <= 10'd0;
        end else begin
            vga_clk = ~vga_clk; // divide by 2

            if (vga_clk == 1'b1) begin
                if (xPixel == WIDTH) begin
                    xPixel <= 10'd0;
                    if (yPixel == HEIGHT)
                        yPixel <= 10'd0;
                    else
                        yPixel <= yPixel + 1'b1;
                end else begin
                    xPixel <= xPixel + 1'b1;
                end
            end
        end
    end

endmodule