// PicoRV32 native memory interface -> AMBA APB master (APB4 signals, without PPROT).
//
// One APB transfer per CPU access:
//   IDLE   -> SETUP  : PSEL=1, PENABLE=0, address/data/strobes driven
//   SETUP  -> ACCESS : PENABLE=1
//   ACCESS -> IDLE   : when the slave raises PREADY; read data and PSLVERR are captured
// The CPU sees `ready` one cycle later. A slave that holds PREADY low stalls the CPU
// (used by the UART for TX-FIFO backpressure); `wait_cycle` marks every such cycle.
module apb_bridge (
    input  wire        clk,
    input  wire        resetn,
    // from the CPU
    input  wire        valid,
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    input  wire [3:0]  wstrb,
    output reg         ready,
    output reg  [31:0] rdata,
    output reg         err,         // one-cycle pulse: transfer ended with PSLVERR
    output wire        wait_cycle,  // slave is inserting a wait state this cycle
    // APB master
    output reg  [31:0] PADDR,
    output reg         PSEL,
    output reg         PENABLE,
    output reg         PWRITE,
    output reg  [31:0] PWDATA,
    output reg  [3:0]  PSTRB,
    input  wire [31:0] PRDATA,
    input  wire        PREADY,
    input  wire        PSLVERR
);
    localparam [1:0] IDLE = 2'd0, SETUP = 2'd1, ACCESS = 2'd2;
    reg [1:0] st;

    assign wait_cycle = (st == ACCESS) && !PREADY;

    always @(posedge clk) begin
        if (!resetn) begin
            st      <= IDLE;
            ready   <= 1'b0;
            err     <= 1'b0;
            rdata   <= 32'd0;
            PADDR   <= 32'd0;
            PSEL    <= 1'b0;
            PENABLE <= 1'b0;
            PWRITE  <= 1'b0;
            PWDATA  <= 32'd0;
            PSTRB   <= 4'd0;
        end else begin
            ready <= 1'b0;
            err   <= 1'b0;
            case (st)
                IDLE: if (valid && !ready) begin   // !ready: the CPU drops valid one cycle late
                    PADDR   <= addr;
                    PWRITE  <= |wstrb;
                    PWDATA  <= wdata;
                    PSTRB   <= wstrb;
                    PSEL    <= 1'b1;
                    PENABLE <= 1'b0;
                    st      <= SETUP;
                end
                SETUP: begin
                    PENABLE <= 1'b1;
                    st      <= ACCESS;
                end
                ACCESS: if (PREADY) begin
                    PSEL    <= 1'b0;
                    PENABLE <= 1'b0;
                    rdata   <= PRDATA;
                    err     <= PSLVERR;
                    ready   <= 1'b1;
                    st      <= IDLE;
                end
                default: st <= IDLE;
            endcase
        end
    end
endmodule
