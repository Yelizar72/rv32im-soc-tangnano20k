#ifndef MTEST_H
#define MTEST_H
#include <stdint.h>

/* Runs edge cases plus n_random random pairs through all 8 M instructions.
 * Returns the number of mismatches; *n_checks = number of instruction results checked. */
uint32_t m_selftest(uint32_t n_random, uint32_t *n_checks);

#endif
