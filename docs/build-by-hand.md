# Build by hand

Every step, one command at a time, on a Linux host: the libraries, the linker and the shader translator. [`build.sh`](../build.sh)
runs these same steps for you; keep the two in step when you change a command. Verified on Gentoo (kernel 6.18, clang 22,
.NET 10.0.403), x86-64 AVX2, NVIDIA RTX 5070 with driver 615.78.08, Ocarina of Time 1.1.1 from a `.nup`.

You need your own copy of the game at **version 1.1.1**, 16 GB of RAM and about 60 GB free. The game wants a few GB of
free VRAM: with other programs holding the card, `vk: physical pool ... device-local allocation failed` comes first and
the run is slow. Check `nvidia-smi` / `radeontop` before blaming the build.

## 1. Install the tools

```sh
# Arch
pacman -S --needed clang lld ninja make cmake meson nasm pkgconf sdl3 opus dav1d vulkan-headers \
    vulkan-icd-loader vulkan-validation-layers shaderc spirv-tools git
```

On other distributions install the same packages under their own names. Two are usually missing:

- **libvpx** (the movie decoder, `runtime/ov_movie.c`). Not packaged on every system; build it into a folder of your
  own instead of the system's:

  ```sh
  tar xzf libvpx-1.15.1.tar.gz && cd libvpx-1.15.1
  ./configure --prefix="$PWD/../greenhatflute-deps" --enable-static --disable-shared \
      --disable-examples --disable-tools --disable-unit-tests --enable-multithread
  make -j"$(nproc)" && make install
  ```

- **lld**. `build_game.py` links with `-fuse-ld=lld`; without it it now prints a line and uses the system `ld`, which
  takes the same flags a little more slowly.

`dav1d` (the AV1 path of `runtime/ov_codec.c`) is packaged almost everywhere; if yours is not, build it the same way
with meson. Vulkan Memory Allocator needs nothing: `build_game.py` fetches the pinned `vk_mem_alloc.h` into
`toolchain/vma/` on first use.

Keep the folder you built libraries in for every later step, so clang sees both their headers and their archives:

```sh
export CPATH=$PWD/toolchain/deps-linux/include LIBRARY_PATH=$PWD/toolchain/deps-linux/lib
```

(`CPATH` and `LIBRARY_PATH` are read by clang itself, so they reach every compile and the link without touching the
build scripts. `--deps DIR` does the same for a release build, and also makes Opus and zstd static.)

**.NET** (only the shader translator needs it). Use your package manager or the official script, which needs no root:

```sh
curl -sSL https://dot.net/v1/dotnet-install.sh | bash /dev/stdin --channel 10.0 --install-dir "$HOME/.dotnet"
export PATH=$HOME/.dotnet:$PATH
```

## 2. Get the code and the Python environment

```sh
git clone https://github.com/K-code-AI/GreenHatFlute GreenHatFlute
cd GreenHatFlute
python3 -m venv .venv
.venv/bin/pip install -r tools/requirements-build.txt   # or just: numpy lz4 zstandard
```

The extraction here uses `tools/extract_nup.py`, which needs only the standard library of Python 3.14 (`zstd` also
works through the `zstd` program).

## 3. Extract the game's executable

```sh
python3 tools/extract_nup.py oot.nup --list          # expect "1 package(s)" for a standalone update
python3 tools/extract_nup.py oot.nup --out build/dump --only exefs --package 0
mkdir -p build/exefs && cp build/dump/exefs/* build/exefs/
sha256sum build/exefs/main
```

The right result is `f90499eeb596d67c730fac9b7e247b3a46d51d6f334c767aef071c9a783cccef`. If it differs, `main` is
ZBIC-compressed (its first segment starts with `ZBIC`); decompress it:

```sh
git clone https://github.com/kinnay/zbic build/zbic
git -C build/zbic checkout 11b08f2712264bbed731545085cbd9702096ceb7
clang -O2 -w -Ibuild/zbic/src tools/oot/unzbic.c -o build/unzbic
build/unzbic build/dump/exefs/main build/exefs/main
sha256sum build/exefs/main
```

`unzbic.c` builds unmodified on Linux. If the hash still differs, the game is not 1.1.1.

## 4. Build the shader translator

```sh
python tools/build_xlate.py
```

On Linux this publishes `build/xlate/totk_xlate` for `linux-x64`; NativeAOT links it with the system clang and needs no
MSVC. The 34 selected patches apply cleanly.

