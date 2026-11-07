# Architecture

How the Switch build of the game becomes a native Linux x86-64 program. What this project builds on is listed under
Credits in the [README](../README.md) and in [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).

## Pipeline

### 1. Input

- **This project builds Ocarina of Time on Switch 2**: title id `0400486024DEC000`, display version 1.1.1, `--version oot111`.
- Input is one `.nup` — the standalone update, with ExeFS and RomFS as loose trees. `tools/extract_nup.py` reads the
  container (an independent reader of Eglantine's `nup_container.cpp` layout), checks every file against the SHA-256 in
  it, and writes the two folders. `--package 0` picks the update.
- `main` arrives ZBIC-compressed; `tools/oot/unzbic.c` decompresses it (kinnay/zbic, fetched during the build).
- Verification: `tools/data/expected-oot111.json` holds the SHA-256 of `main`, `main.npdm`, `rtld`, `sdk` and
  `subsdk0`; `tools/build_game.py` refuses an ExeFS that does not match. The RomFS is repacked by `tools/pack_romfs.py`.
- No code patch sets: `recomp/gen.py` runs without `--patches` for `oot111`.
- Unused by this build but still in the tree: the *Tears of the Kingdom* version tables
  and patch sets (`recomp/patches-v111.txt`, `-v121.txt`, `-v143.txt`), the NSP/XCI extractor with hactool and its BKTR
  patches (`tools/extract.py`, `tools/build_hactool.py`) and `tools/data/expected-v*.json`. They stay because the runtime
  still carries the behaviour those versions were measured against; `--version v121` and `v143` build that game, not this one.

### 2. CPU: lift ARM64 to C

- Modules: `main`, `sdk`, `subsdk0`. `rtld` is dropped and the host does the linking.
- The decoder is hand-written (`lifter.py`), with the NEON and FP/SIMD lowering in `simd_c.py` and `simd.h`. Output: one C function per guest function, direct calls for `BL`, an address-keyed table for indirect branches.
- Scaled up for a game this size:
  - generator runs in parallel processes, with bounded memory per worker;
  - jump tables resolved by our own symbolic pass instead of Unicorn, which keeps GPL code out of the shipped generator;
  - `LDXP`/`STXP` (128-bit exclusive pairs) supported;
  - no 64 MB limit on `main`; `subsdk*` loaded;
  - NZCV and the six most used general registers of each function kept in C locals instead of the `Cpu`
    (`recomp/flags.py`, `recomp/regs.py`): registers are stored back where they changed, before calls, SVCs and
    exits, and reloaded after them. A call reloads only X0-X18 and X30, as AAPCS64 has the callee preserve X19-X29 and
    SP; `gen.py --no-callee-saved-trust` reloads those too.
- Coverage oracle: the list of every site where game code touches the OS (SVCs, TLS reads, counter reads, `x18`, exclusive windows, jump tables): 68,968 sites in 1.4.3 `main`. The lifter must handle every one.
- Memory: guest address equals host address, all below 2^39 (IPC encodes 39-bit addresses). The heap, stacks and the alias region are reserved write-watched (`plat_mem_reserve`), so the graphics back end can ask which pages the CPU wrote since the last upload (`runtime/memory.c`).
- Indirect branches go through `rt_dispatch` (`runtime/dispatch.c`), which looks the target up in the address table and tail-calls it.
- Testing: a differential harness, every lifted instruction class checked against Unicorn (test-only, never linked into the game).

### 3. Host

- The host layer is portable C: threads and synchronisation, IPC, memory services, fs/RomFS, time, account, applet, audio renderer and effects. Its OS half is Linux: the platform layer, pthreads, SDL3 for the window and input, libopus for voice.
- SDK boundary at the `nn::*` function level. Only `audren:u` and `sm:` are real IPC services.
- Window, keyboard and mouse: SDL3 (`gfx_window_sdl.c`, `input_sdl.c`), which takes the session's own back end, Wayland or X11. Gamepad and audio output: SDL3. Voice: libopus (BSD). Movies: the SDK's `movie::Decoder` is replaced by a host decoder over libvpx and dav1d (BSD, static; `runtime/ov_movie.c`, `runtime/ov_codec.c`), because FFmpeg is a GPL build.
- zstd: most RomFS files of 1.4.3 are zstd frames. The patch set `zstd` sends the game's two decoder entry points to
  libzstd on the host (`ov_zstd.c`, `GHF_ZSTD_NATIVE`); the lifted decoder took almost three times as long.
- Settings and menu: every key with its default is in one table (`cfg.c`), read from `greenhatflute.ini` and `GHF_*`
  variables and written back when the in-game menu changes it. The menu and the performance overlay are Dear ImGui,
  drawn into the swapchain image (`runtime/ui/`); their text is in `ui_text.c` (English, Russian).
- OS calls the host makes go through `runtime/platform/` (`platform.h`, `linux.c`), so another host adds one file instead of touching the rest. The split is not finished: `tools/check_platform.py` fails when a runtime file outside it reaches for the Win32 API.

#### Threads and cores

Every guest thread is a host thread. The game assumes Horizon's scheduler: three application cores, a thread runs only on a core in its affinity mask, and a higher-priority thread takes a core from a lower-priority one. The game keeps per-core data without locks and relies on that, so the host models it (`runtime/kernel.c`):

- Three virtual cores. A guest thread runs guest code only while it holds a core; the others wait in a priority-ordered list.
- Preemption. When a waiting thread has a better priority than a holder on a core it may use, exactly one holder is flagged. The holder checks the flag at its next SVC and at every indirect call (`rt_dispatch`: two loads when nobody waits), checks again under the kernel lock that a better thread still waits, and only then hands its core over. Checking only at SVCs left a better thread waiting up to 26 ms.
- Asynchronous preemption (on unless `GHF_ASYNC_PREEMPT=0`). Game code can run for
  milliseconds with neither (`GHF_CORE_DIAG=1` measures it): a waiter that has spun 250 us suspends the holder and,
  if its host rip is in lifted code at host depth 0 (not inside a host call or SVC), moves it to `kern_ap_stub`, which
  saves the volatile registers and gives the core up there. A holder of a guest mutex counts at the priority of its
  best waiter, and one inside an SDK spin lock (TLR+0x100 `disable_count`) is not preempted: its interrupt flag is set
  and the switch happens at SVC 0x36. `GHF_ASYNC_PREEMPT=2` keeps those two without interrupting. The interruption is a
  real-time signal handshake (`runtime/platform/linux.c`): the handler reports where the thread was, and the caller
  sends it on to the core-handoff stub through its own return context.
- Host work gives the core back. Queue submits, presents, GPU waits, shader translation, `nn::fs` calls and NVN memory pool setup run without a core (`NVN_BLOCKING`, `kern_core_away`), as the Switch blocks those threads in IPC, so a thread blocked in the driver or on a file does not hold up guest threads.
- Spin waits. Loops that only another thread can end (857 in 1.4.3, 864 in 1.2.1, found by `tools/spin_waits.py`) send
  their back-edges through `rt_spin_gate`, which pauses the core once per pass and hands it to a
  waiter after 50 us of polling (`GHF_SPIN`, `GHF_SPIN_HANDOFF_US`).
- `GHF_FREE_CORES=1` turns the gate off, for experiments.

### 4. Graphics

- NVN front end (`nvn_api_*.c`, `nvn_obj.h`, texture layout and deswizzle). The game records command buffers through it; nothing reaches the GPU until the game submits.
- Vulkan 1.3 back end. At `QueueSubmitCommands` the recorded NVN commands are replayed into Vulkan command buffers (`vk_exec*.c`).
- Memory pools. The game's CPU-visible pools are host memory, so the back end can either import them (`VK_EXT_external_memory_host`) or keep a host-visible copy of them. Importing pins the pages and drops their write protection, and re-protecting imported memory invalidates the driver's userptr buffer on every submit, so the default here is shadow storage: a host-visible copy per pool, the pages the CPU wrote uploaded before a replay and the GPU's writes read back at its fence (`GHF_SHADOW`, `vk_memory.c`). On a discrete GPU, pools bound as buffers are mirrored in device-local memory and the pages the CPU wrote (write watch, above) are uploaded before a replay; idle pool regions are made read-only so the write-watch queries skip them (`vk_memory.c`). GPU-rendered textures are written back when the CPU reads them: on a pool invalidate, on a CPU copy, and for small targets once the CPU waits for a fence (`vk_texture.c`).
- Replay thread. `GHF_REPLAY_ASYNC=1` moves the replay off the submitting thread onto a queue at most one frame behind the game; reads of GPU results wait for the newest writer instead of draining the queue (`vk_backend.c`). It is off by default because no timing has shown a gain yet.
- Recorder thread. The Vulkan calls the replay makes into its command buffer are made by a thread of their own (`vk_rec.c`): each `vkCmd*` copies its arguments into a packet of a ring and the recorder makes the calls in order; calls into other command buffers are made at once; the recorder also ends the command buffer, and the submit waits until it has. In the town on an RX 9070 the replay takes 17% less time on the submitting thread. `GHF_VK_RECORDER=0` makes every call on the submitting thread.
- Uniform snapshot. The game rewrites per-object uniform blocks on other threads soon after it submits the frame
  that reads them, while the replay still records it. At the start of a submission's replay every uniform range it
  binds from CPU-written pools is copied, and the draws bind the copy (`vk_usnap.c`); without it, late draws read another object's matrix.
- Driver data. The NVN driver keeps a per-stage constant bank (c0) that shaders read for things like point size, dispatch size and base instance. The back end fills it the way the driver does.
- Shaders: the Ryujinx translator 1.3.2 with our patches (`tools/xlate/patches/`), built with .NET 10 NativeAOT as `greenhatflute_xlate` and run as a separate process. Its SPIR-V goes to Vulkan directly. `tools/prepare_shaders.py` and `GreenHatFlute --prepare-shaders` translate and compile the variants of the shader list ahead of play (29,587 for 1.4.3); the rest are translated on first use and cached on disk.
- Pipelines: `VK_EXT_graphics_pipeline_library` where the driver has it. Shader stages are compiled ahead into libraries; a draw that meets a new state links them at once (fast link), and an optimised pipeline replaces the linked one when a background thread finishes it. Pipeline keys seen in play are saved and built at boot. A draw whose pipeline is not ready is skipped when one of its pass's targets was rendered in the previous frame, and waits otherwise, so one-shot passes are never lost; a full-screen draw is skipped as well rather than waiting (`GHF_PIPE_SKIP`); the stage libraries a waiting draw needs are built on idle workers in parallel (`GHF_PIPE_WAIT`). Without the extension, a missing pipeline is built on a worker and the draw waits or is skipped by the same rule.
- Resolution. Patch sets make the game read its output, swapchain and scene sizes from the patch page;
  `resolution.c` sets them from `output_res` and `render_scale` and grows the texture heap
  and the application pool to match. When the window is larger than the output, `vk_fsr.c` runs AMD FSR 1 (EASU,
  RCAS) on the present. An `output_res` that is not 16:9 (more than 1% off, `res_is_16x9`) also switches on the
  `aspect` patch set, which hands the output's ratio to the camera, and `romfs.c` `overlay_init` loads the
  `romfs-patches-<w>x<h>` overlay for it when it exists (`tools/make_romfs_patches.py --aspect`, laid out by
  `tools/ultrawide_layout.py`; ten sizes are laid out: 21:9 2560x1080, 3440x1440, 3840x1600, 5120x2160, 32:9
  3840x1080, 5120x1440 and 16:10 1280x800, 1680x1050, 1920x1200, 2560x1600). A wider layout moves the HUD to the
  screen's corners, a narrower one to its top and bottom edges. Other sizes get the camera of their shape and the 16:9
  HUD stretched over it. The `aspect` setting (`fit`, the default; `stretch`) decides what the present does
  when the window's shape differs from the output's: `fit` letterboxes, where a 16:9 game in a wider window used to be
  stretched.
- Occlusion queries never block the CPU; a result that is not ready counts as visible.
- ASTC textures are uploaded as they are where the device reports `textureCompressionASTC_LDR`, and decoded by a compute shader everywhere else (`vk_astc.c`, `GHF_ASTC`). The CPU decoder (`tex_astc*.c`) is the fallback and the test oracle.
- Draw state. A draw whose program, bound state and textures repeat reuses the previous draw's shaders and skips rebuilding its descriptor sets; descriptor sets are written through update templates (`vk_exec_draw.c`, `vk_pipeline.c`).
- Allocation: Vulkan Memory Allocator. Debugging: Vulkan validation layers, per-pass frame dumps (`GHF_DUMP`, `vk_dump.c`) and a flight recorder (`GHF_FLIGHT`). RenderDoc cannot capture, because it hides `VK_EXT_external_memory_host` from the application.

Maxwell behaviour the back end has to match, and the game bugs other implementations worked around: [maxwell.md](maxwell.md).

Why Vulkan rather than D3D12 or wgpu:

- The translator emits SPIR-V, which Vulkan consumes as is. D3D12 would add a SPIR-V to DXIL step; wgpu would add SPIR-V to WGSL through Naga and drop features the game uses (bindless textures, some atomics).

### 5. Toolchain

- Generated C: Clang + LLD. The generated code uses GNU extensions (`__int128`, `musttail`, vector types).
- Host code: the same Clang, C11.
- Builds: `tools/build_game.py` writes a Ninja file and runs Ninja. Every object is hashed before linking, because a faulty RAM module once flipped bits in stored objects.
- Analysis: Ghidra with the Switch loader, Capstone, `llvm-objdump`.
- Players: everyone builds the game on their own machine (`build.sh`), so no recompiled code is ever distributed.

