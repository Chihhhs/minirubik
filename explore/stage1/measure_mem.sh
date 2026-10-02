#!/bin/sh
# Ex7: host bytes per guest byte on Ripes.
# Runs each store-loop program REPS times and reports the minimum
# max-RSS and peak-footprint, then the slope between consecutive sizes.
RIPES=${RIPES:-/Users/chihhlinn/code/CArch/Ripes/build/Ripes.app/Contents/MacOS/Ripes}
PROC=${PROC:-RV32_ISS}
REPS=${REPS:-2}
cd "$(dirname "$0")" || exit 1

run() { # $1 = source file -> prints "iret rss footprint" (min over REPS)
    best_rss=; best_fp=
    i=0
    while [ $i -lt "$REPS" ]; do
        out=$(/usr/bin/time -l "$RIPES" --mode cli --src "$1" -t asm \
            --proc "$PROC" --iret --timeout 120000 2>&1)
        iret=$(printf '%s\n' "$out" | awk '/instructions retired$/ && !/^ +[0-9]/ {getline; print; exit}')
        rss=$(printf '%s\n' "$out" | awk '/maximum resident set size/ {print $1}')
        fp=$(printf '%s\n' "$out" | awk '/peak memory footprint/ {print $1}')
        [ -z "$best_rss" ] || [ "$rss" -lt "$best_rss" ] && best_rss=$rss
        [ -z "$best_fp" ] || [ "$fp" -lt "$best_fp" ] && best_fp=$fp
        i=$((i + 1))
    done
    echo "$iret $best_rss $best_fp"
}

printf '%-12s %10s %14s %14s\n' N iret max_rss peak_footprint
results=
for pair in "4096 ex7_4k.s" "1048576 ex7.s" "2097152 ex7_2m.s" "4194304 ex7_4m.s"; do
    set -- $pair
    r=$(run "$2")
    printf '%-12s %10s %14s %14s\n' "$1" $r
    results="$results$1 $r
"
done

echo
echo "slope = delta bytes / delta N  (host bytes per guest byte)"
printf '%s' "$results" | awk '
    NR > 1 {
        dn = $1 - n
        printf "%8d -> %-8d  rss %6.2f   footprint %6.2f\n", n, $1, ($3 - rss) / dn, ($4 - fp) / dn
    }
    NR == 1 { n0 = $1; rss0 = $3; fp0 = $4 }
    { n = $1; rss = $3; fp = $4 }
    END {
        dn = n - n0
        printf "%8d -> %-8d  rss %6.2f   footprint %6.2f   (overall)\n", n0, n, (rss - rss0) / dn, (fp - fp0) / dn
    }'
