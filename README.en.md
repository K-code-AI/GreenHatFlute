# Ocarina Recomp

[Leia em português](README.md)

**Ocarina of Time running natively on Windows, with no emulator.**

The game's code is translated to C and compiled into a Windows program. The Switch 2 graphics are converted to Vulkan. All of this happens **on your PC, from your own copy of the game**.

> [!IMPORTANT]
> This repository **does not contain the game, keys or an executable**, and it does not explain how to get them. You need your own copy. Everything the installation creates (`ocarina.exe`, the generated code, the shader cache and the saves) comes from your game: **do not share it**.

## Project status

Experimental. It has only been tested on **one PC** (Ryzen 9 9950X3D, RTX 5090), in the area at the start of the game.

| What | Status |
|---|---|
| Kokiri village: trees, plants, houses, lighting | ✅ Works |
| Sound, controller, saves and videos | ✅ Works |
| Performance on an RTX 5090 | ✅ About 59 fps standing still, 51 to 55 fps walking |
| Stutter when entering new areas | ⚠️ Still happens, mostly the first time |
| Playing the ocarina | ❓ Fix applied, not yet tested in game |
| Hyrule Field and the rest of the game | ❓ Not tested yet |
| AMD and Intel cards | ❓ Never tested |

## How to build

The game does not come ready-made: it is built on your PC from your copy. Choose one of these three ways.

**1. With the installer, the easiest:**

1. Download **[Instalar-Ocarina.exe](https://github.com/sostenesfreitas/ocarina-recomp/releases/latest/download/Instalar-Ocarina.exe)** and double-click it.
2. The executable has no digital signature, so Windows may warn you. Click **More info** and then **Run anyway**.
3. In the window, choose your game's `.nup` (or a folder with `exefs` and `romfs`) and click **Install**.
4. If Windows asks for permission to install the tools, click **Yes**.

Want to check first? The executable only opens the [installer script](instalador/Instalar-Ocarina.ps1), and [its code](instalador/launcher.c) is a few lines long. The release lists the file's SHA-256. Antivirus programs sometimes complain about unsigned programs.

**2. With the scripts, which you can read before running** (first install the tools from step 1 of the [guide](docs/build-by-hand.md)):

```powershell
git clone https://github.com/sostenesfreitas/ocarina-recomp C:\OcarinaRecomp
cd C:\OcarinaRecomp
powershell -ExecutionPolicy Bypass -File .\verificar.ps1 -Jogo "C:\path\your-game.nup"
powershell -ExecutionPolicy Bypass -File .\compilar.ps1 -Simular -Jogo "C:\path\your-game.nup"
powershell -ExecutionPolicy Bypass -File .\compilar.ps1 -Jogo "C:\path\your-game.nup"
```

1. `verificar.ps1` only looks and says what is missing. It changes nothing.
2. `compilar.ps1 -Simular` shows every command and runs none of them.
3. `compilar.ps1` runs those commands, shows each one and asks before each step. If it stops, run it again: it continues from where it stopped.

`-ExecutionPolicy Bypass` applies only to that command and does not change your Windows settings.

**3. Fully by hand:** follow the **[step-by-step build guide](docs/build-by-hand.md)**.

### What this does on your PC

- The scripts do not ask for administrator. Installing the tools may: the installer does that for you, and in the other ways you run it yourself.
- It writes only inside the project folder, and never changes your game file.
- It downloads the Python packages (`tools\requirements-build.txt`), the shader translator's .NET packages and, if the game's executable is compressed, [zbic](https://github.com/kinnay/zbic).
- To uninstall, delete the project folder. The tools from step 1 are removed through Windows' apps panel.

It takes 30 minutes to 2 hours, and you can use your PC in the meantime. To update, run the installer again or see the end of the guide.

> [!NOTE]
> The first time you open the game, **plants can take a few minutes to appear** while shaders compile in the background. It gets better after that.

### What you need

- 64-bit Windows 10 or 11, with an AVX2-capable processor.
- A graphics card with Vulkan 1.3 and mesh shaders, with an up-to-date driver. We recommend NVIDIA.
- We recommend 16 GB of RAM or more. We never tested with less: the build or the game may fail.
- 60 GB free, plus about 15 GB on C: if the tools are not installed yet.
- Internet access during installation.
- **Your copy of the game at version 1.1.1.** Other versions do not work.

### If something goes wrong

| Problem | What to do |
|---|---|
| "This game is not version 1.1.1" | Check that you chose the right, updated game |
| The game opens and closes | Update your graphics driver and look at `ultima-partida-erros.log` in the install folder |
| Stutter the first time | This is normal: shaders are being prepared. It gets better when you pass through the same place again |

If the problem continues, [open an issue](https://github.com/sostenesfreitas/ocarina-recomp/issues) with the error message and your graphics card model. Never send game files.

### Controls

Use a controller, or keyboard and mouse. **F1** or **Esc** opens the options menu, **F11** toggles fullscreen and **F10** shows the frame rate. The full list is in [docs/controls.md](docs/controls.md).

## How it works

1. `recomp/gen.py` translates the game's ARM64 code to C.
2. `tools/build_game.py` compiles that C together with `runtime/`, which plays the part of the console's system.
3. `runtime/` converts NVN 2 graphics calls to Vulkan.
4. Switch 2 Ampere shaders are lowered to Maxwell (`lower_to_maxwell.h`) and translated to SPIR-V by a patched Ryujinx (`tools/xlate/patches`).

## Want to help?

Read the **[contributing guide](CONTRIBUTING.en.md)**. Testing on other graphics cards and reporting the result already helps a lot.

## Credits

Maintained by **Miojo** ([sostenesfreitas](https://github.com/sostenesfreitas)). Word is he left a hidden message in the installer and another one inside the game. 🍜

This project exists thanks to the work of many people:

- **[Lucas-blip-png/dkb-pc-recomp](https://github.com/Lucas-blip-png/dkb-pc-recomp)** and TotK Recomp: the base of this project, whose history is preserved here.
- **[seedds/nxnative](https://github.com/seedds/nxnative)**: reference for how the game uses task and mesh shaders, and the microphone fix.
- **[zortos293/Lichii](https://github.com/zortos293/Lichii)** and Eglantine/Eden: Ampere shader lowering and the reference for comparing draws.
- **[Ryujinx](https://github.com/Ryujinx/Ryujinx)**: the shader translator.
- **[kinnay/zbic](https://github.com/kinnay/zbic)**: executable decompression, downloaded during installation.

The full list is in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## License

[GPL-3.0](LICENSE), like the original project. Third-party parts keep their own licenses, listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Fan project, not affiliated with Nintendo. The Legend of Zelda and Ocarina of Time are trademarks of Nintendo.
