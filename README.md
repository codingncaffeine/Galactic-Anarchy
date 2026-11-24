# Galactic Anarchy

A first-person space shooter for the Commodore 64, drawn in 3D vector graphics.

The galaxy's government has fallen and three factions fight over what is left: the
remains of the old navy, pirates, and a swarm of mining drones that has turned on
everyone. You fly an interceptor across the sector map from the outer rim to the old
capital, choosing your route as you go. Sectors get harder the farther you get, and the
factions fight each other as well as you.

The game is in early development. Nothing playable exists yet beyond a start-up screen.

## Requirements

- A PAL or NTSC Commodore 64, or an emulator. The game is developed and tested on the
  [Kernal64](https://github.com/codingncaffeine/Kernal64) core.
- A joystick in port 2.

## Building

Linux, with `git`, `make` and a C compiler installed:

```sh
./build.sh
```

The first build fetches and compiles the cc65 assembler (release V2.19) into
`.toolchain/`, unless `ca65` and `ld65` are already installed. The game is written to
`build/galactic-anarchy.prg`.

`bin/run.sh` starts the build in RetroArch with the Kernal64 core.

## Tests

```sh
test/run.sh
```

The tests run the game headless in Kernal64's `k64run` tool. They need a built Kernal64
next to this folder (or `K64RUN` pointing to `k64run`) and a folder with your own C64 ROMs
(`K64_ROMS`, default `~/.config/retroarch/system/kernal64`).

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
