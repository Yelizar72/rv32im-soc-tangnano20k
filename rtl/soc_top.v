// RV32IM SoC: PicoRV32 + 8 KB ROM + 8 KB RAM + APB bus (UART with FIFOs, GPIO,
// performance counters).
//
// Memory map
//   0x0000_0000 - 0x0000_1FFF  ROM 8 KB: firmware image (code, constants, .data initial values).
//                              Preloaded at configuration; writes are ignored.
//   0x0000_2000 - 0x0000_3FFF  RAM 8 KB: .data, .bss, stack
//   0x1000_0000                APB slave 0: UART  (DATA, STATUS, LEVELS)
//   0x1000_1000                APB slave 1: GPIO  (LED)
//   0x1000_2000                APB slave 2: performance counters
//   0x1xxx_xxxx, other         APB default slave: PSLVERR, reads 0
//   anything else              reads 0, writes ignored (never hangs the CPU)
module soc_top #(
    parameter integer CLK_HZ    = 27_000_000,
    parameter integer BAUD      = 115_200,
    parameter         FIRMWARE  = "build/firmware.hex"
) (
    input  wire       clk,
    input  wire       resetn,       // active low, synchronous to clk
    output wire       uart_tx,
    input  wire       uart_rx,
    output wire [5:0] leds,         // 1 = on
    output wire       trap          // CPU stopped on an illegal instruction / misaligned access
);
    localparam integer ROM_WORDS = 2048;   // 8 KB
    localparam integer RAM_WORDS = 2048;   // 8 KB
    localparam integer AW        = 11;     // word address bits per memory

    // ---------------- CPU -------------------------------------------------------------
    wire        mem_valid, mem_instr;
    wire        mem_ready;
    wire [31:0] mem_addr, mem_wdata, mem_rdata;
    wire [3:0]  mem_wstrb;

    // CPU outputs this SoC does not use (look-ahead bus, co-processor, IRQ, trace)
    wire        nc_la_read, nc_la_write, nc_pcpi_valid, nc_trace_valid;
    wire [31:0] nc_la_addr, nc_la_wdata, nc_pcpi_insn, nc_pcpi_rs1, nc_pcpi_rs2, nc_eoi;
    wire [3:0]  nc_la_wstrb;
    wire [35:0] nc_trace_data;

    picorv32 #(
        .ENABLE_COUNTERS   (1),      // rdcycle / rdinstret
        .ENABLE_COUNTERS64 (1),
        .BARREL_SHIFTER    (1),
        .COMPRESSED_ISA    (0),
        .ENABLE_FAST_MUL   (1),      // M extension: MUL* in DSP blocks
        .ENABLE_DIV        (1),      // M extension: DIV/REM, iterative
        .ENABLE_IRQ        (0),
        .CATCH_MISALIGN    (1),
        .CATCH_ILLINSN     (1),
        .PROGADDR_RESET    (32'h0000_0000),
        .STACKADDR         (32'h0000_4000)   // top of RAM
    ) cpu (
        .clk(clk), .resetn(resetn), .trap(trap),
        .mem_valid(mem_valid), .mem_instr(mem_instr), .mem_ready(mem_ready),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb), .mem_rdata(mem_rdata),
        // unused interfaces
        .mem_la_read(nc_la_read), .mem_la_write(nc_la_write), .mem_la_addr(nc_la_addr),
        .mem_la_wdata(nc_la_wdata), .mem_la_wstrb(nc_la_wstrb),
        .pcpi_valid(nc_pcpi_valid), .pcpi_insn(nc_pcpi_insn),
        .pcpi_rs1(nc_pcpi_rs1), .pcpi_rs2(nc_pcpi_rs2),
        .pcpi_wr(1'b0), .pcpi_rd(32'd0), .pcpi_wait(1'b0), .pcpi_ready(1'b0),
        .irq(32'd0), .eoi(nc_eoi),
        .trace_valid(nc_trace_valid), .trace_data(nc_trace_data)
    );

    // ---------------- address decode --------------------------------------------------
    wire sel_rom = mem_valid && (mem_addr[31:13] == 19'd0);
    wire sel_ram = mem_valid && (mem_addr[31:13] == 19'd1);
    wire sel_apb = mem_valid && (mem_addr[31:28] == 4'h1);
    wire sel_err = mem_valid && !sel_rom && !sel_ram && !sel_apb;

    // ---------------- ROM and RAM (one wait state each) ------------------------------
    reg         rom_ready, ram_ready, err_ready;
    wire [31:0] rom_rdata, ram_rdata;

    ram #(.WORDS(ROM_WORDS), .INIT(FIRMWARE)) u_rom (
        .clk(clk), .en(sel_rom && !rom_ready), .wstrb(4'b0000),     // writes ignored
        .addr(mem_addr[AW+1:2]), .wdata(32'd0), .rdata(rom_rdata));

    ram #(.WORDS(RAM_WORDS), .INIT("")) u_ram (
        .clk(clk), .en(sel_ram && !ram_ready), .wstrb(mem_wstrb),
        .addr(mem_addr[AW+1:2]), .wdata(mem_wdata), .rdata(ram_rdata));

    always @(posedge clk) begin
        if (!resetn) begin
            rom_ready <= 1'b0;
            ram_ready <= 1'b0;
            err_ready <= 1'b0;
        end else begin
            rom_ready <= sel_rom && !rom_ready;
            ram_ready <= sel_ram && !ram_ready;
            err_ready <= sel_err && !err_ready;
        end
    end

    // ---------------- APB bus ---------------------------------------------------------------
    wire        apb_ready, apb_err, apb_wait;
    wire [31:0] apb_rdata;
    wire [31:0] PADDR, PWDATA, PRDATA;
    wire [3:0]  PSTRB;
    wire        PSEL, PENABLE, PWRITE, PREADY, PSLVERR;

    apb_bridge u_bridge (
        .clk(clk), .resetn(resetn),
        .valid(sel_apb), .addr(mem_addr), .wdata(mem_wdata), .wstrb(mem_wstrb),
        .ready(apb_ready), .rdata(apb_rdata), .err(apb_err), .wait_cycle(apb_wait),
        .PADDR(PADDR), .PSEL(PSEL), .PENABLE(PENABLE), .PWRITE(PWRITE),
        .PWDATA(PWDATA), .PSTRB(PSTRB), .PRDATA(PRDATA), .PREADY(PREADY), .PSLVERR(PSLVERR));

    wire        PSEL_UART, PSEL_GPIO, PSEL_PERF;
    wire [31:0] PRDATA_UART, PRDATA_GPIO, PRDATA_PERF;
    wire        PREADY_UART, PREADY_GPIO, PREADY_PERF;
    wire        PSLVERR_UART, PSLVERR_GPIO, PSLVERR_PERF;
    wire        ev_tx_stall, ev_tx_full, ev_rx_drop;

    apb_interconnect u_ic (
        .PADDR(PADDR), .PSEL(PSEL), .PRDATA(PRDATA), .PREADY(PREADY), .PSLVERR(PSLVERR),
        .PSEL0(PSEL_UART), .PRDATA0(PRDATA_UART), .PREADY0(PREADY_UART), .PSLVERR0(PSLVERR_UART),
        .PSEL1(PSEL_GPIO), .PRDATA1(PRDATA_GPIO), .PREADY1(PREADY_GPIO), .PSLVERR1(PSLVERR_GPIO),
        .PSEL2(PSEL_PERF), .PRDATA2(PRDATA_PERF), .PREADY2(PREADY_PERF), .PSLVERR2(PSLVERR_PERF));

    apb_uart #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_uart (
        .PCLK(clk), .PRESETn(resetn),
        .PSEL(PSEL_UART), .PENABLE(PENABLE), .PWRITE(PWRITE), .PADDR(PADDR[11:0]),
        .PWDATA(PWDATA), .PSTRB(PSTRB), .PRDATA(PRDATA_UART), .PREADY(PREADY_UART),
        .PSLVERR(PSLVERR_UART), .uart_tx(uart_tx), .uart_rx(uart_rx),
        .ev_tx_stall(ev_tx_stall), .ev_tx_full(ev_tx_full), .ev_rx_drop(ev_rx_drop));

    apb_gpio u_gpio (
        .PCLK(clk), .PRESETn(resetn),
        .PSEL(PSEL_GPIO), .PENABLE(PENABLE), .PWRITE(PWRITE), .PADDR(PADDR[11:0]),
        .PWDATA(PWDATA), .PSTRB(PSTRB), .PRDATA(PRDATA_GPIO), .PREADY(PREADY_GPIO),
        .PSLVERR(PSLVERR_GPIO), .leds(leds));

    // performance counter events, in register order (see apb_perf.v)
    wire [7:0] perf_events = {
        ev_rx_drop,                 // 7 RX_DROP
        ev_tx_full,                 // 6 TX_FULL
        ev_tx_stall,                // 5 TX_STALL
        apb_err | err_ready,        // 4 BUS_ERR: PSLVERR, or unmapped address on the CPU bus
        apb_ready,                  // 3 APB_XFER
        apb_wait,                   // 2 APB_WAIT
        mem_valid && !mem_ready,    // 1 MEM_WAIT
        1'b1                        // 0 CYCLES
    };

    apb_perf #(.N(8)) u_perf (
        .PCLK(clk), .PRESETn(resetn),
        .PSEL(PSEL_PERF), .PENABLE(PENABLE), .PWRITE(PWRITE), .PADDR(PADDR[11:0]),
        .PWDATA(PWDATA), .PSTRB(PSTRB), .PRDATA(PRDATA_PERF), .PREADY(PREADY_PERF),
        .PSLVERR(PSLVERR_PERF), .events(perf_events));

    // ---------------- read mux ----------------------------------------------------------
    assign mem_ready = rom_ready | ram_ready | apb_ready | err_ready;
    assign mem_rdata = rom_ready ? rom_rdata :
                       ram_ready ? ram_rdata :
                       apb_ready ? apb_rdata : 32'd0;

    // tell lint these are intentionally unused
    wire unused = &{1'b0, mem_instr,
                    nc_la_read, nc_la_write, nc_la_addr, nc_la_wdata, nc_la_wstrb,
                    nc_pcpi_valid, nc_pcpi_insn, nc_pcpi_rs1, nc_pcpi_rs2,
                    nc_eoi, nc_trace_valid, nc_trace_data};
endmodule
