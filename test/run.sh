#!/usr/bin/env bash
# Runs the game's checks headless and silent in Kernal64's k64run.
#   K64RUN     the runner (default: ../Kernal64/bin/k64run next to this project)
#   K64_ROMS   folder with the C64 ROMs (default: RetroArch's system/kernal64)
# The ROMs are the user's own and are never part of this repository.
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
k64run="${K64RUN:-$root/../Kernal64/bin/k64run}"
roms="${K64_ROMS:-$HOME/.config/retroarch/system/kernal64}"

# Preflight: everything the run needs, checked before anything starts.
fail=0
[ -x "$k64run" ] || { echo "preflight: k64run not found at $k64run (set K64RUN)"; fail=1; }
[ -d "$roms" ] || { echo "preflight: ROM folder not found at $roms (set K64_ROMS)"; fail=1; }
for f in build/galactic-anarchy.prg build/test/irq.prg build/test/irq-control.prg; do
  [ -f "$root/$f" ] || { echo "preflight: $f missing (run ./build.sh)"; fail=1; }
done
[ "$fail" = 0 ] || exit 2

out="$root/build/test-out"
rm -rf "$out"; mkdir -p "$out"
run() { taskset -c 0-7 nice -n 10 "$k64run" "$roms" "$@"; }

passed=0; failed=0
check() {  # check NAME EXPECTED_STATUS ARGS...
  local name="$1" want="$2"; shift 2
  run "$@" >"$out/$name.log" 2>&1
  local got=$?
  if [ "$got" = "$want" ]; then
    echo "ok    $name"; passed=$((passed + 1))
  else
    echo "FAIL  $name: exit $got, expected $want (log: build/test-out/$name.log)"; failed=$((failed + 1))
  fi
}

for model in pal ntsc; do
  # The title is on screen after boot and RUN.
  check "boot-$model" 0 --model "$model" --frames 300 \
        --autostart "$root/build/galactic-anarchy.prg" \
        --expect "GALACTIC ANARCHY" --png "$out/boot-$model.png"
  # The raster interrupt runs: 50 frames counted, result 0 written to the debug port.
  check "irq-$model" 0 --model "$model" --cycles 8000000 --debugcart \
        --autostart "$root/build/test/irq.prg"
  # Control: without the interrupt the same test must time out (124), or the check
  # above could not see a broken interrupt.
  check "irq-control-$model" 124 --model "$model" --cycles 8000000 --debugcart \
        --autostart "$root/build/test/irq-control.prg"
done

echo "$passed passed, $failed failed"
[ "$failed" = 0 ]
