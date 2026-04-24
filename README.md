# Odin + Karl2D + Hot Reload

This is a small, kinda hacked-together hot reload setup for Odin + [Karl2D](https://github.com/karl-zylinski/karl2d).

Right now it only supports Windows, but the code is mostly portable. You’d just need to write a `build-hot-reload.sh` for macOS/Linux.

Tested in `odin version dev-2026-04-nightly:a896fb2`

## How it works

- `hotreload/main.odin` is the host executable. It owns the window and Karl2D state.
- `game/` is compiled as a DLL. This is your actual game code.
- When you rebuild the DLL, the host swaps it in without restarting the process.

If the size of your game state changes, the game will restart (but the window stays open).  
If it doesn’t, state is preserved across reloads.

Each DLL has its own PDB, debugging should work (but it wasn't tested).

## Running

```bash
./build-hot-reload.bat
```

The first time you run, this will generate both `./game_hotreload.exe` and the DLL files.

`./game_hotreload.exe` will start the game, and when you run `build-hot-reload.bat` again, it will generate a new DLL and the game will automatically swap.

Usual loop should be:

1. Edit Code
2. Run `build-hot-reload.bat`
3. Watch the game change

## Credits

This is heavily inspired by [Odin + Raylib + Hot Reload template](https://github.com/karl-zylinski/odin-raylib-hot-reload-game-template).

