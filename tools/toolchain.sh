#!/usr/bin/env bash
# Puts the cc65 assembler and linker (ca65, ld65) in .toolchain/cc65/bin, built from the
# pinned release tag. build.sh calls it when the tools are missing.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tag="V2.19"
dest="$root/.toolchain/cc65"
if [ -x "$dest/bin/ca65" ] && [ -x "$dest/bin/ld65" ] && [ "$(cat "$dest/.tag" 2>/dev/null)" = "$tag" ]; then
  exit 0
fi
for tool in git make cc; do
  command -v "$tool" >/dev/null || { echo "toolchain: $tool is required" >&2; exit 1; }
done
rm -rf "$dest"
git clone --quiet --depth 1 --branch "$tag" https://github.com/cc65/cc65 "$dest"
# A quarter of the cores, at low priority.
jobs=$(( $(nproc --all) / 4 )); [ "$jobs" -ge 1 ] || jobs=1
nice -n 10 make -C "$dest" -j"$jobs" bin >/dev/null
echo "$tag" > "$dest/.tag"
"$dest/bin/ca65" --version
