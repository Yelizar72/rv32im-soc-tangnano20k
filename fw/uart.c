/* Polling UART driver for the APB UART (16-byte TX and RX FIFOs). */
#include "soc.h"
#include "uart.h"

void uart_putc(char c)
{
    while (UART_STATUS & UART_TX_FULL)
        ;
    UART_DATA = (uint8_t)c;
}

void uart_puts(const char *s)
{
    while (*s) {
        if (*s == '\n')
            uart_putc('\r');
        uart_putc(*s++);
    }
}

void uart_putdec(uint32_t v)
{
    char buf[11];
    int i = 0;
    do {
        buf[i++] = (char)('0' + v % 10u);
        v /= 10u;
    } while (v);
    while (i)
        uart_putc(buf[--i]);
}

void uart_puthex(uint32_t v)
{
    uart_puts("0x");
    for (int s = 28; s >= 0; s -= 4)
        uart_putc("0123456789abcdef"[(v >> s) & 0xFu]);
}

void uart_flush(void)
{
    while (!(UART_STATUS & UART_TX_IDLE))
        ;
}

int uart_getc_nb(void)
{
    if (UART_STATUS & UART_RX_EMPTY)
        return -1;
    return (int)(UART_DATA & 0xFFu);
}

char uart_getc(void)
{
    int c;
    while ((c = uart_getc_nb()) < 0)
        ;
    return (char)c;
}
