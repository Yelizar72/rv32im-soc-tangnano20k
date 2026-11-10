// Synchronous FIFO, first-word-fall-through: `dout` shows the oldest entry while !empty.
// Small depths map to LUT RAM. push when full and pop when empty are ignored.
module fifo #(
    parameter integer WIDTH = 8,
    parameter integer AW    = 4                      // depth = 2^AW
) (
    input  wire             clk,
    input  wire             resetn,
    input  wire             push,
    input  wire [WIDTH-1:0] din,
    input  wire             pop,
    output wire [WIDTH-1:0] dout,
    output wire             full,
    output wire             empty,
    output wire [AW:0]      count                    // 0 .. 2^AW
);
    reg [WIDTH-1:0] mem [0:(1<<AW)-1];
    reg [AW:0]      wp, rp;                           // extra MSB tells full from empty

    assign count = wp - rp;
    assign empty = (wp == rp);
    assign full  = (wp[AW] != rp[AW]) && (wp[AW-1:0] == rp[AW-1:0]);
    assign dout  = mem[rp[AW-1:0]];

    always @(posedge clk)
        if (push && !full) mem[wp[AW-1:0]] <= din;

    always @(posedge clk) begin
        if (!resetn) begin
            wp <= 0;
            rp <= 0;
        end else begin
            if (push && !full)  wp <= wp + 1'b1;
            if (pop  && !empty) rp <= rp + 1'b1;
        end
    end
endmodule
