/* Register map of the SoC (must match rtl/soc_top.v, rtl/apb_uart.v, rtl/apb_gpio.v). */
#ifndef SOC_H
#define SOC_H
#include <stdint.h>

#define REG32(addr) (*(volatile uint32_t *)(addr))

/* ---- APB slave 0: UART ---------------------------------------------------------- */
#define UART_BASE        0x10000000u
#define UART_DATA        REG32(UART_BASE + 0x00)  /* W: push TX byte (stalls if full); R: pop RX byte */
#define UART_STATUS      REG32(UART_BASE + 0x04)  /* R: flags below; W: 1 clears sticky flags  */
#define UART_LEVELS      REG32(UART_BASE + 0x08)  /* R: [4:0] TX level, [12:8] RX level        */

#define UART_TX_FULL     (1u << 0)
#define UART_TX_IDLE     (1u << 1)                /* TX FIFO empty and line idle */
#define UART_RX_EMPTY    (1u << 2)
#define UART_RX_FULL     (1u << 3)
#define UART_RX_OVERRUN  (1u << 4)                /* sticky: a byte arrived while RX was full */
#define UART_RX_FRAMEERR (1u << 5)                /* sticky: bad stop bit */
#define UART_FIFO_DEPTH  16u

#define UART_TX_LEVEL()  (UART_LEVELS & 0x1Fu)
#define UART_RX_LEVEL()  ((UART_LEVELS >> 8) & 0x1Fu)

/* ---- APB slave 1: GPIO ------------------------------------------------------------ */
#define GPIO_BASE        0x10001000u
#define LED              REG32(GPIO_BASE + 0x00)  /* RW: bits 5:0, 1 = on */

/* ---- APB slave 2: performance counters -------------------------------------------- */
#define PERF_BASE        0x10002000u
#define PERF_CTRL        REG32(PERF_BASE + 0x00)  /* bit0 ENABLE, write bit1 = clear all */
#define PERF_ENABLE      (1u << 0)
#define PERF_CLEAR       (1u << 1)
#define PERF_CNT(i)      REG32(PERF_BASE + 0x04u + 4u * (i))
enum perf_counter {
    PERF_CYCLES   = 0,   /* clock cycles                                         */
    PERF_MEM_WAIT = 1,   /* cycles the CPU waits for memory or a peripheral      */
    PERF_APB_WAIT = 2,   /* wait states inserted by APB slaves                   */
    PERF_APB_XFER = 3,   /* APB transfers completed                              */
    PERF_BUS_ERR  = 4,   /* accesses ending in PSLVERR or at an unmapped address */
    PERF_TX_STALL = 5,   /* cycles a UART write was held (TX FIFO full)          */
    PERF_TX_FULL  = 6,   /* cycles the TX FIFO was full                          */
    PERF_RX_DROP  = 7,   /* received bytes dropped (RX FIFO full)                */
    PERF_N        = 8
};
static inline void perf_start(void) { PERF_CTRL = PERF_CLEAR | PERF_ENABLE; }
static inline void perf_stop(void)  { PERF_CTRL = 0; }

#ifndef CLK_HZ
#define CLK_HZ 27000000u
#endif

/* RISC-V cycle and retired-instruction counters (Zicntr, implemented by PicoRV32). */
static inline uint32_t rdcycle(void)   { uint32_t v; __asm__ volatile ("rdcycle %0"   : "=r"(v)); return v; }
static inline uint32_t rdinstret(void) { uint32_t v; __asm__ volatile ("rdinstret %0" : "=r"(v)); return v; }

static inline void delay_cycles(uint32_t n) { uint32_t t = rdcycle(); while (rdcycle() - t < n) ; }

#endif
