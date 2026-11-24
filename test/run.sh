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
for f in build/galactic-anarchy.prg build/test/irq.prg build/test/irq-control.prg \
         build/test/mul.prg build/test/mul-control.prg build/test/play.prg build/test/play-control.prg \
         build/test/boss.prg build/test/boss-control.prg; do
  [ -f "$root/$f" ] || { echo "preflight: $f missing (run ./build.sh)"; fail=1; }
done
[ "$fail" = 0 ] || exit 2

out="$root/build/test-out"
rm -rf "$out"; mkdir -p "$out"
run() { taskset -c 0-7 nice -n 10 "$k64run" "$roms" "$@"; }

passed=0; failed=0
check_not() {  # check_not NAME UNWANTED_STATUS ARGS...: any exit but UNWANTED passes
  local name="$1" unwanted="$2"; shift 2
  run "$@" >"$out/$name.log" 2>&1
  local got=$?
  if [ "$got" != "$unwanted" ]; then
    echo "ok    $name"; passed=$((passed + 1))
  else
    echo "FAIL  $name: exit $got (log: build/test-out/$name.log)"; failed=$((failed + 1))
  fi
}
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

# check_panel NAME: the play build's title panel reads "GAL" at row 21, column 12 of buffer
# 0's screen ($8400 + 21*40 + 12 = $8754), in the game's screen codes.
check_panel() {
  local name="$1"; shift
  run "$@" --dump 8754:3 >"$out/$name.log" 2>&1
  local got=$?
  local text
  text=$(grep -i '^8754:' "$out/$name.log" | cut -d' ' -f2-4 | tr 'A-F' 'a-f')
  if [ "$got" = 0 ] && [ "$text" = "07 01 0c" ]; then
    echo "ok    $name"; passed=$((passed + 1))
  else
    echo "FAIL  $name: exit $got, panel bytes '$text' (log: build/test-out/$name.log)"; failed=$((failed + 1))
  fi
}

# Through Kernal64 as a frontend runs it (k64host + the core), with the joystick held.
k64host="${K64HOST:-$root/../Kernal64/bin/k64host}"
core="${K64CORE:-$root/../Kernal64/bin/kernal64_libretro.so}"
system="${K64_SYSTEM:-$HOME/.config/retroarch/system}"
label_addr() { sed -n "s/^al 0000\([0-9A-F]*\) \.$1\$/\1/p" "$root/build/galactic-anarchy.labels"; }
# check_host NAME FRAMES LABEL VALUE [--hold ...]: after FRAMES frames, LABEL's byte = VALUE.
check_host() {
  local name="$1" frames="$2" label="$3" value="$4"; shift 4
  mkdir -p "$out/save"
  taskset -c 0-7 nice -n 10 "$k64host" "$core" --content "$root/build/galactic-anarchy.prg" \
    --system "$system" --save "$out/save" --frames "$frames" --expect-ram "$(label_addr "$label")" "$value" \
    --dump "$out/$name.ppm" "$@" >"$out/$name.log" 2>&1
  local got=$?
  if [ "$got" = 0 ]; then
    echo "ok    $name"; passed=$((passed + 1))
  else
    echo "FAIL  $name: $(grep -m1 FAIL "$out/$name.log") (log: build/test-out/$name.log)"; failed=$((failed + 1))
  fi
}
if [ -x "$k64host" ] && [ -f "$core" ]; then
  # Fire (RetroPad B, the core's default) on the title starts a game on the map (state 4).
  check_host fire-starts-game 900 state 4 --hold 450 460 0 b 1
  # Fire again on the map: the jump to the chosen sector, which is in play (state 2).
  check_host map-fire-jumps 1000 state 2 --hold 450 460 0 b 1 --hold 600 610 0 b 1
  # Control: A is not fire, so the title stays (state 0).
  check_host other-button-does-not 900 state 0 --hold 450 460 0 a 1
  # Right held: the crosshair runs from the middle (128) to its stop at 248.
  check_host crosshair-right 1000 cross_x 248 --hold 450 460 0 b 1 --hold 600 610 0 b 1 \
    --hold 800 900 0 right 1
else
  echo "FAIL  k64host or the core not found ($k64host, $core)"; failed=$((failed + 1))
fi

# A game played by the test build: it aims at enemies and fires; passes after 5 kills.
check play 0 --cycles 150000000 --debugcart --autostart "$root/build/test/play.prg"
# Control: the same, aiming 60 pixels to the side, must not get there.
check play-control 124 --cycles 150000000 --debugcart --autostart "$root/build/test/play-control.prg"
# The Dreadnought: aiming at its weak points destroys it; the control aiming off cannot
# (the shields run out first: 2, or the time: 124).
check boss 0 --cycles 150000000 --debugcart --autostart "$root/build/test/boss.prg"
check_not boss-control 0 --cycles 150000000 --debugcart --autostart "$root/build/test/boss-control.prg"

# The fast multiply equals shift-and-add for all 65,536 pairs; the control has one table
# entry corrupted and must fail (1).
check mul 0 --cycles 40000000 --debugcart --autostart "$root/build/test/mul.prg"
check mul-control 1 --cycles 40000000 --debugcart --autostart "$root/build/test/mul-control.prg"

for model in pal ntsc; do
  # The game starts on its title: "GAL" at row 21, column 12 of the panel.
  check_panel "boot-$model" --model "$model" --frames 400 \
        --autostart "$root/build/galactic-anarchy.prg" --png "$out/boot-$model.png"
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
