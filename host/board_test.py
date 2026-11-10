"""Run the Day 2 checks on the real board: the same script the Verilator testbench plays.

    python3 host/board_test.py              # programs the board, then runs the script
    python3 host/board_test.py --no-prog    # board already programmed: press S1 when asked
    python3 host/board_test.py --port /dev/cu.usbserial-XXXX

Run 1 starts by loading the bitstream (or S1). Run 2 asks you to press S1 and checks
that the output is identical, which proves .data is restored on every reset.
Never sends more than 32 bytes at once (the board's USB-serial chip drops bigger bursts).
"""
import argparse
import glob
import subprocess
import sys
import time

import serial

SCRIPT = [                       # (wait for this text, then send this)
    ("RXTEST", b"ABCDEFGHIJKLMNOPQRST"),
    ("echo> ", b"Hello, RV32!\r"),
    ("[12 chars]", None),
]
STEP_TIMEOUT = 20.0              # seconds


def find_port():
    ports = sorted(glob.glob("/dev/cu.usbserial-*")) + sorted(glob.glob("/dev/ttyUSB*"))
    if not ports:
        sys.exit("No board serial port found. Is the Tang Nano 20K plugged in?")
    return ports[-1]             # the BL616 UART is the second (highest-numbered) port


def one_run(s, start_action, carry=""):
    """Returns (text of this run, completed?, text that already belongs to the next run)."""
    out = carry
    pos = 0
    if carry:
        sys.stdout.write(carry)
    start_action()
    for expect, send in SCRIPT:
        t0 = time.time()
        while out.find(expect, pos) < 0:
            chunk = s.read(256).decode("ascii", "replace")
            if chunk:
                sys.stdout.write(chunk)
                sys.stdout.flush()
                out += chunk
            if time.time() - t0 > STEP_TIMEOUT:
                print(f"\n[host] TIMEOUT waiting for {expect!r}")
                return out, False, ""
        pos = out.find(expect, pos) + 1
        if send:
            assert len(send) <= 32
            s.write(send)
    t0 = time.time()                         # read up to the new "echo> " prompt, no further
    while out.find("echo> ", pos) < 0 and time.time() - t0 < 2.0:
        chunk = s.read(256).decode("ascii", "replace")
        sys.stdout.write(chunk)
        out += chunk
    end = out.find("echo> ", pos)
    if end < 0:
        return out, True, ""
    end += len("echo> ")
    return out[:end], True, out[end:]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port")
    ap.add_argument("--no-prog", action="store_true")
    ap.add_argument("--bit", default="build/soc.fs")
    a = ap.parse_args()
    port = a.port or find_port()
    print(f"[host] serial port {port}")

    with serial.Serial(port, 115200, timeout=0.1) as s:
        def program():
            if a.no_prog:
                print("[host] press S1 on the board now")
            else:
                print(f"[host] loading {a.bit} ...")
                r = subprocess.run(["openFPGALoader", "-b", "tangnano20k", a.bit],
                                   capture_output=True, text=True)
                if r.returncode != 0:
                    print(r.stdout[-500:], r.stderr[-500:])
                    sys.exit("[host] programming failed (try: make prog, then --no-prog)")

        s.reset_input_buffer()
        out1, ok1, rest = one_run(s, program)
        out2, ok2, _ = one_run(s, lambda: print("\n[host] run 2: press S1 on the board now"), rest)

    def clean(o):                            # compare from the banner on
        i = o.find("RV32IM SoC")
        return o[i:] if i >= 0 else o

    same = clean(out1) == clean(out2)
    no_fail = "FAIL" not in out1 + out2
    print("\n[host] run 1 completed:", ok1, "| run 2 completed:", ok2)
    print("[host] no FAIL reported:", no_fail)
    print("[host] run 2 output identical to run 1 (.data restored on reset):", same)
    ok = ok1 and ok2 and no_fail and same
    print("[host] RESULT:", "PASS" if ok else "FAIL")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
