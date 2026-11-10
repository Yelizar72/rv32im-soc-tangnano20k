// UART with 16-byte TX and RX FIFOs on an APB slave port. 8N1, fixed baud rate.
//
// Registers (offset from the slave base)
//   0x00 DATA    W: push a byte into the TX FIFO. If the FIFO is full the APB transfer
//                   waits (PREADY low) until there is room: no byte is ever lost, the CPU stalls.
//                R: pop the oldest received byte (0 if the RX FIFO is empty).
//   0x04 STATUS  R: bit0 TX_FULL, bit1 TX_IDLE (FIFO empty and line idle), bit2 RX_EMPTY,
//                   bit3 RX_FULL, bit4 RX_OVERRUN (sticky), bit5 RX_FRAME_ERR (sticky)
//                W: write 1 to bit4 / bit5 to clear them
//   0x08 LEVELS  R: bits 4:0 TX FIFO level, bits 12:8 RX FIFO level
//   other        PSLVERR
// Event outputs feed the performance counters (apb_perf.v).
module apb_uart #(
    parameter integer CLK_HZ  = 27_000_000,
    parameter integer BAUD    = 115_200,
    parameter integer FIFO_AW = 4                    // 16 bytes
) (
    input  wire        PCLK,
    input  wire        PRESETn,
    input  wire        PSEL,
    input  wire        PENABLE,
    input  wire        PWRITE,
    input  wire [11:0] PADDR,
    input  wire [31:0] PWDATA,
    input  wire [3:0]  PSTRB,
    output reg  [31:0] PRDATA,
    output wire        PREADY,
    output wire        PSLVERR,
    output wire        uart_tx,
    input  wire        uart_rx,
    // events for the performance counters
    output wire        ev_tx_stall,                 // DATA write held: TX FIFO full
    output wire        ev_tx_full,                  // TX FIFO full this cycle
    output wire        ev_rx_drop                   // received byte dropped: RX FIFO full
);
    localparam integer CPB = CLK_HZ / BAUD;
    localparam [11:0] A_DATA = 12'h000, A_STATUS = 12'h004, A_LEVELS = 12'h008;

    // ---------------- FIFOs -----------------------------------------------------------
    wire [7:0]       tx_dout, rx_dout, rx_byte;
    wire             tx_full, tx_empty, rx_full, rx_empty;
    wire [FIFO_AW:0] tx_count, rx_count;
    wire             tx_push, tx_pop, rx_push, rx_pop;

    fifo #(.WIDTH(8), .AW(FIFO_AW)) u_txf (
        .clk(PCLK), .resetn(PRESETn), .push(tx_push), .din(PWDATA[7:0]), .pop(tx_pop),
        .dout(tx_dout), .full(tx_full), .empty(tx_empty), .count(tx_count));

    fifo #(.WIDTH(8), .AW(FIFO_AW)) u_rxf (
        .clk(PCLK), .resetn(PRESETn), .push(rx_push), .din(rx_byte), .pop(rx_pop),
        .dout(rx_dout), .full(rx_full), .empty(rx_empty), .count(rx_count));

    // ---------------- APB access decode ---------------------------------------------------
    wire access   = PSEL && PENABLE;
    wire at_data  = (PADDR == A_DATA);
    wire known    = at_data || (PADDR == A_STATUS) || (PADDR == A_LEVELS);
    wire wr_data  = access && PWRITE && at_data && PSTRB[0];

    assign PREADY  = !(wr_data && tx_full);          // backpressure: wait for TX FIFO room
    assign PSLVERR = access && !known;

    assign tx_push = wr_data && !tx_full;
    assign rx_pop  = access && !PWRITE && at_data && !rx_empty;

    // ---------------- transmitter: FIFO -> shift register ---------------------------
    reg       tx_start;
    reg [7:0] tx_byte;
    wire      tx_busy;

    assign tx_pop = !tx_busy && !tx_start && !tx_empty;

    always @(posedge PCLK) begin
        if (!PRESETn) begin
            tx_start <= 1'b0;
            tx_byte  <= 8'd0;
        end else begin
            tx_start <= tx_pop;
            if (tx_pop) tx_byte <= tx_dout;
        end
    end

    uart_tx #(.CLKS_PER_BIT(CPB)) u_tx (
        .clk(PCLK), .resetn(PRESETn), .start(tx_start), .data(tx_byte),
        .tx(uart_tx), .busy(tx_busy));

    wire tx_idle = tx_empty && !tx_busy && !tx_start;

    // ---------------- receiver: shift register -> FIFO -------------------------------
    wire rx_valid, rx_ferr;
    uart_rx #(.CLKS_PER_BIT(CPB)) u_rx (
        .clk(PCLK), .resetn(PRESETn), .rx(uart_rx),
        .data(rx_byte), .valid(rx_valid), .frame_err(rx_ferr));

    assign rx_push = rx_valid;                      // dropped by the FIFO if full

    assign ev_tx_stall = wr_data && tx_full;
    assign ev_tx_full  = tx_full;
    assign ev_rx_drop  = rx_valid && rx_full;

    reg overrun, ferr;
    wire clr = access && PWRITE && (PADDR == A_STATUS) && PSTRB[0];
    always @(posedge PCLK) begin
        if (!PRESETn) begin
            overrun <= 1'b0;
            ferr    <= 1'b0;
        end else begin
            if (rx_valid && rx_full)       overrun <= 1'b1;
            else if (clr && PWDATA[4])     overrun <= 1'b0;
            if (rx_ferr)                   ferr    <= 1'b1;
            else if (clr && PWDATA[5])     ferr    <= 1'b0;
        end
    end

    // ---------------- read data ----------------------------------------------------------
    localparam integer PADW = 8 - (FIFO_AW + 1);
    wire [7:0] tx_lvl = {{PADW{1'b0}}, tx_count};
    wire [7:0] rx_lvl = {{PADW{1'b0}}, rx_count};

    always @(*) begin
        case (PADDR)
            A_DATA:   PRDATA = {24'd0, rx_empty ? 8'd0 : rx_dout};
            A_STATUS: PRDATA = {26'd0, ferr, overrun, rx_full, rx_empty, tx_idle, tx_full};
            A_LEVELS: PRDATA = {16'd0, rx_lvl, tx_lvl};
            default:  PRDATA = 32'd0;
        endcase
    end

    wire unused = &{1'b0, PWDATA[31:8], PSTRB[3:1]};
endmodule
