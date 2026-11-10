# Timing constraints for the RV32IM SoC on Tang Nano 20K (nextpnr-himbaechel --sdc).
#
# One clock: the on-board 27 MHz crystal on pin 4. Period = 1 / 27 MHz = 37.037 ns.
#
# The constraint is placed on the clock net *after* the input buffer, u_soc.clk, which is
# the net nextpnr's timing analysis uses. Constraining the port [get_ports {clk}] is
# accepted but does not reach that net here, and the analysis silently falls back to its
# 12 MHz default (checked: a 200 MHz port constraint still "passed"). If the hierarchy
# changes, check the "constraining clock net" line in build/soc-pnr.log.
#
# Verified as a gate: with -period 5.0 (200 MHz) nextpnr stops with
#   ERROR: Max frequency for clock 'u_soc.clk': ... (FAIL at 200.00 MHz)
create_clock -name clk -period 37.037 [get_nets {u_soc.clk}]

# Asynchronous inputs (uart_rx, btn_s1) get no input delays on purpose: each goes through
# a two-flip-flop synchronizer in the RTL (uart_rx.v, board_top.v). nextpnr parses
# set_false_path but does not apply it yet, so no false paths are declared.
#
# For Gowin's own tool flow the equivalent line would target the port:
#   create_clock -name clk -period 37.037 -waveform {0 18.518} [get_ports {clk}]
