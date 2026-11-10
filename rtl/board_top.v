// Tang Nano 20K pin wrapper around soc_top.
//   - power-on reset, and button S1 = reset (re-runs the firmware)
//   - LEDs are active low on the board
//   - if the CPU traps (illegal instruction / misaligned access), all six LEDs light up
module board_top #(
    parameter FIRMWARE = "build/firmware.hex"
) (
    input  wire       clk,       // 27 MHz
    input  wire       btn_s1,    // high while pressed
    input  wire       uart_rx,
    output wire       uart_tx,
    output wire [5:0] led
);
    // button synchronizer + power-on reset: hold reset for 255 clocks.
    // These two registers are the only ones that rely on their power-up value:
    // they create the reset, so nothing can reset them. Hence the lint waiver.
    /* verilator lint_off PROCASSINIT */
    reg [1:0] btn_sync = 2'b00;
    reg [7:0] por      = 8'd0;
    /* verilator lint_on PROCASSINIT */
    always @(posedge clk) begin
        btn_sync <= {btn_sync[0], btn_s1};
        if (btn_sync[1])  por <= 8'd0;
        else if (~&por)   por <= por + 8'd1;
    end
    wire resetn = &por;

    wire [5:0] leds;
    wire       trap;

    soc_top #(.FIRMWARE(FIRMWARE)) u_soc (
        .clk(clk), .resetn(resetn),
        .uart_tx(uart_tx), .uart_rx(uart_rx),
        .leds(leds), .trap(trap));

    assign led = trap ? 6'b000000 : ~leds;
endmodule
