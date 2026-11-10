/* M-extension self-test.
 * Each of the 8 instructions is issued explicitly (inline asm, so the compiler cannot
 * optimise it away) and compared with a software reference that uses only shifts, adds
 * and compares. Includes the RISC-V special cases: division by zero and INT_MIN / -1.
 */
#include <stdint.h>
#include "uart.h"
#include "mtest.h"

#define RV_OP(op, a, b) ({ uint32_t r_; \
    __asm__ volatile (op " %0, %1, %2" : "=r"(r_) : "r"(a), "r"(b)); r_; })

/* ---- software references (no M instructions) -------------------------------------- */
static uint64_t sw_mulu64(uint32_t a, uint32_t b)
{
    uint64_t acc = 0, x = a;
    for (int i = 0; i < 32; i++) {
        if (b & 1u) acc += x;
        x <<= 1;
        b >>= 1;
    }
    return acc;
}

static uint64_t neg64(uint64_t v) { return ~v + 1u; }

static uint32_t sw_mulh(int32_t a, int32_t b)          /* signed x signed, high word */
{
    uint32_t ua = a < 0 ? 0u - (uint32_t)a : (uint32_t)a;
    uint32_t ub = b < 0 ? 0u - (uint32_t)b : (uint32_t)b;
    uint64_t p = sw_mulu64(ua, ub);
    if ((a < 0) != (b < 0)) p = neg64(p);
    return (uint32_t)(p >> 32);
}

static uint32_t sw_mulhsu(int32_t a, uint32_t b)       /* signed x unsigned, high word */
{
    uint32_t ua = a < 0 ? 0u - (uint32_t)a : (uint32_t)a;
    uint64_t p = sw_mulu64(ua, b);
    if (a < 0) p = neg64(p);
    return (uint32_t)(p >> 32);
}

static void sw_divu(uint32_t a, uint32_t b, uint32_t *q, uint32_t *r)
{
    if (b == 0) { *q = 0xFFFFFFFFu; *r = a; return; }   /* RISC-V: no trap */
    uint32_t quo = 0, rem = 0;
    for (int i = 31; i >= 0; i--) {                     /* restoring division */
        rem = (rem << 1) | ((a >> i) & 1u);
        if (rem >= b) { rem -= b; quo |= 1u << i; }
    }
    *q = quo; *r = rem;
}

static void sw_div(int32_t a, int32_t b, uint32_t *q, uint32_t *r)
{
    if (b == 0) { *q = 0xFFFFFFFFu; *r = (uint32_t)a; return; }
    if (a == INT32_MIN && b == -1) { *q = (uint32_t)INT32_MIN; *r = 0; return; }
    uint32_t ua = a < 0 ? 0u - (uint32_t)a : (uint32_t)a;
    uint32_t ub = b < 0 ? 0u - (uint32_t)b : (uint32_t)b;
    uint32_t uq, ur;
    sw_divu(ua, ub, &uq, &ur);
    *q = ((a < 0) != (b < 0)) ? 0u - uq : uq;           /* quotient rounds toward zero */
    *r = (a < 0) ? 0u - ur : ur;                        /* remainder takes a's sign    */
}

/* ---- test ----------------------------------------------------------------------------- */
static uint32_t lcg_state = 12345u;
static uint32_t lcg(void)
{
    lcg_state = (lcg_state << 2) + lcg_state + 0x3C6EF35Fu;   /* x*5 + c, no MUL needed */
    lcg_state ^= lcg_state >> 13;
    return lcg_state;
}

static uint32_t fails;

static void check(const char *op, uint32_t a, uint32_t b, uint32_t got, uint32_t want)
{
    if (got == want) return;
    if (fails++ < 5) {          /* report the first few */
        uart_puts("  FAIL "); uart_puts(op);
        uart_puts(" a="); uart_puthex(a); uart_puts(" b="); uart_puthex(b);
        uart_puts(" got="); uart_puthex(got); uart_puts(" want="); uart_puthex(want);
        uart_puts("\n");
    }
}

static void test_pair(uint32_t a, uint32_t b)
{
    uint64_t p = sw_mulu64(a, b);
    uint32_t q, r, sq, sr;
    sw_divu(a, b, &q, &r);
    sw_div((int32_t)a, (int32_t)b, &sq, &sr);

    check("mul",    a, b, RV_OP("mul",    a, b), (uint32_t)p);
    check("mulhu",  a, b, RV_OP("mulhu",  a, b), (uint32_t)(p >> 32));
    check("mulh",   a, b, RV_OP("mulh",   a, b), sw_mulh((int32_t)a, (int32_t)b));
    check("mulhsu", a, b, RV_OP("mulhsu", a, b), sw_mulhsu((int32_t)a, b));
    check("divu",   a, b, RV_OP("divu",   a, b), q);
    check("remu",   a, b, RV_OP("remu",   a, b), r);
    check("div",    a, b, RV_OP("div",    a, b), sq);
    check("rem",    a, b, RV_OP("rem",    a, b), sr);
}

uint32_t m_selftest(uint32_t n_random, uint32_t *n_checks)
{
    static const uint32_t edge[] = {
        0u, 1u, 2u, 3u, 7u, 0x7FFFFFFFu, 0x80000000u, 0x80000001u,
        0xFFFFFFFEu, 0xFFFFFFFFu, 0x0000FFFFu, 0x00010000u,
    };
    const uint32_t ne = sizeof edge / sizeof edge[0];
    fails = 0;
    for (uint32_t i = 0; i < ne; i++)          /* every pair of edge values, incl. b = 0 */
        for (uint32_t j = 0; j < ne; j++)
            test_pair(edge[i], edge[j]);
    for (uint32_t i = 0; i < n_random; i++)
        test_pair(lcg(), lcg());
    *n_checks = 8u * (ne * ne + n_random);
    return fails;
}
