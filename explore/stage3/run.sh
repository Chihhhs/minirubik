#!/bin/sh
# Run an RV32I ELF on Ripes CLI: ./run.sh rv_x.elf [proc]   (default RV32_ISS)
# Prints the program output, exit code, retired instructions and section sizes.
RIPES=${RIPES:-/Users/chihhlinn/code/CArch/Ripes/build/Ripes.app/Contents/MacOS/Ripes}
[ -f "$1" ] || { echo "usage: $0 file.elf [proc]" >&2; exit 2; }
proc=${2:-RV32_ISS}
riscv64-elf-size -A "$1" | awk '$1 ~ /^\.(text|s?rodata|s?data|s?bss)/ {print}'
/usr/bin/time -p "$RIPES" --mode cli --src "$1" -t elf --proc "$proc" \
    --iret --exectime --timeout 3600000
