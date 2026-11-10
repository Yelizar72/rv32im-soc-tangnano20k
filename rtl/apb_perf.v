// Performance counters on an APB slave port. Eight 32-bit counters, each adding 1 on
// every clock its event signal is high, while ENABLE is set. They wrap after 2^32
// (159 s at 27 MHz).
//
// Registers (offset from the slave base)
//   0x00 CTRL       RW  bit0 ENABLE (1 after reset); write bit1 = 1 to clear all counters
//                       (clear wins over counting in that cycle)
//   0x04 CYCLES     R   clock cycles
//   0x08 MEM_WAIT   R   cycles the CPU waits for any memory or peripheral access
//   0x0C APB_WAIT   R   wait states inserted by APB slaves (PREADY low in ACCESS)
//   0x10 APB_XFER   R   APB transfers completed
//   0x14 BUS_ERR    R   accesses that ended in an error (PSLVERR or unmapped address)
//   0x18 TX_STALL   R   cycles a UART DATA write was held because the TX FIFO was full
//   0x1C TX_FULL    R   cycles the UART TX FIFO was full (backpressure asserted)
//   0x20 RX_DROP    R   received bytes dropped because the RX FIFO was full
//   other           PSLVERR; writes to counters are ignored
module apb_perf #(
    parameter integer N = 8
) (
    input  wire         PCLK,
    input  wire         PRESETn,
    input  wire         PSEL,
    input  wire         PENABLE,
    input  wire         PWRITE,
    input  wire [11:0]  PADDR,
    input  wire [31:0]  PWDATA,
    input  wire [3:0]   PSTRB,
    output reg  [31:0]  PRDATA,
    output wire         PREADY,
    output wire         PSLVERR,
    input  wire [N-1:0] events          // bit i drives counter i
);
    wire       access = PSEL && PENABLE;
    wire [9:0] index  = PADDR[11:2];
    wire       at_ctrl  = (PADDR == 12'h000);
    localparam [9:0] LAST = N[9:0];                  // index of the last counter register
    wire       at_count = (PADDR[1:0] == 2'b00) && (index >= 10'd1) && (index <= LAST);

    assign PREADY  = 1'b1;
    assign PSLVERR = access && !(at_ctrl || at_count);

    reg  enable;
    wire clear = access && PWRITE && at_ctrl && PSTRB[0] && PWDATA[1];

    always @(posedge PCLK) begin
        if (!PRESETn)                                   enable <= 1'b1;
        else if (access && PWRITE && at_ctrl && PSTRB[0]) enable <= PWDATA[0];
    end

    reg [31:0] count [0:N-1];
    genvar i;
    generate
        for (i = 0; i < N; i = i + 1) begin : g_cnt
            always @(posedge PCLK) begin
                if (!PRESETn || clear)        count[i] <= 32'd0;
                else if (enable && events[i]) count[i] <= count[i] + 32'd1;
            end
        end
    endgenerate

    wire [9:0] sel = index - 10'd1;
    always @(*) begin
        if (at_ctrl)       PRDATA = {31'd0, enable};
        else if (at_count) PRDATA = count[sel[$clog2(N)-1:0]];
        else               PRDATA = 32'd0;
    end

    wire unused = &{1'b0, PWDATA[31:2], PSTRB[3:1], sel[9:$clog2(N)]};
endmodule
