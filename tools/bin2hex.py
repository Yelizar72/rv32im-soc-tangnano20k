"""Convert a raw firmware binary into a $readmemh file of 32-bit little-endian words.

    python3 tools/bin2hex.py firmware.bin firmware.hex 2048

Pads with zeros to the RAM size and fails if the image does not fit.
"""
import sys

src, dst, words = sys.argv[1], sys.argv[2], int(sys.argv[3])
data = open(src, "rb").read()
if len(data) > words * 4:
    sys.exit(f"bin2hex: firmware is {len(data)} bytes, RAM holds only {words * 4}")
data += b"\0" * (words * 4 - len(data))
with open(dst, "w") as f:
    for i in range(words):
        f.write(f"{int.from_bytes(data[4 * i:4 * i + 4], 'little'):08x}\n")
print(f"bin2hex: {len(data.rstrip(bytes(1)))} bytes used of {words * 4}")
