/* Firmware: checks every hardware feature from software, profiles two UART drivers with
 * the performance counters, then runs an echo prompt.
 *
 *   .data restore   an initialized global reads its initial value after every reset
 *   ROM / errors    ROM writes are ignored; unmapped accesses return 0, count as BUS_ERR
 *   M extension     self-test against a software reference
 *   perf counters   CYCLES agrees with rdcycle
 *   TX FIFO         fills at 16; the next write is held by the bus; TX_STALL = held cycles
 *   RX FIFO         20 bytes into 16: overrun flag, RX_DROP = 4, write-1-to-clear
 *   profile         polling driver vs backpressure driver, measured by the counters
 */
#include <stdint.h>
#include "soc.h"
#include "uart.h"
#include "mtest.h"

static volatile uint32_t boot_value = 0xC0FFEE00u;   /* lives in .data */
static uint32_t n_pass, n_fail;

static void result(int ok)
{
    if (ok) { n_pass++; uart_puts(" -> PASS\n"); }
    else    { n_fail++; uart_puts(" -> FAIL\n"); }
}

static void test_data_restore(void)
{
    uint32_t v = boot_value;
    uart_puts(".data restored at boot: value ");
    uart_puthex(v);
    result(v == 0xC0FFEE00u);
    boot_value = v + 1u;           /* change it; the next reset must undo this */
}

static void test_rom_and_bus_errors(void)
{
    volatile uint32_t *rom_word = (volatile uint32_t *)0x00000100u;
    uint32_t before = *rom_word;
    *rom_word = ~before;
    uart_puts("ROM write ignored");
    result(*rom_word == before);

    volatile uint32_t *no_slave = (volatile uint32_t *)0x10003000u;   /* APB: no slave 3 */
    volatile uint32_t *no_mem   = (volatile uint32_t *)0x20000000u;   /* not decoded at all */
    perf_start();
    uint32_t v1 = *no_slave;
    *no_slave = 0x12345678u;
    uint32_t v2 = *no_mem;
    *no_mem = 0x12345678u;
    perf_stop();
    uint32_t errs = PERF_CNT(PERF_BUS_ERR);
    uart_puts("Unmapped accesses (2 APB, 2 CPU bus): read ");
    uart_puthex(v1 | v2);
    uart_puts(", BUS_ERR counter ");
    uart_putdec(errs);
    uart_puts(", CPU kept running");
    result(v1 == 0u && v2 == 0u && errs == 4u);
}

static void test_m_extension(void)
{
    uint32_t checks;
    uint32_t c0 = rdcycle(), i0 = rdinstret();
    uint32_t fails = m_selftest(200, &checks);
    uint32_t cycles = rdcycle() - c0, instrs = rdinstret() - i0;
    uart_puts("M-extension self-test: ");
    uart_putdec(checks);
    uart_puts(" results, ");
    uart_putdec(fails);
    uart_puts(" wrong, cycles per instruction x100 = ");
    uart_putdec(cycles / (instrs / 100u));
    result(fails == 0u);
}

static void test_perf_cycles(void)
{
    perf_start();
    uint32_t t0 = rdcycle();
    delay_cycles(10000u);
    uint32_t t1 = rdcycle();
    perf_stop();
    uint32_t hw = PERF_CNT(PERF_CYCLES), sw = t1 - t0;
    uart_puts("CYCLES counter ");
    uart_putdec(hw);
    uart_puts(" vs rdcycle ");
    uart_putdec(sw);
    uart_puts(" (counter window is slightly wider: start/stop writes)");
    result(hw >= sw && hw - sw < 100u);
}

/* rdcycle; sw; rdcycle as one fixed instruction sequence, so two measurements are
 * directly comparable (the compiler cannot move an address load in between). */
static inline uint32_t timed_store(volatile uint32_t *addr, uint32_t v)
{
    uint32_t t0, t1;
    __asm__ volatile ("rdcycle %0\n\tsw %2, 0(%3)\n\trdcycle %1"
                      : "=&r"(t0), "=&r"(t1) : "r"(v), "r"(addr) : "memory");
    return t1 - t0;
}

