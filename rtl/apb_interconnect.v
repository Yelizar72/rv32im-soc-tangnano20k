// APB address decoder + read mux: one master, three slaves, 4 KB per slave.
//   0x1000_0000  slave 0  UART
//   0x1000_1000  slave 1  GPIO
//   0x1000_2000  slave 2  performance counters
//   other        default slave: answers at once with PSLVERR (the CPU never hangs)
module apb_interconnect (
    // from the master
    input  wire [31:0] PADDR,
    input  wire        PSEL,
    output wire [31:0] PRDATA,
    output wire        PREADY,
    output wire        PSLVERR,
    // slave 0
    output wire        PSEL0,
    input  wire [31:0] PRDATA0,
    input  wire        PREADY0,
    input  wire        PSLVERR0,
    // slave 1
    output wire        PSEL1,
    input  wire [31:0] PRDATA1,
    input  wire        PREADY1,
    input  wire        PSLVERR1,
    // slave 2
    output wire        PSEL2,
    input  wire [31:0] PRDATA2,
    input  wire        PREADY2,
    input  wire        PSLVERR2
);
    wire hit0 = (PADDR[27:12] == 16'h0000);
    wire hit1 = (PADDR[27:12] == 16'h0001);
    wire hit2 = (PADDR[27:12] == 16'h0002);

    assign PSEL0   = PSEL && hit0;
    assign PSEL1   = PSEL && hit1;
    assign PSEL2   = PSEL && hit2;

    assign PRDATA  = hit0 ? PRDATA0  : hit1 ? PRDATA1  : hit2 ? PRDATA2  : 32'd0;
    assign PREADY  = hit0 ? PREADY0  : hit1 ? PREADY1  : hit2 ? PREADY2  : 1'b1;
    assign PSLVERR = hit0 ? PSLVERR0 : hit1 ? PSLVERR1 : hit2 ? PSLVERR2 : 1'b1;

    wire unused = &{1'b0, PADDR[31:28], PADDR[11:0]};
endmodule
