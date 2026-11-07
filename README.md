# GreenHatFlute

**The Legend of Zelda: Ocarina of Time running natively on Linux, with no emulator.**

The game's code is translated to C and compiled into a Linux program. The Switch 2 graphics are converted to Vulkan.
All of this happens **on your PC, from your own copy of the game**.

GreenHatFlute continues [sostenesfreitas/ocarina-recomp](https://github.com/sostenesfreitas/ocarina-recomp), the
project it comes from, and keeps its history and its license. From there it goes its own way: Linux only, English
throughout, no Windows tooling, no installer, Wayland and X11 both first class.

**This repository is where the project is developed and where problems are reported.** Issues, questions and pull
requests about this build belong here; the project we came from does not take reports about it.

> [!IMPORTANT]
> This repository **does not contain the game, keys or an executable**, and it does not explain how to get them. You
> need your own copy. Everything the build creates (`ocarina`, the generated code, the shader cache and the saves)
> comes from your game: **do not share it**.

## Project status

Experimental. Tested on **one Linux PC** (Gentoo, kernel 6.18, clang 22, i5-12600KF, RTX 5070 12 GB), in the area at
the start of the game.

| What | Status |
|---|---|
| Kokiri village: trees, plants, houses, lighting | ✅ Works |
| Window on Wayland and on X11 | ✅ Both reach `boot: passed`, 0 validation errors, 0 shader failures |
| Sound, saves, AV1 movies decoding | ✅ Works |
| Stutter when entering new areas | ⚠️ Still happens, mostly the first time: shaders compile on sight |
| Playing the ocarina | ❓ Not tested in game |
| Hyrule Field and the rest of the game | ❓ Not tested yet |
| AMD and Intel cards | ❓ Never tested |

## How to build

The game does not come ready-made: it is built on your PC from your copy.

**1. Install the tools and check what is missing:**

```sh
git clone https://github.com/K-code-AI/GreenHatFlute
cd GreenHatFlute
./build.sh --check --game /path/your-game.nup     # looks, changes nothing
```

**2. Build it:**

```sh
./build.sh --game /path/your-game.nup             # about 15 minutes plus the RomFS
```

It needs your own copy of the game at **version 1.1.1**, 16 GB of RAM and about 60 GB free. You can use the PC
meanwhile. If it stops, run it again: it continues from where it stopped.

**3. Play:**

```sh
play/run.sh
```

**4. Optional — install it as a desktop app** (menu entry, icon, `greenhatflute` on PATH, all under XDG paths so no
root is needed):

```sh
python tools/install_linux.py
```

Prefer to read every command first? Follow the **[step-by-step build guide](docs/build-by-hand.md)**.

> [!NOTE]
> The first time you open the game, **plants can take a few minutes to appear** while shaders compile in the
> background. It gets better after that.

### Where your saves go

`~/.local/share/greenhatflute` (or `$XDG_DATA_HOME/greenhatflute`) — not next to the executable, so the build folder
can be moved or deleted without losing a game. `TOTK_PROFILE_DIR` or `--profile DIR` overrides that.

### What you need

- 64-bit Linux, with an AVX2-capable processor.
- A graphics card with Vulkan 1.3 and mesh shaders, with an up-to-date driver. We recommend NVIDIA.
- 16 GB of RAM or more. We never tested with less: the build or the game may fail.
- 60 GB free.
- Internet access during the build.
- **Your copy of the game at version 1.1.1.** Other versions do not work.

### If something goes wrong

| Problem | What to do |
|---|---|
| "this game is not version 1.1.1" | Check that you chose the right, updated game |
| `device-local allocation failed (-2)` | The card's free VRAM is smaller than the game's pools. The run survives on host memory but slowly; close what holds the card and check with `nvidia-smi` |
| Stutter the first time | Normal: shaders are being prepared. It gets better when you pass through the same place again |

If the problem continues, [open an issue](https://github.com/K-code-AI/GreenHatFlute/issues) with the error message
and your graphics card model. Never send game files.

### Controls

Use a controller, or keyboard and mouse. **F1** or **Esc** opens the options menu, **F11** toggles fullscreen and
**F10** shows the frame rate. The full list is in [docs/controls.md](docs/controls.md).

## How it works

1. `recomp/gen.py` translates the game's ARM64 code to C.
2. `tools/build_game.py` compiles that C together with `runtime/`, which plays the part of the console's system.
3. `runtime/` converts NVN 2 graphics calls to Vulkan.
4. Switch 2 Ampere shaders are lowered to Maxwell (`lower_to_maxwell.h`) and translated to SPIR-V by a patched Ryujinx (`tools/xlate/patches`).

## Want to help?

Read the **[contributing guide](CONTRIBUTING.md)**. Testing on other graphics cards and reporting the result already
helps a lot.

## Credits

The project comes from **Miojo** ([sostenesfreitas](https://github.com/sostenesfreitas)), who started it and maintains
the original. We keep its history and thank them for it; questions about this build go to us, not to them.

This project exists thanks to the work of many people:

- **[Lucas-blip-png/dkb-pc-recomp](https://github.com/Lucas-blip-png/dkb-pc-recomp)** and TotK Recomp: the base of this project, whose history is preserved here.
- **[seedds/nxnative](https://github.com/seedds/nxnative)**: reference for how the game uses task and mesh shaders, and the microphone fix.
- **[zortos293/Lichii](https://github.com/zortos293/Lichii)** and Eglantine/Eden: Ampere shader lowering and the reference for comparing draws.
- **[Ryujinx](https://github.com/Ryujinx/Ryujinx)**: the shader translator.
- **[kinnay/zbic](https://github.com/kinnay/zbic)**: executable decompression, downloaded during the build.

The full list is in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## License

[GPL-3.0](LICENSE), like the original project. Third-party parts keep their own licenses, listed in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Fan project, not affiliated with Nintendo. The Legend of Zelda and Ocarina of Time are trademarks of Nintendo.
