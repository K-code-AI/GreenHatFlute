# Building from source

Linux on x86-64 with AVX2, and a GPU with Vulkan 1.3 and `VK_EXT_external_memory_host` (NVIDIA or RADV). Allow about
60 GB for the work folder: extraction wants about 55 GB free while it runs and keeps about 35 GB afterwards.

The short way is [`build.sh`](../build.sh) at the repository root; the long way, one command at a time, is
[build-by-hand.md](build-by-hand.md). This page is the reference around them: the toolchain, how memory works on this
port, and the checks to run before a commit.

## Toolchain

Verified on Gentoo (kernel 6.18, clang 22, .NET 10.0.403), x86-64 AVX2, NVIDIA RTX 5070. Newer patch releases are fine.

| Tool | Version | Install | Used for |
|---|---|---|---|
| clang | 22 | your package manager | compiling the generated C and the runtime |
| lld | any | optional | `build_game.py` links with `-fuse-ld=lld`; without it it prints a line and uses the system `ld` |
| ninja, make, cmake, meson, nasm, pkgconf | any | your package manager | the build and the dependency builds |
| .NET SDK | 10.0 | `curl -sSL https://dot.net/v1/dotnet-install.sh \| bash /dev/stdin --channel 10.0` (no root) | the shader translator (`totk_xlate`) |
| SDL3, Vulkan, opus, zstd, dav1d | any | your package manager | window and input, graphics, audio, movies |
| libvpx | 1.15 | often not packaged: build it into `toolchain/deps-linux` | the movie decoder (`runtime/ov_movie.c`) |
| spirv-tools, shaderc | any | your package manager | validating and compiling shaders |

```sh
# Arch names; other distributions have the same packages under other names
pacman -S --needed clang lld ninja make cmake meson nasm pkgconf sdl3 opus dav1d zstd vulkan-headers \
    vulkan-icd-loader vulkan-validation-layers shaderc spirv-tools git
```

`ffmpeg` is never linked; the movies go through libvpx and dav1d.

A folder of libraries you built yourself is handed to clang with two variables, so they reach every compile and the
link without touching the build scripts:

```sh
export CPATH=$PWD/toolchain/deps-linux/include LIBRARY_PATH=$PWD/toolchain/deps-linux/lib
```

Vulkan Memory Allocator needs nothing: `build_game.py` fetches the pinned `vk_mem_alloc.h` (3.4.0) into
`toolchain/vma/` on first use and checks its hash.

## Build

From the repository root. This fork builds **Ocarina of Time 1.1.1**, whose version name is `oot111`; the tools take it
as `--version oot111`.

1. Python environment (once):

   ```sh
   python3 -m venv .venv
   .venv/bin/pip install -r tools/requirements-build.txt      # numpy, lz4, zstandard
   ```

2. Extract the game's executable from your own `.nup`, decompressing it if it is ZBIC-compressed, and check its
   SHA-256 against `tools/data/expected-oot111.json`. Step 3 of [build-by-hand.md](build-by-hand.md) has the commands.

3. Shader translator (once; no game files). This publishes `build/xlate/totk_xlate` for `linux-x64`; NativeAOT links
   it with the system clang:

   ```sh
   .venv/bin/python tools/build_xlate.py
   ```

4. Lift the modules to C, then compile and link `build/oot111/ocarina`:

   ```sh
   .venv/bin/python recomp/gen.py --exefs build/exefs --out generated/oot111 --modules main,sdk,subsdk0
   .venv/bin/python tools/oot/patch_generated.py generated/oot111
   .venv/bin/python tools/build_game.py --version oot111 --gen generated/oot111 --out build/oot111 \
       --expected tools/data/expected-oot111.json --exefs build/exefs --romfs build/romfs --jobs "$(nproc)"
   ```

   Lifting takes about a minute on 16 cores (297 414 functions, 1.2 GB of C); the compile about 7 minutes cold, and
   later builds recompile only what changed. A compiler cache in front of clang shortens it further: with `SCCACHE` set
   to an sccache executable, `build_game.py` writes it into the ninja file ahead of `cc`.

5. Prepare the RomFS image (26 GB) — step 6 of the guide.

`build_game.py` takes clang, lld and Ninja from PATH (or the ones in `<dir>/bin` with `--toolchain <dir>`) and links
against the system libraries, with `libstdc++` static and an `$ORIGIN` rpath so a `libSDL3.so.0` next to the program
comes before the system's.

Settings live in `totk.ini` next to the program ([totk.ini.example](../totk.ini.example) lists them). Saves go to
`~/.local/share/greenhatflute` (`build_game.py --profile` or `TOTK_PROFILE_DIR` changes it).

