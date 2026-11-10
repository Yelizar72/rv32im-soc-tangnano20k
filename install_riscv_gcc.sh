#!/usr/bin/env bash
# Installs the RISC-V cross-compiler (xPack riscv-none-elf-gcc) on macOS into ~/fpga
# and puts it on your PATH via ~/.zshrc.     bash install_riscv_gcc.sh
set -euo pipefail

VER="15.2.0-1"
DEST="$HOME/fpga"
say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
fail() { printf '\n\033[31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "Run this in the Mac Terminal."
case "$(uname -m)" in
    arm64)  PLAT="darwin-arm64" ;;
    x86_64) PLAT="darwin-x64"   ;;
    *)      fail "Unknown CPU type $(uname -m)" ;;
esac

DIR="$DEST/xpack-riscv-none-elf-gcc-$VER"
if [ -x "$DIR/bin/riscv-none-elf-gcc" ]; then
    echo "Already installed in $DIR"
else
    FILE="xpack-riscv-none-elf-gcc-$VER-$PLAT.tar.gz"
    URL="https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/v$VER/$FILE"
    mkdir -p "$DEST"
    say "Downloading $FILE"
    curl -fL --progress-bar -o "$DEST/$FILE" "$URL" || fail "Download failed: $URL"
    say "Unpacking"
    tar -xzf "$DEST/$FILE" -C "$DEST"
    xattr -dr com.apple.quarantine "$DIR" 2>/dev/null || true
    rm -f "$DEST/$FILE"
fi
ln -sfn "$DIR" "$DEST/riscv"

RC="$HOME/.zshrc"
if ! grep -qs 'fpga/riscv/bin' "$RC"; then
    printf '\n# RISC-V cross-compiler (xPack)\nexport PATH="$HOME/fpga/riscv/bin:$PATH"\n' >> "$RC"
    echo "Added ~/fpga/riscv/bin to PATH in $RC"
fi

"$DEST/riscv/bin/riscv-none-elf-gcc" --version | head -1
"$DEST/riscv/bin/riscv-none-elf-gcc" -print-multi-lib | grep -q '^rv32im/' \
    && echo "rv32im libraries: present" || fail "rv32im libraries missing"
say "Done. Open a new Terminal window, then: fpgaenv && cd rv32_soc && make sim"
