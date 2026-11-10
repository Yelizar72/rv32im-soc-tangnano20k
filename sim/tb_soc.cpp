// Verilator testbench for soc_top. It plays the PC on the other end of the UART:
//   - decodes the bits on uart_tx into text and prints it
//   - when the firmware prints a cue, sends bytes into uart_rx, bit by bit
//   - after the last cue, resets the CPU (like pressing S1) and runs again;
//     RAM is NOT reloaded, exactly as on the board
//
//   ./Vsoc_top [max_cycles] [runs]          (defaults: 60000000, 2)
// Exit code: 0 all runs completed, no FAIL, runs identical; 1 CPU trap; 2 timeout;
//            3 firmware reported FAIL or runs differ.
#include <cstdio>
#include <cstdlib>
#include <deque>
#include <string>
#include <vector>
#include "Vsoc_top.h"
#include "verilated.h"

#ifndef CLKS_PER_BIT
#define CLKS_PER_BIT 234            // FPGA: 27 MHz / 115200
#endif
static const int PC_CLKS_PER_BIT = CLKS_PER_BIT + 1;   // the PC is a little slower, as on the board

struct Step { const char *expect; const char *send; };
static const Step script[] = {
    { "RXTEST",     "ABCDEFGHIJKLMNOPQRST" },   // 20 bytes into a 16-byte FIFO
    { "echo> ",     "Hello, RV32!\r"       },
    { "[12 chars]", nullptr                },   // end of the run
};
static const int n_steps = sizeof script / sizeof script[0];

int main(int argc, char **argv)
{
    Verilated::commandArgs(argc, argv);
    const uint64_t max_cycles = argc > 1 ? strtoull(argv[1], nullptr, 0) : 60000000ull;
    const int runs = argc > 2 ? atoi(argv[2]) : 2;

    Vsoc_top *top = new Vsoc_top;
    top->clk = 0;
    top->resetn = 0;
    top->uart_rx = 1;

    std::vector<std::string> outputs;
    std::string out;
    int run = 1, step = 0, rc = 2;
    size_t matched_at = 0;
    uint64_t reset_until = 10, cyc;

    // UART decoder (FPGA -> PC)
    int rstate = 0, rbit = 0, rcnt = 0, prev_tx = 1;
    unsigned ch = 0;
    // UART driver (PC -> FPGA)
    std::deque<unsigned char> txq;
    int tbit = -1, tcnt = 0;          // tbit -1 = idle, 0 = start, 1..8 data, 9 stop
    unsigned char tbyte = 0;

    for (cyc = 0; cyc < max_cycles; cyc++) {
        top->resetn = cyc >= reset_until;
        top->clk = 1; top->eval();
        top->clk = 0; top->eval();

        // ---- decode what the FPGA sends ----
        const int tx = top->uart_tx;
        switch (rstate) {
        case 0: if (prev_tx && !tx) { rstate = 1; rcnt = 0; } break;
        case 1: if (++rcnt == CLKS_PER_BIT / 2) { rstate = tx ? 0 : 2; rcnt = 0; rbit = 0; ch = 0; } break;
        case 2: if (++rcnt == CLKS_PER_BIT) {
                    rcnt = 0; ch |= (unsigned)tx << rbit;
                    if (++rbit == 8) rstate = 3;
                } break;
        case 3: if (++rcnt == CLKS_PER_BIT) {
                    if (!tx) std::printf("[framing error]");
                    out += (char)ch; std::putchar((int)ch); std::fflush(stdout);
                    rstate = 0;
                } break;
        }
        prev_tx = tx;

        // ---- follow the script ----
        if (step < n_steps) {
            size_t p = out.find(script[step].expect, matched_at);
            if (p != std::string::npos) {
                matched_at = p + 1;
                if (script[step].send)
                    for (const char *s = script[step].send; *s; s++) txq.push_back((unsigned char)*s);
                step++;
            }
        }

        // ---- drive bytes into the FPGA ----
        if (tbit < 0 && !txq.empty()) { tbyte = txq.front(); txq.pop_front(); tbit = 0; tcnt = 0; }
        if (tbit >= 0) {
            top->uart_rx = tbit == 0 ? 0 : tbit <= 8 ? (tbyte >> (tbit - 1)) & 1 : 1;
            if (++tcnt == PC_CLKS_PER_BIT) { tcnt = 0; if (++tbit == 10) tbit = -1; }
        } else
            top->uart_rx = 1;

        if (top->trap) { rc = 1; break; }

        // ---- end of a run: the last cue plus the new prompt has arrived ----
        if (step == n_steps && out.size() >= matched_at + 16) {
            outputs.push_back(out);
            std::printf("\n[tb] run %d complete at cycle %llu\n", run, (unsigned long long)cyc);
            if (run == runs) { rc = 0; break; }
            std::printf("[tb] --- pressing reset (S1) ---\n");
            run++; step = 0; out.clear(); matched_at = 0;
            reset_until = cyc + 300;
        }
    }

    if (rc == 0) {
        for (const auto &o : outputs)
            if (o.find("FAIL") != std::string::npos) rc = 3;
        if (outputs.size() > 1) {
            bool same = true;
            for (const auto &o : outputs) same &= (o == outputs[0]);
            std::printf("[tb] %zu runs, output identical across resets: %s\n",
                        outputs.size(), same ? "yes" : "NO");
            if (!same) rc = 3;
        }
    }
    std::printf("[tb] result: %s after %llu cycles (%.1f ms at 27 MHz)\n",
                rc == 0 ? "PASS" : rc == 1 ? "CPU TRAP" : rc == 2 ? "TIMEOUT" : "FAIL",
                (unsigned long long)cyc, cyc / 27e3);
    if (rc == 2) std::printf("[tb] stuck waiting for \"%s\"\n", step < n_steps ? script[step].expect : "?");
    top->final();
    delete top;
    return rc;
}
