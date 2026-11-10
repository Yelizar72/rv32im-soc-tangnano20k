// UART transmitter, 8N1. Pulse `start` with `data` while `busy` is low.
module uart_tx #(
    parameter integer CLKS_PER_BIT = 234            // f_clk / baud (27 MHz / 115200)
) (
    input  wire       clk,
    input  wire       resetn,
    input  wire       start,
    input  wire [7:0] data,
    output reg        tx,                           // idle high
    output wire       busy
);
    localparam integer  LAST_I = CLKS_PER_BIT - 1;
    localparam [15:0]   LAST   = LAST_I[15:0];      // explicit 16-bit compare value

    reg [9:0]  shift;                               // {stop, data[7:0], start}
    reg [3:0]  left;                                // bits still to send
    reg [15:0] cnt;

    assign busy = (left != 4'd0);

    always @(posedge clk) begin
        if (!resetn) begin
            shift <= 10'h3FF;
            left  <= 4'd0;
            cnt   <= 16'd0;
            tx    <= 1'b1;
        end else begin
            if (!busy) begin
                if (start) begin
                    shift <= {1'b1, data, 1'b0};
                    left  <= 4'd10;
                    cnt   <= 16'd0;
                end
            end else if (cnt == LAST) begin
                cnt   <= 16'd0;
                shift <= {1'b1, shift[9:1]};
                left  <= left - 4'd1;
            end else
                cnt <= cnt + 16'd1;

            tx <= busy ? shift[0] : 1'b1;
        end
    end
endmodule
