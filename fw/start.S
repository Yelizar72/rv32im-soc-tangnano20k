/* Reset entry point. The CPU starts executing here (address 0) after every reset.
 * 1. set up the global pointer and the stack pointer
 * 2. copy .data initial values from ROM to RAM  (so S1 / reset always starts clean)
 * 3. zero .bss (C expects uninitialized globals to be 0)
 * 4. call main(); if it ever returns, park in a loop
 */
    .section .text.start
    .global _start
_start:
    .option push
    .option norelax
    la   gp, __global_pointer$
    .option pop
    la   sp, _stack_top

    la   a0, _data_load          /* source: ROM */
    la   a1, _data_start         /* destination: RAM */
    la   a2, _data_end
1:  bgeu a1, a2, 2f
    lw   t0, 0(a0)
    sw   t0, 0(a1)
    addi a0, a0, 4
    addi a1, a1, 4
    j    1b

2:  la   a0, _bss_start
    la   a1, _bss_end
3:  bgeu a0, a1, 4f
    sw   zero, 0(a0)
    addi a0, a0, 4
    j    3b

4:  call main
5:  j    5b
