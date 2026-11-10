# Development log

Built in three stages on 2026-11-10; each stage ended with the design running on the board.
The numbers below are from simulation (Verilator) and from the board, as labelled.

## Day 1 results (simulation and build, 2026-11-10; 8 KB single RAM design)

| Item | Value |
|---|---|
| Firmware size | 2,390 bytes of 8,192 |
| M-extension self-test | 2,752 results (8 instructions, edge cases incl. divide by 0 and INT_MIN / -1, plus 200 random pairs): 0 wrong |
| Self-test sensitivity | a deliberately wrong reference value is caught and reported |
| CPU cycles per instruction | 4.65 on the self-test |
| Lint (Verilator -Wall) | clean, one documented waiver (power-on reset registers) |
| Resources | 2,978 LUT4 (14%), 1,179 DFF, 4 BSRAM, 1 MULT36X36 DSP |
| Fmax (nextpnr estimate) | 119 MHz; the board runs at 27 MHz |

The Fmax is nextpnr's timing estimate from the Apicula timing data, not a measurement.

## Day 1 on the board (2026-11-10)

| Item | Board | Verilator |
|---|---|---|
| Banner and self-test over UART at 115200 baud | printed, 0 wrong of 2,752 | same |
| Self-test, run after S1 reset | 3,616,785 cycles, 776,362 instructions | 3,616,785 cycles, 776,362 instructions (`Vsoc_top 40000000 2`) |

Simulation and hardware agree to the clock cycle. The multiplier mapped to the DSP block
passes on the chip.

Day 1 issue, fixed in Day 2: S1 reset the CPU but did not reload RAM, so initialized globals
(`.data`) kept values from the previous run.

## Day 2 results (simulation and build, 2026-11-10)

| Check (firmware, from software) | Result |
|---|---|
| `.data` restored at boot | 0xc0ffee00 on both runs |
| ROM write ignored | PASS |
| Unmapped APB slave: reads 0, CPU keeps running | PASS |
| M-extension self-test | 2,752 results, 0 wrong |
| TX FIFO: 17 fast writes -> level 16, TX_FULL; 18th write held by PREADY | held 1,814 cycles |
| RX FIFO: 20 bytes sent, nobody reading -> 16 kept, RX_FULL, OVERRUN; write-1-to-clear | PASS |
| Echo prompt | "Hello, RV32!" echoed, 12 chars |
| Two runs with reset between | output identical |

Fault injection, each caught by the tests: no `.data` copy (value 0x0/0x1, runs differ),
no TX backpressure (18th write held 17 cycles, byte lost), overrun flag disabled (OVERRUN=0).

| Build | |
|---|---|
| Lint (Verilator -Wall) | clean, one documented waiver (power-on reset registers) |
| Resources | 3,564 LUT4 (17%), 1,313 DFF, 8 BSRAM, 1 MULT36X36 |
| Fmax (nextpnr estimate) | 110 MHz; board clock 27 MHz |
| Firmware | 3,926 bytes of 8 KB ROM |

## Day 2 on the board (2026-11-10, `make boardtest`)

| Item | Board |
|---|---|
| All 7 checks, run after programming | PASS, identical to simulation (incl. 18th write held 1,814 cycles) |
| Run after S1 reset | PASS, output identical to run 1: `.data` restored |
| Fmax reported by nextpnr for the bitstream that ran | 115.4 MHz (placement varies between builds: 110 MHz in another build) |

The `Cell O_sdram_* not found` lines from nextpnr are informational: the GW2AR has an embedded
SDRAM die with fixed pins, and this design does not use it.

## Day 3: performance counters and timing constraints (simulation and build, 2026-11-10)

Eight 32-bit counters on APB slave 2, each fed by one event signal:

| Counter | Event (cycle it is high) | Source |
|---|---|---|
| CYCLES | every clock | constant 1 |
| MEM_WAIT | CPU access in flight, not ready yet | CPU bus: `mem_valid && !mem_ready` |
| APB_WAIT | APB slave holds PREADY low | APB bridge, ACCESS phase |
| APB_XFER | APB transfer completed | APB bridge |
| BUS_ERR | access ended in PSLVERR, or at an unmapped CPU address | APB bridge, address decoder |
| TX_STALL | UART DATA write held, TX FIFO full | UART |
| TX_FULL | TX FIFO full (backpressure asserted) | UART |
| RX_DROP | received byte dropped, RX FIFO full | UART |

| Check (firmware) | Result |
|---|---|
| CYCLES vs `rdcycle` over a 10,000-cycle delay | 10,035 vs 10,018: wider by the start/stop writes |
| TX_STALL vs measured hold of the 18th write | held 1,797 = TX_STALL 1,784 + 13, where 13 is the same write without a stall (identical instruction sequence) |
| TX_STALL vs APB_WAIT | equal (1,784): the UART was the only slave inserting waits |
| BUS_ERR for 2 unmapped APB + 2 unmapped CPU-bus accesses | 4 |
| RX_DROP for 20 bytes into a 16-byte FIFO | 4 |
| All earlier checks | pass; 11 of 11 |
| Two runs with reset between | output identical |

Profile, 128 bytes sent by two drivers (window ends when the last byte is in the FIFO):

| Driver | Cycles | APB transfers | TX_STALL | MEM_WAIT |
|---|---|---|---|---|
| Polling (read STATUS, then write) | 260,172 | 12,700 | 0 | 34% |
| Backpressure (write, bus holds CPU) | 260,079 | 129 | 250,947 | 97% |

Both are bound by the 115,200-baud line and take the same time. Polling spends it on 98x more bus
transfers; backpressure turns it into CPU stall cycles. Neither frees the CPU: that needs interrupts.

Fault injection, each caught: BUS_ERR not counting CPU-bus errors (2 instead of 4), counters not
clearing (CYCLES 329,083), TX_STALL off by one cycle (1,783 vs APB_WAIT 1,784).

**Timing constraints** (`constraints/soc.sdc`): `create_clock` at 37.037 ns (27 MHz) on the clock
net nextpnr analyses, `u_soc.clk`. A constraint on the port `clk` was accepted but did not reach that
net (analysis fell back to 12 MHz; a 200 MHz port constraint still passed), so the net is named
directly. Verified as a gate: `-period 5.0` stops the build with `ERROR: ... FAIL at 200.00 MHz`.
nextpnr parses `set_false_path` but does not apply it; the asynchronous inputs are handled by
two-flop synchronizers in the RTL instead.

| Build | |
|---|---|
| Lint (Verilator -Wall) | clean, one documented waiver |
| Resources | 3,947 LUT4 (19%), 1,590 DFF (10%), 8 BSRAM, 1 MULT36X36 |
| Timing | constraint met at 27 MHz; Fmax 115.2 MHz (nextpnr estimate) |
| Firmware | 5,530 bytes of 8 KB ROM |

## Day 3 on the board (2026-11-10, `make boardtest`)

| Item | Board |
|---|---|
| All 11 checks, after programming and after S1 reset | PASS; both runs identical |
| Counter values (TX_STALL 1,784, BUS_ERR 4, RX_DROP 4, profile rows) | identical to Verilator, cycle for cycle |
| Timing, bitstream that ran | SDC constraint 27 MHz met; Fmax 115.9 MHz (nextpnr estimate) |
| Critical path | BSRAM read data -> CPU load-data alignment logic -> register write: 8.62 ns (5.65 logic, 2.98 routing) |

Yosys prints `Replacing memory \count with list of registers` for apb_perf.v: expected, the
counter array is meant to be flip-flops (all eight update in the same cycle).