static void test_tx_fifo(void)
{
    static const char s[] = "0123456789ABCDEFGH";      /* 18 bytes */
    uart_flush();
    perf_start();
    uint32_t base = timed_store(&UART_DATA, (uint8_t)s[0]);   /* FIFO empty: no wait */
    for (int i = 1; i < 17; i++)
        UART_DATA = (uint8_t)s[i];                     /* no polling: fill it */
    uint32_t lvl  = UART_TX_LEVEL();
    uint32_t full = UART_STATUS & UART_TX_FULL;
    uint32_t held = timed_store(&UART_DATA, (uint8_t)s[17]);  /* must wait for room */
    perf_stop();
    uint32_t stall = PERF_CNT(PERF_TX_STALL), apbw = PERF_CNT(PERF_APB_WAIT);

    uart_puts("\nTX FIFO: level ");
    uart_putdec(lvl);
    uart_puts(" after 17 writes, TX_FULL=");
    uart_putdec(full ? 1u : 0u);
    uart_puts(", 18th write held ");
    uart_putdec(held);
    uart_puts(" cycles by bus backpressure");
    result(lvl == UART_FIFO_DEPTH && full && held > 1000u);

    uart_puts("  counters: TX_STALL ");
    uart_putdec(stall);
    uart_puts(" = APB_WAIT ");
    uart_putdec(apbw);
    uart_puts("; held ");
    uart_putdec(held);
    uart_puts(" = TX_STALL + ");
    uart_putdec(base);
    uart_puts(" (same write without a stall)");
    result(stall == apbw && held == stall + base);
}

static void test_rx_fifo(void)
{
    static const char expect[] = "ABCDEFGHIJKLMNOP";
    while (uart_getc_nb() >= 0)                        /* start empty and clean */
        ;
    UART_STATUS = UART_RX_OVERRUN | UART_RX_FRAMEERR;

    perf_start();                                      /* before the cue: the host answers at once */
    uart_puts("RXTEST: send 20 bytes ABCDEFGHIJKLMNOPQRST now\n");
    uart_flush();
    uint32_t t = rdcycle();
    while (UART_RX_LEVEL() < UART_FIFO_DEPTH)
        if (rdcycle() - t > 3u * CLK_HZ) {
            perf_stop();
            uart_puts("RX FIFO test: no input within 3 s -> SKIPPED\n");
            return;
        }
    delay_cycles(12u * 10u * (CLK_HZ / 115200u));      /* let the last 4 bytes arrive */
    perf_stop();

    uint32_t st  = UART_STATUS;
    uint32_t lvl = UART_RX_LEVEL();
    char got[17];
    for (int i = 0; i < 16; i++)
        got[i] = (char)uart_getc_nb();
    got[16] = 0;
    int same = 1;
    for (int i = 0; i < 16; i++)
        same &= (got[i] == expect[i]);

    uart_puts("RX FIFO: level ");
    uart_putdec(lvl);
    uart_puts(", RX_FULL=");
    uart_putdec((st & UART_RX_FULL) ? 1u : 0u);
    uart_puts(", OVERRUN=");
    uart_putdec((st & UART_RX_OVERRUN) ? 1u : 0u);
    uart_puts(", FRAME_ERR=");
    uart_putdec((st & UART_RX_FRAMEERR) ? 1u : 0u);
    uart_puts(", data ");
    uart_puts(got);
    result(lvl == UART_FIFO_DEPTH && (st & UART_RX_FULL) && (st & UART_RX_OVERRUN) &&
           !(st & UART_RX_FRAMEERR) && same);

    uart_puts("  RX_DROP counter ");
    uart_putdec(PERF_CNT(PERF_RX_DROP));
    uart_puts(" (20 sent - 16 kept)");
    result(PERF_CNT(PERF_RX_DROP) == 4u);

    UART_STATUS = UART_RX_OVERRUN;                     /* write 1 to clear */
    st = UART_STATUS;
    uart_puts("OVERRUN cleared by writing 1, RX FIFO empty");
    result(!(st & UART_RX_OVERRUN) && (st & UART_RX_EMPTY));
}

