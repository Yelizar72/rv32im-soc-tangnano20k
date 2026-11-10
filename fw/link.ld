/* Linker script.
 *   ROM 0x0000-0x1FFF: .text, .rodata, and the load copy of .data (never written)
 *   RAM 0x2000-0x3FFF: .data (copied from ROM by start.S on every reset), .bss, stack
 */
OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
    ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 8K
    RAM (rw)  : ORIGIN = 0x00002000, LENGTH = 8K
}

SECTIONS
{
    .text : {
        KEEP(*(.text.start))          /* start.S must be at address 0 */
        *(.text .text.*)
    } > ROM

    .rodata : ALIGN(4) {
        *(.rodata .rodata.*)
        *(.srodata .srodata.*)
    } > ROM

    .data : ALIGN(4) {
        _data_start = .;
        *(.data .data.*)
        __global_pointer$ = . + 0x800;
        *(.sdata .sdata.*)
        . = ALIGN(4);
        _data_end = .;
    } > RAM AT > ROM                  /* runs in RAM, initial values stored in ROM */
    _data_load = LOADADDR(.data);

    .bss (NOLOAD) : ALIGN(4) {
        _bss_start = .;
        *(.sbss .sbss.*)
        *(.bss .bss.*)
        *(COMMON)
        . = ALIGN(4);
        _bss_end = .;
    } > RAM

    _stack_top  = ORIGIN(RAM) + LENGTH(RAM);
    _stack_size = _stack_top - _bss_end;
    ASSERT(_stack_size >= 2048, "RAM too full: less than 2 KB left for the stack")
    ASSERT(_data_load + (_data_end - _data_start) <= ORIGIN(ROM) + LENGTH(ROM), "ROM full")

    /DISCARD/ : { *(.comment) *(.riscv.attributes) *(.note*) *(.eh_frame*) }
}
