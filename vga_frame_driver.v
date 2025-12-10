// =====================================================
// vga_frame_driver
// - Wraps vga_driver + framebuffer memories
// - Reads from double-buffered display frame
// - Accepts writes into "the_vga_draw_frame" via
//   external write port (used by your game logic).
// - Resolution: 640x480, virtual 160x120 (4x4 blocks)
// =====================================================
module vga_frame_driver(

    input  clk,
    input  rst,

    output active_pixels,  // is on when we're in the active draw space
    output frame_done,     // is on when we're done writing 640*480

    // NOTE x and y that are passed out go greater than 640 for x
    // and 480 for y as those signals need to be sent for hsync and vsync
    output [9:0] x,        // current x 
    output [9:0] y,        // current y - 10 bits = 1024 ... a little more than we need

    //////////// VGA //////////
    output              VGA_BLANK_N,
    output              VGA_CLK,
    output              VGA_HS,
    output reg [7:0]    VGA_B,
    output reg [7:0]    VGA_G,
    output reg [7:0]    VGA_R,
    output              VGA_SYNC_N,
    output              VGA_VS,

    /* access ports to the frame we draw from */
    input  [14:0] the_vga_draw_frame_write_mem_address,
    input  [23:0] the_vga_draw_frame_write_mem_data,
    input         the_vga_draw_frame_write_a_pixel

);

    // Parameters (must match your earlier code)
    parameter MEMORY_SIZE          = 16'd19200; // 160*120
    parameter PIXEL_VIRTUAL_SIZE   = 16'd4;     // 4x4 pixels per memory location

    // ACTUAL VGA RESOLUTION
    parameter VGA_WIDTH  = 16'd640; 
    parameter VGA_HEIGHT = 16'd480;

    // Our reduced RESOLUTION 160 by 120 needs a memory of 19,200 words each 24 bits wide
    parameter VIRTUAL_PIXEL_WIDTH  = VGA_WIDTH  / PIXEL_VIRTUAL_SIZE; // 160
    parameter VIRTUAL_PIXEL_HEIGHT = VGA_HEIGHT / PIXEL_VIRTUAL_SIZE; // 120

    // VGA timing driver
    wire       vga_active_pixels;
    wire       vga_frame_done;
    wire [9:0] xPixel;
    wire [9:0] yPixel;

    vga_driver the_vga(
        .clk(clk),
        .rst(rst),

        .vga_clk(VGA_CLK),

        .hsync(VGA_HS),
        .vsync(VGA_VS),

        .active_pixels(vga_active_pixels),
        .frame_done(vga_frame_done),

        .xPixel(xPixel),
        .yPixel(yPixel),

        .VGA_BLANK_N(VGA_BLANK_N),
        .VGA_SYNC_N(VGA_SYNC_N)
    );

    assign active_pixels = vga_active_pixels;
    assign frame_done    = vga_frame_done;
    assign x             = xPixel;
    assign y             = yPixel;

    // Framebuffer memories
    // Double-buffer memories (display buffers)
    reg  [15:0] frame_buf_mem_address0;
    reg  [23:0] frame_buf_mem_data0;
    reg         frame_buf_mem_wren0;
    wire [23:0] frame_buf_mem_q0;

    vga_frame vga_memory0(
        .address(frame_buf_mem_address0),
        .clock(clk),
        .data(frame_buf_mem_data0),
        .wren(frame_buf_mem_wren0),
        .q(frame_buf_mem_q0)
    );
    
    reg  [15:0] frame_buf_mem_address1;
    reg  [23:0] frame_buf_mem_data1;
    reg         frame_buf_mem_wren1;
    wire [23:0] frame_buf_mem_q1;

    vga_frame vga_memory1(
        .address(frame_buf_mem_address1),
        .clock(clk),
        .data(frame_buf_mem_data1),
        .wren(frame_buf_mem_wren1),
        .q(frame_buf_mem_q1)
    );

    // This is the frame that is written to and read from for the double buffering
    reg  [15:0] the_vga_draw_frame_mem_address;
    reg  [23:0] the_vga_draw_frame_mem_data;
    reg         the_vga_draw_frame_mem_wren;
    wire [23:0] the_vga_draw_frame_mem_q;

    // This is the main memory to write to (your "draw" framebuffer)
    vga_frame the_vga_draw_frame(
        .address(the_vga_draw_frame_mem_address),
        .clock(clk),
        .data(the_vga_draw_frame_mem_data),
        .wren(the_vga_draw_frame_mem_wren),
        .q(the_vga_draw_frame_mem_q)
    );

    // ALWAYS block writes to the memory or otherwise is just being read into the framebuffer
    // External write vs internal read mux for draw framebuffer
    always @(*) begin
        /* writing from external code */
        if (the_vga_draw_frame_write_a_pixel == 1'b1) begin
            the_vga_draw_frame_mem_address = the_vga_draw_frame_write_mem_address;
            the_vga_draw_frame_mem_data    = the_vga_draw_frame_write_mem_data;
            the_vga_draw_frame_mem_wren    = 1'b1;
        end else begin
            /* just reading */
            the_vga_draw_frame_mem_address = (xPixel/PIXEL_VIRTUAL_SIZE) * VIRTUAL_PIXEL_HEIGHT
                                           + (yPixel/PIXEL_VIRTUAL_SIZE);
            the_vga_draw_frame_mem_data    = 24'd0;
            the_vga_draw_frame_mem_wren    = 1'b0;    
        end
    end

    // FSM to control the reading/writing of display buffers
    reg [7:0] S;
    reg [7:0] NS;

    parameter 
        START          = 8'd0,
        // W2M is write to memory (skipped, using MIF)
        W2M_DONE       = 8'd4,
        // The RFM = READ_FROM_MEMORY reading cycles
        RFM_INIT_START = 8'd5,
        RFM_INIT_WAIT  = 8'd6,
        RFM_DRAWING    = 8'd7,
        ERROR          = 8'hFF;

    // Which buffer is being written / read
    reg [1:0] wr_id;
    parameter MEM_INIT_WRITE        = 2'd0,
               MEM_M0_READ_M1_WRITE  = 2'd1,
               MEM_M0_WRITE_M1_READ  = 2'd2,
               MEM_ERROR             = 2'd3;

    reg [15:0] write_buf_mem_address;
    reg [23:0] write_buf_mem_data;
    reg        write_buf_mem_wren;
    reg [23:0] read_buf_mem_q;
    reg [15:0] read_buf_mem_address;

    // Next-state logic
    always @(*) begin
        case (S)
            START:          NS = W2M_DONE;
            W2M_DONE:       NS = (vga_frame_done == 1'b1) ? RFM_INIT_START : W2M_DONE;
            RFM_INIT_START: NS = RFM_INIT_WAIT;
            RFM_INIT_WAIT:  NS = (vga_frame_done == 1'b0) ? RFM_DRAWING : RFM_INIT_WAIT;
            RFM_DRAWING:    NS = (vga_frame_done == 1'b1) ? RFM_INIT_START : RFM_DRAWING;
            default:        NS = ERROR;
        endcase
    end

    // State register (only S here; wr_id is handled in the other always block)
    always @(posedge clk or negedge rst) begin
        if (rst == 1'b0) begin
            S <= START;
        end else begin
            S <= NS;
        end
    end

    // Write/read buffer addressing and copying
    always @(posedge clk or negedge rst) begin
        if (rst == 1'b0) begin
            write_buf_mem_address <= 16'd0;
            write_buf_mem_data    <= 24'd0;
            write_buf_mem_wren    <= 1'd0;
            wr_id                 <= MEM_INIT_WRITE;
            read_buf_mem_address  <= 16'd0;
        end else begin
            case (S)
                START: begin
                    write_buf_mem_address <= 16'd0;
                    write_buf_mem_data    <= 24'd0;
                    write_buf_mem_wren    <= 1'd0;
                    wr_id                 <= MEM_INIT_WRITE;
                end

                W2M_DONE: begin
                    write_buf_mem_wren <= 1'd0; // turn off writing to memory
                end

                RFM_INIT_START: begin
                    write_buf_mem_wren <= 1'd0; // turn off writing to memory
                    
                    /* swap the buffers after each frame...the double buffer */
                    if (wr_id == MEM_M0_READ_M1_WRITE)
                        wr_id <= MEM_M0_WRITE_M1_READ;
                    else
                        wr_id <= MEM_M0_READ_M1_WRITE;
                                    
                    if (yPixel < VGA_HEIGHT-1 && xPixel < VGA_WIDTH-1) // or use active_pixels
                        read_buf_mem_address <= (xPixel/PIXEL_VIRTUAL_SIZE) * VIRTUAL_PIXEL_HEIGHT
                                              + (yPixel/PIXEL_VIRTUAL_SIZE);
                end

                RFM_INIT_WAIT: begin
                    if (yPixel < VGA_HEIGHT-1 && xPixel < VGA_WIDTH-1) // or use active_pixels
                        read_buf_mem_address <= (xPixel/PIXEL_VIRTUAL_SIZE) * VIRTUAL_PIXEL_HEIGHT
                                              + (yPixel/PIXEL_VIRTUAL_SIZE);
                end

                RFM_DRAWING: begin        
                    if (yPixel < VGA_HEIGHT-1 && xPixel < VGA_WIDTH-1)
                        read_buf_mem_address <= (xPixel/PIXEL_VIRTUAL_SIZE) * VIRTUAL_PIXEL_HEIGHT
                                              + (yPixel/PIXEL_VIRTUAL_SIZE);
                    
                    // copy from the draw frame into the write buffer
                    write_buf_mem_address <= (xPixel/PIXEL_VIRTUAL_SIZE) * VIRTUAL_PIXEL_HEIGHT
                                           + (yPixel/PIXEL_VIRTUAL_SIZE);
                    write_buf_mem_data    <= the_vga_draw_frame_mem_q;
                    write_buf_mem_wren    <= 1'b1;
                end    

                default: begin
                    write_buf_mem_wren <= 1'b0;
                end
            endcase
        end
    end

    // signals that will be combinationally swapped
    // between buffers based on wr_id
    always @(*) begin
        if (wr_id == MEM_INIT_WRITE) begin
            // WRITING to BOTH
            frame_buf_mem_address0 = write_buf_mem_address;
            frame_buf_mem_data0    = write_buf_mem_data;
            frame_buf_mem_wren0    = write_buf_mem_wren;

            frame_buf_mem_address1 = write_buf_mem_address;
            frame_buf_mem_data1    = write_buf_mem_data;
            frame_buf_mem_wren1    = write_buf_mem_wren;
            
            read_buf_mem_q = frame_buf_mem_q1; // doesn't matter in this mode
        end
        else if (wr_id == MEM_M0_WRITE_M1_READ) begin
            // WRITING to MEM 0, READING FROM MEM 1
            // MEM 0 - WRITE
            frame_buf_mem_address0 = write_buf_mem_address;
            frame_buf_mem_data0    = write_buf_mem_data;
            frame_buf_mem_wren0    = write_buf_mem_wren;
            // MEM 1 - READ
            frame_buf_mem_address1 = read_buf_mem_address;
            frame_buf_mem_data1    = 24'd0;
            frame_buf_mem_wren1    = 1'b0;
            read_buf_mem_q         = frame_buf_mem_q1;
        end
        else begin
            // MEM_M0_READ_M1_WRITE:
            // MEM 0 - READ
            frame_buf_mem_address0 = read_buf_mem_address;
            frame_buf_mem_data0    = 24'd0;
            frame_buf_mem_wren0    = 1'b0;
            read_buf_mem_q         = frame_buf_mem_q0;
            // MEM 1 - WRITE
            frame_buf_mem_address1 = write_buf_mem_address;
            frame_buf_mem_data1    = write_buf_mem_data;
            frame_buf_mem_wren1    = write_buf_mem_wren;
        end
    end

    // Drive VGA from the read buffer
    always @(*) begin
        if (S == RFM_INIT_WAIT || S == RFM_INIT_START || S == RFM_DRAWING)
            {VGA_R, VGA_G, VGA_B} = read_buf_mem_q;
        else
            {VGA_R, VGA_G, VGA_B} = 24'h000000; // black otherwise
    end

endmodule