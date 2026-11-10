// UART receiver, 8N1. Samples each bit in its middle.
module uart_rx #(
    parameter integer CLKS_PER_BIT = 234            // f_clk / baud (27 MHz / 115200)
) (
    input  wire       clk,
    input  wire       resetn,
    input  wire       rx,                           // serial line, idle high
    output reg  [7:0] data,
    output reg        valid,                        // one-clock pulse when `data` is new
    output reg        frame_err                     // one-clock pulse: stop bit was 0, byte dropped
);
    localparam integer HALF_I = CLKS_PER_BIT / 2 - 1;
    localparam integer LAST_I = CLKS_PER_BIT - 1;
    localparam [15:0]  HALF   = HALF_I[15:0];
    localparam [15:0]  LAST   = LAST_I[15:0];

    localparam [2:0] IDLE = 3'd0, START = 3'd1, BITS = 3'd2, STOP = 3'd3,
                     WAIT_HIGH = 3'd4;              // after a framing error: wait for idle line

    // two-flop synchronizer: rx comes from outside the clock domain
    reg rx_meta, rx_s;
    reg [2:0]  state;
    reg [15:0] cnt;
    reg [2:0]  bit_i;

    always @(posedge clk) begin
        if (!resetn) begin
            rx_meta   <= 1'b1;
            rx_s      <= 1'b1;
            state     <= IDLE;
            cnt       <= 16'd0;
            bit_i     <= 3'd0;
            data      <= 8'd0;
            valid     <= 1'b0;
            frame_err <= 1'b0;
        end else begin
            rx_meta   <= rx;
            rx_s      <= rx_meta;
            valid     <= 1'b0;
            frame_err <= 1'b0;
            case (state)
                IDLE: if (!rx_s) begin               // falling edge = start bit
                    cnt   <= 16'd0;
                    state <= START;
                end
                START: if (cnt == HALF) begin         // middle of start bit
                    cnt   <= 16'd0;
                    bit_i <= 3'd0;
                    state <= rx_s ? IDLE : BITS;      // high again = glitch
                end else
                    cnt <= cnt + 16'd1;
                BITS: if (cnt == LAST) begin          // middle of each data bit
                    cnt         <= 16'd0;
                    data[bit_i] <= rx_s;              // LSB first
                    if (bit_i == 3'd7) state <= STOP;
                    bit_i <= bit_i + 3'd1;
                end else
                    cnt <= cnt + 16'd1;
                STOP: if (cnt == LAST) begin
                    valid     <= rx_s;
                    frame_err <= !rx_s;
                    // a low stop bit means the line is still low: going straight to IDLE
                    // would read that as a new start bit and decode a phantom byte
                    state     <= rx_s ? IDLE : WAIT_HIGH;
                end else
                    cnt <= cnt + 16'd1;
                WAIT_HIGH: if (rx_s) state <= IDLE;
                default:   state <= IDLE;
            endcase
        end
    end
endmodule
