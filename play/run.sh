#!/bin/sh
# Opens GreenHatFlute.
#
#   play/run.sh [--seconds S] [--shot PNG] [other GreenHatFlute arguments]
#
# Extra arguments go to the game: see `build/oot111/GreenHatFlute --help` for the test modes.
# A run's output and errors go to last-run.log and last-run-errors.log.
#
# The window works on both Wayland and X11: SDL3 picks the session's own back end, so nothing here chooses one.
# Saves live in ~/.local/share/greenhatflute (or $XDG_DATA_HOME/greenhatflute), which the game picks by itself, so
# this script does not set TOTK_PROFILE_DIR. Set it if you want the saves somewhere else.

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
builddir="$root/build/oot111"

[ -x "$builddir/GreenHatFlute" ] || { echo "no $builddir/GreenHatFlute: run the build first (docs/build-by-hand.md)" >&2; exit 1; }

# The settings this port is tuned with.
TOTK_GPL=0               # bindless set 2 + an allocated vertex set in an independent layout loses the device
TOTK_ASYNC_PREEMPT=0
DKB_SKIP_CS="3bdfe449de832903,909139c13b510f1f,753f8ab880fe7923,c968ad44272dcbb4,785a41d2df6dc095,db8c39bdb420e068,dec1feb3c7fa967a,09931d0c57c6b67f,13cab66ee383c4f4,3f6f2b1d671badcd"   # the game's upscaler: giant shaders that take many minutes to compile
case "$(lspci -mm 2>/dev/null | grep -i 'vga\|3d\|display')" in
    *[Nn][Vv][Ii][Dd][Ii][Aa]*) TOTK_GPU_NAME=NVIDIA ;;
esac
export TOTK_GPL TOTK_ASYNC_PREEMPT DKB_SKIP_CS TOTK_GPU_NAME

# The probes and --shot open a window; over SSH, point at the graphical session's display.
if [ -z "$DISPLAY" ] && [ -z "$WAYLAND_DISPLAY" ]; then
    export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
    export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-1}
    echo "note: no DISPLAY in the environment; trying Wayland on $XDG_RUNTIME_DIR" >&2
    echo "      for an X11 session instead: DISPLAY=:0 $0 ..." >&2
fi

cd "$builddir" || exit 1

# The game asks the card for a few GB of device-local memory. With the card full, the first thing to fail is the
# 320 MB physical pool ("device-local allocation failed"); the run then survives on host memory but slowly. Warning
# first beats making it look like a bug.
free_mib=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits 2>/dev/null | head -1)
if [ -n "$free_mib" ] && [ "$free_mib" -lt 2048 ]; then
    echo "warning: the graphics card has only ${free_mib} MiB free; the game wants a few GB of VRAM." >&2
    echo "         close what is holding it (nvidia-smi lists the processes) and open it again." >&2
fi

echo "opening $builddir/GreenHatFlute"
exec ./GreenHatFlute "$@" > "$root/last-run.log" 2> "$root/last-run-errors.log"
