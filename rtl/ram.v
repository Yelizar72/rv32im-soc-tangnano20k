// Single-port on-chip memory, 32-bit words with byte write enables.
// Synchronous read: data appears one clock after `en`. Maps to Gowin BSRAM.
// INIT = "" leaves it uninitialized (RAM); otherwise it is preloaded from a
// $readmemh file at configuration time (ROM holding the firmware image).
module ram #(
    parameter integer WORDS = 2048,              // 2048 x 32 bit = 8 KB
    parameter         INIT  = ""
) (
    input  wire                     clk,
    input  wire                     en,
    input  wire [3:0]               wstrb,       // byte enables; 0 = read
    input  wire [$clog2(WORDS)-1:0] addr,        // word address
    input  wire [31:0]              wdata,
    output reg  [31:0]              rdata
);
    reg [31:0] mem [0:WORDS-1];

    generate
        if (INIT != "") begin : g_init
            initial $readmemh(INIT, mem);
        end
    endgenerate

    always @(posedge clk) begin
        if (en) begin
            rdata <= mem[addr];
            if (wstrb[0]) mem[addr][ 7: 0] <= wdata[ 7: 0];
            if (wstrb[1]) mem[addr][15: 8] <= wdata[15: 8];
            if (wstrb[2]) mem[addr][23:16] <= wdata[23:16];
            if (wstrb[3]) mem[addr][31:24] <= wdata[31:24];
        end
    end
endmodule
