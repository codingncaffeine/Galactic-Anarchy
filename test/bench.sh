#!/usr/bin/env bash
# Runs the benchmark scenes headless in Kernal64's k64run and prints, per scene, the
# frame rate and the average cycles per drawn frame of each stage. Screenshots go to
# build/bench/. Usage: test/bench.sh [pal|ntsc] (default pal)
#   K64RUN, K64_ROMS   as for test/run.sh
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
k64run="${K64RUN:-$root/../Kernal64/bin/k64run}"
roms="${K64_ROMS:-$HOME/.config/retroarch/system/kernal64}"
model="${1:-pal}"
[ -x "$k64run" ] || { echo "bench: k64run not found at $k64run (set K64RUN)"; exit 2; }
[ -d "$roms" ] || { echo "bench: ROM folder not found at $roms (set K64_ROMS)"; exit 2; }

out="$root/build/bench"
rm -rf "$out"; mkdir -p "$out"
rate=50; [ "$model" = ntsc ] && rate=60

printf '%-6s %6s %6s %9s %9s %9s %9s\n' scene edges fps clear math lines total
status=0
for scene in 1 2 3; do
  prg="$root/build/test/bench-$scene.prg"
  [ -f "$prg" ] || { echo "bench: $prg missing (run ./build.sh)"; exit 2; }
  log="$out/bench-$scene.log"
  taskset -c 0-7 nice -n 10 "$k64run" "$roms" --model "$model" --cycles 200000000 --debugcart \
    --autostart "$prg" --png "$out/bench-$scene.png" --dump 0340:10 >"$log" 2>&1
  rc=$?
  if [ "$rc" != 0 ]; then echo "scene $scene: run failed (exit $rc, log $log)"; status=1; continue; fi
  # The dump line: "0340: b0 b1 ... b15"
  read -r -a b < <(grep '^0340:' "$log" | cut -d' ' -f2-)
  h() { echo $((16#${b[$1]})); }
  edges=$(h 1)
  frames=$(( $(h 2) + 256 * $(h 3) ))
  s24() { echo $(( $(h $1) + 256 * $(h $(($1 + 1))) + 65536 * $(h $(($1 + 2))) )); }
  clear=$(( $(s24 4) / 32 )); math=$(( $(s24 7) / 32 )); lines=$(( $(s24 10) / 32 ))
  fps=$(awk -v f="$frames" -v r="$rate" 'BEGIN { printf "%.1f", 32 * r / f }')
  printf '%-6s %6s %6s %9s %9s %9s %9s\n' "$scene" "$edges" "$fps" "$clear" "$math" "$lines" \
    $((clear + math + lines))
done
exit "$status"
