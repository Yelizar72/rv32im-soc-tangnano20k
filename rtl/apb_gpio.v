// LED register on an APB slave port.
//   0x00 LED  RW: bits 5:0, 1 = LED on
//   other     PSLVERR
module apb_gpio (
    input  wire        PCLK,
    input  wire        PRESETn,
    input  wire        PSEL,
    input  wire        PENABLE,
    input  wire        PWRITE,
    input  wire [11:0] PADDR,
    input  wire [31:0] PWDATA,
    input  wire [3:0]  PSTRB,
    output wire [31:0] PRDATA,
    output wire        PREADY,
    output wire        PSLVERR,
    output reg  [5:0]  leds
);
    wire access = PSEL && PENABLE;
    wire at_led = (PADDR == 12'h000);

    assign PREADY  = 1'b1;
    assign PSLVERR = access && !at_led;
    assign PRDATA  = at_led ? {26'd0, leds} : 32'd0;

    always @(posedge PCLK) begin
        if (!PRESETn)                              leds <= 6'd0;
        else if (access && PWRITE && at_led && PSTRB[0]) leds <= PWDATA[5:0];
    end

    wire unused = &{1'b0, PWDATA[31:6], PSTRB[3:1]};
endmodule
