# RV32IM SoC on Tang Nano 20K.  Run `fpgaenv` first (puts yosys, nextpnr, verilator on PATH).
#
#   make fw         compile firmware  -> build/firmware.hex
#   make sim        Verilator simulation: the testbench plays the PC, runs twice (S1 reset)
#   make lint       Verilator lint of our RTL (-Wall), must be warning-free
#   make bit        bitstream          -> build/soc.fs  (+ Fmax in build/soc-pnr.log)
#   make prog       load into the FPGA (lost at power-off)
#   make flash      write to the on-board flash
#   make boardtest  program the board and run the same checks as the simulation, twice
#   make term       watch the board's UART output (Ctrl+] to quit); press S1 to rerun
#   make clean

# ---- toolchain ------------------------------------------------------------------------
CROSS   ?= riscv-none-elf-
CC       = $(CROSS)gcc
OBJCOPY  = $(CROSS)objcopy
OBJDUMP  = $(CROSS)objdump
SIZE     = $(CROSS)size

CLK_HZ    = 27000000
ROM_WORDS = 2048
BUILD     = build

CFLAGS  = -march=rv32im -mabi=ilp32 -Os -g -Wall -Wextra -ffreestanding -fno-builtin \
          -nostdlib -ffunction-sections -fdata-sections -DCLK_HZ=$(CLK_HZ)u \
          --param=min-pagesize=0   # fixed low addresses (ROM test) are intentional
LDFLAGS = -T fw/link.ld -Wl,--no-warn-rwx-segments -Wl,--gc-sections -Wl,-Map=$(BUILD)/firmware.map -lgcc

FW_SRC = fw/start.S fw/main.c fw/uart.c fw/mtest.c
RTL    = rtl/third_party/picorv32.v rtl/uart_tx.v rtl/uart_rx.v rtl/fifo.v rtl/ram.v \
         rtl/apb_bridge.v rtl/apb_interconnect.v rtl/apb_uart.v rtl/apb_gpio.v rtl/apb_perf.v \
         rtl/soc_top.v
BOARD_RTL = $(RTL) rtl/board_top.v

DEVICE = GW2AR-LV18QN88C8/I7
FAMILY = GW2A-18C
CST    = constraints/tangnano20k.cst
SDC    = constraints/soc.sdc

.PHONY: all fw sim lint bit prog flash term boardtest clean
.SECONDARY:
all: fw sim bit

# ---- firmware -------------------------------------------------------------------------
fw: $(BUILD)/firmware.hex

$(BUILD)/firmware.elf: $(FW_SRC) fw/link.ld fw/soc.h fw/uart.h fw/mtest.h | $(BUILD)
	$(CC) $(CFLAGS) $(FW_SRC) $(LDFLAGS) -o $@
	$(SIZE) $@
	$(OBJDUMP) -d $@ > $(BUILD)/firmware.lst

$(BUILD)/firmware.bin: $(BUILD)/firmware.elf
	$(OBJCOPY) -O binary $< $@

$(BUILD)/firmware.hex: $(BUILD)/firmware.bin tools/bin2hex.py
	python3 tools/bin2hex.py $< $@ $(ROM_WORDS)

# ---- simulation -------------------------------------------------------------------------
VFLAGS = --cc --exe --build -O2 -j 0 --top-module soc_top -Mdir $(BUILD)/obj_dir \
         -Wno-fatal -Wno-lint -Wno-style -Wno-TIMESCALEMOD \
         -GFIRMWARE='"$(BUILD)/firmware.hex"' -GCLK_HZ=$(CLK_HZ)

$(BUILD)/obj_dir/Vsoc_top: $(RTL) sim/tb_soc.cpp $(BUILD)/firmware.hex
	verilator $(VFLAGS) $(RTL) sim/tb_soc.cpp > $(BUILD)/verilator.log 2>&1 || (cat $(BUILD)/verilator.log; false)

sim: $(BUILD)/obj_dir/Vsoc_top
	$(BUILD)/obj_dir/Vsoc_top

# ---- lint: all warnings on, third-party core excluded via sim/lint.vlt ----------------
lint: $(BUILD)/firmware.hex
	verilator --lint-only -Wall --top-module board_top sim/lint.vlt $(BOARD_RTL) \
	    -GFIRMWARE='"$(BUILD)/firmware.hex"' 2>&1 | tee $(BUILD)/lint.log
	@! grep -q "%Warning\|%Error" $(BUILD)/lint.log && echo "lint: clean"

# ---- FPGA -------------------------------------------------------------------------------
bit: $(BUILD)/soc.fs

$(BUILD)/soc-synth.json: $(BOARD_RTL) $(BUILD)/firmware.hex
	yosys -q -l $(BUILD)/soc-yosys.log \
	    -p "read_verilog $(BOARD_RTL); chparam -set FIRMWARE \"$(BUILD)/firmware.hex\" board_top; synth_gowin -top board_top -family gw2a -json $@"

# timing is checked against constraints/soc.sdc: a violation stops the build with ERROR
$(BUILD)/soc-pnr.json: $(BUILD)/soc-synth.json $(CST) $(SDC)
	nextpnr-himbaechel --json $< --write $@ --device $(DEVICE) \
	    --vopt family=$(FAMILY) --vopt cst=$(CST) --sdc $(SDC) -l $(BUILD)/soc-pnr.log
	@grep "Max frequency" $(BUILD)/soc-pnr.log | tail -1

$(BUILD)/soc.fs: $(BUILD)/soc-pnr.json
	gowin_pack -d $(FAMILY) -o $@ $<

prog: $(BUILD)/soc.fs
	openFPGALoader -b tangnano20k $<

flash: $(BUILD)/soc.fs
	openFPGALoader -b tangnano20k -f $<

# the BL616 debugger shows two serial ports; the UART is the second (highest-numbered)
PORT ?= $(lastword $(sort $(wildcard /dev/cu.usbserial-*) $(wildcard /dev/ttyUSB*)))
boardtest: $(BUILD)/soc.fs
	python3 host/board_test.py --bit $<

term:
	@echo "Opening $(PORT) at 115200 baud. Press S1 on the board to rerun the firmware, Ctrl+] to quit."
	python3 -m serial.tools.miniterm --raw $(PORT) 115200

$(BUILD):
	mkdir -p $@

clean:
	rm -rf $(BUILD)
