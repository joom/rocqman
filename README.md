# Rocqman

Rocqman is a Pacman-like game written in Rocq and extracted to C++ with [Crane](https://github.com/bloomberg/crane). The game uses SDL2 for rendering, SDL2_image for loading the Rocq logo sprite, and small external audio players for sound playback.
This establishes, at least informally, that Rocq is [Pacman-complete](https://corecursive.com/006-type-driven-development-and-idris-with-edwin-brady/#being-pacman-complete---0923---).

![Rocqman screenshot](assets/screenshot.png)

## Features

- game logic written in Rocq
- extraction to C++ with Crane
- SDL2 rendering
- smooth sprite interpolation
- sound effects for dots, power pellets, ghost kills, losing a life, game over, and victory

## Requirements

You need:

- Rocq with `dune`
- a C++23 compiler
- `pkg-config`
- SDL2
- SDL2_image

Runtime audio also needs a platform player in `PATH`:

- macOS: `afplay`
- Linux: one of `mpg123`, `ffplay`, or `play`

## Getting started

Clone the repo with everything it needs:

```bash
git clone --recurse-submodules https://github.com/joom/rocqman.git
cd rocqman
```

If you already cloned it without submodules, run:

```bash
git submodule update --init --recursive
```

## Installing dependencies

### macOS

Install the SDL packages with Homebrew:

```bash
brew install sdl2 sdl2_image
```

If you want to use Homebrew LLVM instead of the system toolchain:

```bash
brew install llvm
```

### Linux

The exact package names vary by distribution, but you generally need:

```bash
sudo apt install clang pkg-config libsdl2-dev libsdl2-image-dev
```

For sound playback, also install at least one of:

```bash
sudo apt install mpg123
```

or

```bash
sudo apt install ffmpeg
```

or

```bash
sudo apt install sox
```

## Building

Build the game:

```bash
make
```

This does three things:

1. uses the local Crane checkout in `./crane`
2. extracts [`theories/Rocqman.v`](./theories/Rocqman.v) and [`theories/SDL.v`](./theories/SDL.v) to C++
3. copies the generated C++ into `src/generated/`
4. compiles the final executable `./rocqman`

Build with a different optimization level:

```bash
make OPT=-O2
```

## Running

Run the game:

```bash
make run
```

or:

```bash
./rocqman
```

Controls:

- arrow keys or `WASD`: move
- `Space`: pause or unpause
- `Q` or `Esc`: quit

## Cleaning

Remove build outputs:

```bash
make clean
```

This removes:

- `./rocqman`
- `./src/generated/`
- `./rocqman.dSYM`
- Dune build outputs

## Repository structure

```text
.
├── assets/
│   ├── *.mp3           sound effects
│   └── rocq.svg        player sprite
├── crane/              Crane submodule used for extraction
├── src/
│   └── sdl_helpers.h   C++ SDL and audio helper functions
├── theories/
│   ├── Rocqman.v       game logic, rendering, extracted main
│   ├── SDL.v           Rocq-side SDL bindings and extraction directives
│   └── dune            Coq theory stanza
├── Makefile            extraction and native build entrypoint
├── dune-project        Dune project file
└── README.md
```

Generated files are written to:

```text
src/generated/
```

These are build artifacts and should not be edited manually.

## Development notes

- The authoritative game logic lives in Rocq, not in the generated C++.
- The build expects Crane at [`crane/`](./crane).
- [`src/sdl_helpers.h`](./src/sdl_helpers.h) is the main handwritten C++ integration layer.
- The extracted program defines its own `main`, so there is no separate handwritten `main.cpp`.
- If extraction succeeds but sound does not play on Linux, check that one of `mpg123`, `ffplay`, or `play` is installed.