### Portable folder

`.venv/bin/python tools/package_build.py --version oot111` writes `build/oot111-portable`, which runs on another of
your machines without Python or .NET. `romfs.bin` stays out unless you pass `--with-romfs`; otherwise put it in
`romfs/` next to the program or point `TOTK_ROMFS` at its folder. Run `ocarina --prepare-shaders` once in the copied
folder. The folder holds code and data derived from your game: for your own machines only.

## Memory on this port

Upstream's Windows port lets the GPU import guest memory and uses `GetWriteWatch` to track the CPU's writes to it. On
Linux, re-protecting imported memory invalidates the driver's userptr buffer on every submit (about 1.3 ms per 16 MiB
on amdgpu), and importing pins the pages, which drops their write protection. Each CPU-visible pool therefore gets a
host-visible copy — shadow storage, `runtime/vk_memory.c`: the pages the CPU wrote go in before each submit, and the
GPU's writes come back at its fence. In play that costs about 0.2 ms a frame and doubles the memory of those pools
(about 1.1 GB). `TOTK_SHADOW=1` turns it on explicitly.

When the card cannot give a pool device-local memory, the log says `physical pool of ... device-local allocation failed
(-2)` and the pool keeps the game's storage in host memory instead. The run continues and renders; it is slower, and
the log shows textures being released under pressure. Check free VRAM with `nvidia-smi` before blaming the build.

GPUs without native ASTC send those textures through the compute decoder (`runtime/vk_astc.c`, `TOTK_ASTC`).

Requirements:

- A Vulkan 1.3 driver with `VK_EXT_external_memory_host` (NVIDIA, RADV).
- Linux 6.7 or later for the write watch, which uses userfaultfd write protection with `PAGEMAP_SCAN`. Older kernels
  refuse it at run time and the runtime falls back.

## Checks

Before a commit:

- `python tools/check_content.py --staged`: nothing game-derived is staged. CI runs the same check;
  `git config core.hooksPath .githooks` runs it before each local commit.
- `build/oot111/ocarina --selftest`: layout, dispatch table and host-function registry, without game files.

The lifter (`recomp/`) and the CPU headers (`runtime/cpu.h`, `runtime/simd.h`) are checked against Unicorn. Every lifter
change passes these, all run with `.venv`:

| Test | Checks | Game files |
|---|---|---|
| `tests/diff/lift.py` | instructions sampled from the extracted modules; `--coverage` lists every word the lifter rejects or traps | yes |
| `tests/diff/simd.py` | the whole FP/SIMD encoding space | no |
| `tests/diff/atomic.py` | exclusive load/store sequences and ARMv8.1 atomics | no |
| `tests/diff/func.py` | whole functions as the generator emits them, loops, jump tables and calls included | yes |
| `tests/flags_check.py` | the function-local flag helpers of `runtime/cpu.h` against its packed ones | no |
| `tests/excl_mt.py` | the exclusive monitor helpers under contention and ABA, on several threads | no |
| `tests/jumptables_check.py` | `recomp/jumptables.py` against a Unicorn oracle; must report 0 disagreements | yes |

Many tests under `tests/` are harnesses that need their tools named: pass `--cc`, `--deps`, `--xlate` or
`--spirv-val` (or set `TOTK_TOOLCHAIN`). Run them with `.venv/bin/python`, and set `TOTK_INPUT=none` so the probes do
not take the keyboard.

Runtime probes, each a mode of `ocarina` (the list is at the top of `runtime/main.c`): `--probe-kernel`,
`--probe-vkexec`, `--probe-nvn-tex` and `--probe-shader` cover most runtime changes. The probes open a window, so from
an SSH session they need the desktop session's display, or they stop at `gpu 0 skipped: no
graphics+compute+present queue family`: on Wayland `XDG_RUNTIME_DIR=/run/user/$(id -u)
WAYLAND_DISPLAY=wayland-1 SDL_VIDEODRIVER=wayland`, on X11 `DISPLAY=:0`.

Note that several probes (`--probe-loader`, `--probe-ipc`, `--probe-nvn`) carry expectations pinned to *Tears of the
Kingdom* addresses, not Ocarina's, and report failures here that are not regressions.

## Reverse engineering (optional)

- Ghidra 12.1.2 with Adubbz's Ghidra-Switch-Loader in `toolchain/ghidra/` (JDK 21) opens the game modules (NSO).
- `tools/fetch_refs.sh` clones the upstream projects this port builds on into `refs/`, read-only.
