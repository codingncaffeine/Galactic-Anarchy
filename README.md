<p align="center"><img src="assets/cover.jpg" alt="Galactic Anarchy cover" width="480"></p>

# Galactic Anarchy

A first-person space shooter for the Commodore 64, drawn in 3D vector graphics. It runs on
a stock PAL or NTSC machine, written in 6502 assembly.

The galaxy's government has fallen, and three factions fight over what is left: the
remains of the old navy, pirates, and the Swarm, mining machines that grew into
insect shapes and turned on everyone. You fly an interceptor across the sector map from the outer rim to the old
capital, choosing your route as you go. Sectors get harder the farther you get, and the
factions fight each other as well as you. A dogfight sector is cleared by reaching its
kill quota, and the best scores are saved to disk.

## Status

Playable from start to finish, still in development. The title shows the high scores and
a demo in turn; press fire to start. A game is a journey across the sector map, left to
right, picking your route lane by lane:

- Each sector belongs to the Concord, the Corsairs or the Swarm, whose fighters and
  insect machines you meet there, or is an asteroid field. Some are derelict stations
  where you thread rings before the reactor blows. A sector is cleared at its kill quota,
  and the farther across the map, the harder.
- Some sectors are convoys of freighters. Left or right on the map chooses whether you
  raid the convoy or escort it against its rivals' fighters.
- Rival factions turn up in each other's space and fight among themselves;
  what they destroy counts toward your quota.
- Every faction keeps a heat for you, shown on the panel. The ones you shoot send more
  ships, sooner, and take over more of the map ahead; shooting their rivals cools them.
- Kills and cleared sectors earn credits. After each sector the dock sells shield
  repairs, shield cells and gun upgrades.
- The Dreadnought waits in the middle of the map and at its end: knock out its four weak
  points before it jumps away.
- High scores are saved to the disk with your initials.

Steer with the joystick (the view turns as you aim) and press fire to shoot. Hold fire
and let go to fire a charged shot that hits everything near the crosshair. Enemy shots
can be shot down. Every hit costs a shield block, a cleared sector repairs two, and the
game ends when they are gone. Up or down on the title turns the music on or off. Played
from the disk image, the game also speaks a few warnings.

<p align="center"><img src="assets/screenshot.png" alt="Galactic Anarchy running in Kernal64" width="640"></p>

All the ships, rocks and insects are made in `models/` and the music in `music/`, both in
plain text formats compiled by the project's own tool. The spoken warnings are made with
[espeak-ng](https://github.com/espeak-ng/espeak-ng) by `tools/speech.sh`.

## Playing it

The game is developed and tested on [Kernal64](https://github.com/codingncaffeine/Kernal64),
a Commodore 64 core for [Emutastic](https://github.com/codingncaffeine/Emutastic-For-Linux)
and RetroArch. Open `galactic-anarchy.d64` (the disk image) in either one; the game
saves its high scores to that disk. `galactic-anarchy.prg` runs too, without saving. It should also run on other C64
emulators and on real hardware, but those are not tested yet.

Controls: a joystick in port 2. In RetroArch or Emutastic with Kernal64, the RetroPad's
d-pad steers and B is fire.

## Building

Linux, with `git`, `make` and a C compiler:

```sh
./build.sh
```

The game is written to `build/galactic-anarchy.prg` and `build/galactic-anarchy.d64`
and copied to `bin/`. If `ca65` and
`ld65` (from [cc65](https://cc65.github.io/)) are not installed, the first build fetches
cc65 V2.19 and compiles it into `.toolchain/`. On Arch Linux, `yay -S cc65` installs it.

`bin/run.sh` starts the build in RetroArch with the Kernal64 core.

The build also needs the .NET 10 SDK, which runs the project's own tool for the math
tables, the font and the models (`tools/GaTool`).

## Tests

```sh
test/run.sh
```

The tests run the game headless and silent in Kernal64's `k64run` tool, on PAL and NTSC.
`test/bench.sh` runs the benchmark scenes the same way and prints their timings.
They need a built Kernal64 in a folder next to this one (or `K64RUN` set to the path of
`k64run`) and a folder with your own C64 ROMs (`K64_ROMS`, by default
`~/.config/retroarch/system/kernal64`). The ROMs are not part of this repository.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
