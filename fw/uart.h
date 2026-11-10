#ifndef UART_H
#define UART_H
#include <stdint.h>

void uart_putc(char c);                 /* waits while the TX FIFO is full */
void uart_puts(const char *s);          /* "\n" is sent as "\r\n" */
void uart_putdec(uint32_t v);
void uart_puthex(uint32_t v);           /* 0x followed by 8 hex digits */
void uart_flush(void);                  /* wait until every byte has left the pin */

int  uart_getc_nb(void);                /* next received byte, or -1 if none */
char uart_getc(void);                   /* waits for a byte */

#endif
