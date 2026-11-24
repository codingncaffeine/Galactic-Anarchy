#!/usr/bin/env bash
# Makes assets/ga-speech.prg, the spoken warnings, with espeak-ng (a free speech
# synthesizer) and our own converter. Run by hand when the phrases change; the result
# is kept in the repository so the build does not need espeak-ng.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
n=0
for phrase in "warning" "shields low" "jump"; do   # the order is SPEAK_* in src/speech.s
  espeak-ng -v en-us -s 190 -p 30 -w "$tmp/$n.wav" "$phrase"
  n=$((n + 1))
done
dotnet build "$root/tools/GaTool" -c Release -o "$tmp/gatool" -v q --nologo >/dev/null
"$tmp/gatool/GaTool" speech "$root/assets/ga-speech.prg" "$tmp"/{0,1,2}.wav
echo "wrote assets/ga-speech.prg ($(stat -c %s "$root/assets/ga-speech.prg") bytes)"
