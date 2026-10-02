#!/bin/sh
# Ex8: retired instructions per second on Ripes.
# rate = iret / exectime; real (wall clock incl. startup) shown for comparison.
RIPES=${RIPES:-/Users/chihhlinn/code/CArch/Ripes/build/Ripes.app/Contents/MacOS/Ripes}
cd "$(dirname "$0")" || exit 1
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' 0 1 2 15

# ALU loop with a smaller COUNT for the slow pipelined model.
sed 's/^\.equ COUNT, [0-9]*/.equ COUNT, 100000/' ex8.s >"$tmp/ex8_100k.s"

run() { # $1 = label, $2 = proc, $3 = source
    out=$( { /usr/bin/time -p "$RIPES" --mode cli --src "$3" -t asm \
        --proc "$2" --iret --exectime --timeout 600000; } 2>&1)
    iret=$(printf '%s\n' "$out" | awk '/instructions retired$/ {getline; print; exit}')
    ms=$(printf '%s\n' "$out" | awk '/execution time/ {getline; print; exit}')
    real=$(printf '%s\n' "$out" | awk '$1 == "real" {print $2}')
    rate=$(awk -v i="$iret" -v m="$ms" 'BEGIN { if (m > 0) printf "%.3g", i / (m / 1000); else print "?" }')
    printf '%-22s %-9s %10s %9s %8s %12s\n' "$1" "$2" "$iret" "$ms" "$real" "$rate"
}

printf '%-22s %-9s %10s %9s %8s %12s\n' program proc iret exec_ms real_s inst_per_s
run "ALU loop (5M)"     RV32_ISS ex8.s
run "memory loop (4MiB)" RV32_ISS ex7_4m.s
run "ALU loop (100k)"   RV32_5S  "$tmp/ex8_100k.s"
run "memory loop (4KiB)" RV32_5S  ex7_4k.s