## 5. Convert the game code

```sh
.venv/bin/python recomp/gen.py --exefs build/exefs --out generated/oot111 --modules main,sdk,subsdk0
.venv/bin/python tools/oot/patch_generated.py generated/oot111
```

About a minute on 16 cores: 297 414 functions, 1.2 GB of C.

## 6. Prepare the game files

The RomFS is 26 GB extracted and 26 GB as an image, so `--consume` (which deletes each file as it enters the image) is
worth using on the copy under `build/dump`:

```sh
python3 tools/extract_nup.py oot.nup --out build/dump --only romfs --package 0
python3 tools/pack_romfs.py --dir build/dump/romfs --out build/romfs --consume
rm -rf build/dump
```

## 7. Build the game

```sh
.venv/bin/python tools/build_game.py --version oot111 --gen generated/oot111 --out build/oot111 \
    --expected tools/data/expected-oot111.json --exefs build/exefs --romfs build/romfs --jobs "$(nproc)"
cp play/totk.ini build/oot111/totk.ini
```

The compile takes about 7 minutes on 16 cores and links a 305 MB ELF (`build/oot111/GreenHatFlute`).

## 8. Check and play

```sh
build/oot111/GreenHatFlute --selftest   # layout, dispatch table, host functions: no game files needed
play/run.sh                              # the settings this port is tuned with
```

The window works on **Wayland and X11** alike: SDL3 picks the session's own back end and logs which one it took
(`gfx: SDL 3.4.18, video driver wayland`). Nothing chooses a driver for you, so an existing `DISPLAY` wins; set
`SDL_VIDEODRIVER=wayland` or `=x11` to decide.

The probes open a window, so from an SSH session they need the desktop session's display: on Wayland
`XDG_RUNTIME_DIR=/run/user/$(id -u) WAYLAND_DISPLAY=wayland-1 SDL_VIDEODRIVER=wayland`, on X11 `DISPLAY=:0`.

## 9. Install it as a desktop app (optional)

```sh
python tools/install_linux.py            # menu entry, icon and greenhatflute on PATH
```

It writes only under XDG paths (`~/.local/share`, `~/.local/bin`), so it needs no root and touches nothing in `/usr`.
The icon comes from the PNG sizes already inside `runtime/totk.ico`; the menu entry is `play/greenhatflute.desktop`
with the launcher's path filled in. `--dry-run` shows what would be written, `--uninstall` removes it.

Saves, cache and the log live in **`~/.local/share/greenhatflute`** (or `$XDG_DATA_HOME/greenhatflute`), not next to
the executable, so the build folder can be moved or deleted without losing a game. `TOTK_PROFILE_DIR` or `--profile DIR`
still overrides that; a `profile` folder next to the executable means a portable copy and wins.

## What differs from the upstream Windows port

| | Linux |
|---|---|
| Executable | `build/oot111/GreenHatFlute`, an ELF; `runtime/*_sdl.*` and `runtime/platform/linux.c` replace the `*_win.*` files, `platform/win32.c` and `totk.rc` |
| Libraries | system Vulkan, SDL3, Opus, zstd and dav1d; libvpx from your own folder; `libstdc++` static, `$ORIGIN` in the rpath |
| Linker | `-no-pie` (the function tables need no load-time relocation) and lld when present |
| CPU-visible pools | shadow storage by default (`runtime/vk_memory.c`): a host-visible copy per pool instead of importing the guest pages; see [building.md](building.md), "Linux" |
| Shader translator | `totk_xlate` for `linux-x64`, NativeAOT over the system clang |

## Common problems

| Message | What to do |
|---|---|
| `vpx/vp8dx.h: file not found` | `CPATH` is not set to the folder you built libvpx in (step 1) |
| `undefined reference to dav1d_*` | install dav1d, or point `LIBRARY_PATH` at one you built |
| `invalid linker name in argument '-fuse-ld=lld'` | an old clang without lld: install lld, or update `build_game.py` (it now falls back to the system `ld`) |
| `device-local allocation failed (-2)` | the card's free VRAM is smaller than the game's pools: close what holds it and check with `nvidia-smi`. The run survives on host memory (the log says `keeps the game's storage`) but slowly |
| `gpu 0 skipped: no graphics+compute+present queue family` | no display for the probe: see step 8 |

Do not share `GreenHatFlute`, `generated/` or `build/`: they come from your game.
