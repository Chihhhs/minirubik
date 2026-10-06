#!/bin/sh
# Stage 4 runner. Ripes has no .include, so the program Ripes sees is
# rubik.s (with the input string substituted) + the generated tables.s.
#   ./build.sh                  all tests on RV32_ISS (pass/fail + retired)
#   ./build.sh INPUT [proc]     one input, full Ripes output
#   ./build.sh full [INPUT]     only write out/rubik_full.s (for the Ripes GUI)
# Renderer: Ripes has no .if, and the CLI has no LED peripheral, so any line
# using LED_MATRIX_0_* fails to assemble there. Put all renderer code between
# lines "# RENDER-BEGIN" and "# RENDER-END": CLI builds delete those blocks
# and set RENDER = 0; the "full" (GUI) build keeps them and sets RENDER = 1.
# Program contract: prints the solution moves on one line ("R B' D2"),
# exit code 0 = solved and re-checked (T5), 2 = invalid input.
RIPES=${RIPES:-/Users/chihhlinn/code/CArch/Ripes/build/Ripes.app/Contents/MacOS/Ripes}
cd "$(dirname "$0")" || exit 1
TABLES=../explore/stage3/tables.s
[ -f "$TABLES" ] || make -C ../explore/stage3 tables.s >/dev/null || exit 1
mkdir -p out

gen() { # $1 = input string, $2 = gui|cli -> out/rubik_full.s
    if [ "$2" = gui ]; then
        sed -e "s/^input:.*/input:      .string \"$1\"/" \
            -e "s/^\.equ RENDER, .*/.equ RENDER, 1/" rubik.s
    else
        sed -e "s/^input:.*/input:      .string \"$1\"/" \
            -e "s/^\.equ RENDER, .*/.equ RENDER, 0/" \
            -e "/^# RENDER-BEGIN/,/^# RENDER-END/d" rubik.s
    fi >out/rubik_full.s
    cat "$TABLES" >>out/rubik_full.s
}

run() { # $1 = input, $2 = proc
    gen "$1" cli
    "$RIPES" --mode cli --src out/rubik_full.s -t asm --proc "$2" --iret \
        --timeout 600000 2>&1
}

case "$1" in
full) gen "${2:-21345671111111}" gui; echo "wrote out/rubik_full.s (RENDER = 1, for the GUI)"; exit 0 ;;
?*)   run "$1" "${2:-RV32_ISS}"; exit 0 ;;
esac

# All tests: "input|expected length|expected exit"
fail=0
{
    grep -v '^#' ../tests/solutions.txt | awk -F'|' '{print $1 "|" (NF > 1 && $2 != "" ? split($2, a, " ") : 0) "|0"}'
    echo "14325671111111|11|0"      # hardest distance-11 state (rank 192,456)
    echo "11345671111111|-|2"       # not a permutation
    echo "21345671111112|-|2"       # orientation sum not 0 mod 3
    echo "2134567111111|-|2"        # too short
} | while IFS='|' read -r in len code; do
    out=$(run "$in" RV32_ISS)
    got_code=$(printf '%s\n' "$out" | sed -n 's/.*exited with code: //p')
    iret=$(printf '%s\n' "$out" | awk '/instructions retired$/ {getline; print}')
    moves=$(printf '%s\n' "$out" | sed '/exited with code/,$d' | head -1)
    got_len=$(printf '%s' "$moves" | wc -w | tr -d ' ')
    ok=PASS
    [ "$got_code" = "$code" ] || ok=FAIL
    [ "$len" = "-" ] || [ "$got_len" = "$len" ] || ok=FAIL
    printf '%-4s %-15s len %2s (want %2s) exit %s (want %s) %10s instr  %s\n' \
        "$ok" "$in" "$got_len" "$len" "${got_code:-?}" "$code" "${iret:-?}" "$moves"
done
