#!/bin/sh
# Plays the dev build (the disk image, so high scores are saved) in RetroArch with the
# Kernal64 core (copied to bin/ by build.sh).
# KERNAL64_CORE overrides which core file is used.
here="$(dirname "$(readlink -f "$0")")"
core="${KERNAL64_CORE:-}"
if [ -z "$core" ]; then
  for c in "$HOME/.local/share/Emutastic/Cores/kernal64_libretro.so" \
           "$HOME/.config/retroarch/cores/kernal64_libretro.so" \
           /usr/lib/libretro/kernal64_libretro.so; do
    [ -f "$c" ] && { core="$c"; break; }
  done
fi
[ -n "$core" ] || { echo "run.sh: Kernal64 core not found; set KERNAL64_CORE" >&2; exit 1; }
exec retroarch -L "$core" "$here/galactic-anarchy.d64"
