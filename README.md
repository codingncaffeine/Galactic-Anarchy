<p align="center"><img src="assets/screenshot.png" alt="Galactic Anarchy on a Commodore 64" width="640"></p>

# Galactic Anarchy

A first-person space shooter for the Commodore 64, drawn in 3D vector graphics. It runs on
a stock PAL or NTSC machine, written in 6502 assembly.

The galaxy's government has fallen, and three factions fight over what is left: the
remains of the old navy, pirates, and a swarm of mining drones that has turned on
everyone. You fly an interceptor across the sector map from the outer rim to the old
capital, choosing your route as you go. Sectors get harder the farther you get, and the
factions fight each other as well as you. A dogfight sector is cleared by reaching its
kill quota, and the best scores are saved to disk.

## Status

Early development. The current build is the engine benchmark: it opens on the enemy
roster, turning each enemy in the double-buffered hires viewport with its name on the
panel and moving on to the next by itself. The panel also shows the frame rate and how
many cycles each stage of a frame takes. There is no game to play yet.

The enemies so far: the Concord Lancer and Gunship, the Corsair Raider and Mauler, the
insect machines of the Swarm (Skitter, Hornet, Moth, Mantis, Centipede and their Hive),
crystal mines and asteroids. They are made in `models/`, in a plain text format.

The game is free and open source and will stay that way.

## Playing it

The game is developed and tested on [Kernal64](https://github.com/codingncaffeine/Kernal64),
a Commodore 64 core for [Emutastic](https://github.com/codingncaffeine/Emutastic-For-Linux)
and RetroArch. Open `galactic-anarchy.prg` in either one. It should also run on other C64
emulators and on real hardware, but those are not tested yet.

A joystick in port 2 will be the main control.

## Building

Linux, with `git`, `make` and a C compiler:

```sh
./build.sh
```

The game is written to `build/galactic-anarchy.prg` and copied to `bin/`. If `ca65` and
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
