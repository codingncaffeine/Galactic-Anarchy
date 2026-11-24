#!/usr/bin/env bash
# Builds the game and its test variants.
#   build/galactic-anarchy.prg   the game
#   build/test/*.prg             test builds (see test/run.sh)
# The dev build is copied to bin/, with bin/run.sh to play it.
set -euo pipefail
root="$(cd "$(dirname "$0")" && pwd)"
cd "$root"

if command -v ca65 >/dev/null && command -v ld65 >/dev/null; then
  CA65=ca65; LD65=ld65
else
  "$root/tools/toolchain.sh"
  CA65="$root/.toolchain/cc65/bin/ca65"; LD65="$root/.toolchain/cc65/bin/ld65"
fi

rm -rf build
mkdir -p build/test

# assemble OUT.prg [ca65 -D options...]
assemble() {
  local out="$1"; shift
  local obj="${out%.prg}.o"
  "$CA65" --cpu 6502 -I src -g "$@" -o "$obj" src/main.s
  "$LD65" -C cfg/game.cfg -o "$out" -m "${out%.prg}.map" -Ln "${out%.prg}.labels" "$obj"
}

assemble build/galactic-anarchy.prg
assemble build/test/irq.prg -D TEST=1
assemble build/test/irq-control.prg -D TEST=1 -D NO_IRQ=1

mkdir -p bin
cp build/galactic-anarchy.prg bin/
cp tools/run.sh bin/run.sh
chmod +x bin/run.sh
echo "built build/galactic-anarchy.prg ($(stat -c %s build/galactic-anarchy.prg) bytes)"