/* ---- profile: the same 128 bytes sent by two drivers -------------------------------- */
#define PROFILE_LEN 128u
static const char line[] = "The quick brown fox jumps over the lazy dog 0123456789.\r\n";

static void send_polling(void)          /* read STATUS until there is room, then write */
{
    for (uint32_t i = 0; i < PROFILE_LEN; i++) {
        while (UART_STATUS & UART_TX_FULL)
            ;
        UART_DATA = (uint8_t)line[i % (sizeof line - 1)];
    }
}

static void send_backpressure(void)     /* just write; the bus holds the CPU when full */
{
    for (uint32_t i = 0; i < PROFILE_LEN; i++)
        UART_DATA = (uint8_t)line[i % (sizeof line - 1)];
}

static void profile_row(const char *name, void (*send)(void), uint32_t *c)
{
    uart_flush();
    perf_start();
    send();                              /* window ends when the last byte is in the FIFO */
    perf_stop();
    uart_flush();
    for (uint32_t i = 0; i < PERF_N; i++)
        c[i] = PERF_CNT(i);
    uart_puts("\n");
    uart_puts(name);
    uart_puts(" cycles ");
    uart_putdec(c[PERF_CYCLES]);
    uart_puts(", APB transfers ");
    uart_putdec(c[PERF_APB_XFER]);
    uart_puts(", TX_STALL ");
    uart_putdec(c[PERF_TX_STALL]);
    uart_puts(", TX_FULL ");
    uart_putdec(c[PERF_TX_FULL]);
    uart_puts(", MEM_WAIT ");
    uart_putdec(c[PERF_MEM_WAIT]);
    uart_puts(" (");
    uart_putdec(c[PERF_MEM_WAIT] * 100u / c[PERF_CYCLES]);
    uart_puts("%)\n");
}

static void profile_drivers(void)
{
    uint32_t a[PERF_N], b[PERF_N];
    uart_puts("Profile: sending 128 bytes with two drivers\n");
    profile_row("polling      :", send_polling, a);
    profile_row("backpressure :", send_backpressure, b);
    /* same line rate, so the same total time (within one byte); polling uses many more
     * bus transfers, backpressure turns that time into stall cycles */
    uint32_t dt = a[PERF_CYCLES] > b[PERF_CYCLES] ? a[PERF_CYCLES] - b[PERF_CYCLES]
                                                  : b[PERF_CYCLES] - a[PERF_CYCLES];
    uart_puts("Both are line-rate bound (same time); polling needs ");
    uart_putdec(a[PERF_APB_XFER] / b[PERF_APB_XFER]);
    uart_puts("x the bus transfers, backpressure stalls instead");
    result(dt < 2u * 10u * (CLK_HZ / 115200u) && a[PERF_TX_STALL] == 0u &&
           b[PERF_TX_STALL] > 0u && a[PERF_APB_XFER] > 2u * b[PERF_APB_XFER]);
}

static void echo_loop(void)
{
    uart_puts("Type a line and press Enter.\necho> ");
    uint32_t n = 0, lines = 0;
    for (;;) {
        char c = uart_getc();
        if (c == '\r' || c == '\n') {
            uart_puts("\n[");
            uart_putdec(n);
            uart_puts(" chars]\necho> ");
            n = 0;
            LED = ++lines;
        } else if ((c == 0x08 || c == 0x7F) && n) {    /* backspace */
            uart_puts("\b \b");
            n--;
        } else if (c >= ' ') {
            uart_putc(c);
            n++;
        }
    }
}

int main(void)
{
    LED = 0x01;
    uart_puts("\n\nRV32IM SoC on Tang Nano 20K: APB bus, UART FIFOs, performance counters\n");
    test_data_restore();
    test_rom_and_bus_errors();
    test_m_extension();
    test_perf_cycles();
    test_tx_fifo();
    test_rx_fifo();
    profile_drivers();
    uart_puts("Tests: ");
    uart_putdec(n_pass);
    uart_puts(" passed, ");
    uart_putdec(n_fail);
    uart_puts(" failed\n");
    LED = n_fail ? 0x2Au : 0x00u;                       /* 101010 = something failed */
    echo_loop();
}
