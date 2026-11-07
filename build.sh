#!/bin/sh
# Builds GreenHatFlute on Linux from your own copy of the game.
#
#   ./build.sh --check --game /path/your-game.nup     report what is missing; change nothing
#   ./build.sh --game /path/your-game.nup             build it
#   ./build.sh --game /path/your-game.nup --dry-run   print every command, run none
#
# Every step is skipped when its output is already there, so running this again after it stopped continues from where
# it stopped. The steps and their order are the ones in docs/build-by-hand.md; keep the two in step.
#
# Nothing here needs root, and your game file is only ever read.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
game=''
dry=0
check_only=0
version=oot111
# The 1.11 executable of Ocarina of Time 1.1.1, uncompressed (docs/build-by-hand.md step 3).
HASH_111=f90499eeb596d67c730fac9b7e247b3a46d51d6f334c767aef071c9a783cccef
ZBIC=11b08f2712264bbed731545085cbd9702096ceb7

say()  { printf '\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

run() {
    printf '  $ %s\n' "$*"
    [ "$dry" = 1 ] && return 0
    "$@"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --check)   check_only=1 ;;
        --game)    game=${2:-}; shift ;;
        --dry-run) dry=1 ;;
        --help|-h) awk 'NR > 1 { if ($0 !~ /^#/) exit; sub(/^# ?/, ""); print }' "$0"; exit 0 ;;
        *)         die "unknown argument '$1' (try --help)" ;;
    esac
    shift
done

[ -n "$game" ] || die "say --game /path/your-game.nup (your own copy: this repository does not carry the game)"
[ -e "$game" ] || die "no such game file: $game"
game=$(CDPATH= cd -- "$(dirname -- "$game")" && pwd)/$(basename -- "$game")

# A folder of locally built libraries (libvpx, dav1d) is picked up if present, as in step 1 of the guide.
deps="$root/toolchain/deps-linux"
if [ -d "$deps" ]; then
    CPATH=${CPATH:-$deps/include}
    LIBRARY_PATH=${LIBRARY_PATH:-$deps/lib}
    export CPATH LIBRARY_PATH
fi

# ---- what is needed ---------------------------------------------------------------------------------------
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM
missing=''
need() {   # need <program> [<package hint>]
    command -v "$1" >/dev/null 2>&1 || missing="$missing
  $1${2:+   (package: $2)}"
}
need clang clang
need ninja ninja
need git git
need python3 python
command -v dotnet >/dev/null 2>&1 || missing="$missing
  dotnet   (only the shader translator: curl -sSL https://dot.net/v1/dotnet-install.sh | bash /dev/stdin --channel 10.0)"
# Headers and libraries are probed by compiling, so CPATH and LIBRARY_PATH are honoured exactly as the build honours
# them, and a library built into toolchain/deps-linux counts the same as a system one.
probe_header() {
    printf '#include <%s>\nint main(void){return 0;}\n' "$1" | clang -x c - -o "$tmp/a.out" 2>/dev/null
}
probe_header SDL3/SDL.h || missing="$missing
  SDL3/SDL.h   (the SDL3 development package)"
probe_header vulkan/vulkan.h || missing="$missing
  vulkan/vulkan.h   (the Vulkan development package)"
probe_link() {
    printf 'int main(void){return 0;}\n' | clang -x c - -o "$tmp/b.out" -l"$1" 2>/dev/null
}
probe_link vpx || warn "libvpx is not on the system and not in $deps: the movies will not decode (step 1 of the guide builds it)"
probe_link dav1d || warn "libdav1d is not on the system: the game's AV1 movies will not decode"

if [ -n "$missing" ]; then
    printf 'missing:%s\n' "$missing"
    [ "$check_only" = 1 ] && exit 1
    die "install those and run this again"
fi

ram_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
[ "$ram_kb" -ge 15000000 ] || warn "$(printf '%d' $((ram_kb / 1024))) MiB of RAM; 16 GB is recommended"
free_gb=$(df -Pk "$root" | awk 'NR==2 {printf "%d", $4/1048576}')
[ "$free_gb" -ge 60 ] || warn "$free_gb GB free here; the build wants about 60 GB"

say "tools present; game file $game"
if [ "$check_only" = 1 ]; then
    say "nothing changed (--check)"
    exit 0
fi

cd "$root"

# ---- 2. the Python environment ----------------------------------------------------------------------------
if [ ! -x .venv/bin/python ]; then
    say "python environment"
    run python3 -m venv .venv
    run .venv/bin/pip install -q -r tools/requirements-build.txt capstone
else
    say "python environment: already there"
fi

# ---- 3. the executable ------------------------------------------------------------------------------------
if [ -f build/exefs/main ]; then
    got=$(sha256sum build/exefs/main | cut -d' ' -f1)
else
    got=''
fi
if [ "$got" = "$HASH_111" ]; then
    say "exefs: already extracted, and it is 1.1.1"
else
    say "extracting the executable"
    run python3 tools/extract_nup.py "$game" --out build/dump --only exefs --package 0
    if [ "$dry" = 1 ]; then
        printf '  $ mkdir -p build/exefs && cp build/dump/exefs/* build/exefs/\n'
    else
        mkdir -p build/exefs && cp build/dump/exefs/* build/exefs/
    fi
    got=$(sha256sum build/exefs/main 2>/dev/null | cut -d' ' -f1)
    if [ "$got" != "$HASH_111" ] && [ "$dry" = 0 ]; then
        if head -c 4 build/exefs/main | grep -q ZBIC; then
            say "main is ZBIC-compressed: decompressing"
            run git clone -q https://github.com/kinnay/zbic build/zbic
            run git -C build/zbic checkout -q "$ZBIC"
            run clang -O2 -w -Ibuild/zbic/src tools/oot/unzbic.c -o build/unzbic
            run build/unzbic build/dump/exefs/main build/exefs/main
            got=$(sha256sum build/exefs/main | cut -d' ' -f1)
        fi
    fi
fi
if [ -n "$got" ] && [ "$got" != "$HASH_111" ] && [ "$dry" = 0 ]; then
    die "build/exefs/main is not Ocarina of Time 1.1.1 (sha256 $got). Other versions do not work."
fi

# ---- 4. the shader translator -----------------------------------------------------------------------------
if [ -x build/xlate/totk_xlate ]; then
    say "shader translator: already built"
else
    say "shader translator (.NET; a few minutes the first time)"
    run .venv/bin/python tools/build_xlate.py
fi

# ---- 5. the game code -------------------------------------------------------------------------------------
if [ -f "generated/$version/functions.txt" ] || [ -d "generated/$version" ]; then
    say "generated code: already there (delete generated/$version to redo it)"
else
    say "converting the game code (about a minute on 16 cores, 1.2 GB of C)"
    run .venv/bin/python recomp/gen.py --exefs build/exefs --out "generated/$version" --modules main,sdk,subsdk0
    run .venv/bin/python tools/oot/patch_generated.py "generated/$version"
fi

# ---- 6. the RomFS -----------------------------------------------------------------------------------------
if [ -f build/romfs/romfs.bin ]; then
    say "romfs: already packed"
else
    say "packing the RomFS (26 GB; a couple of minutes, and it deletes the extracted copy as it goes)"
    run python3 tools/extract_nup.py "$game" --out build/dump --only romfs --package 0
    run python3 tools/pack_romfs.py --dir build/dump/romfs --out build/romfs --consume
    run rm -rf build/dump
fi

# ---- 7. the game ------------------------------------------------------------------------------------------
say "compiling and linking"
run .venv/bin/python tools/build_game.py --version "$version" --gen "generated/$version" --out "build/$version" \
    --expected "tools/data/expected-$version.json" --exefs build/exefs --romfs build/romfs --jobs "$(nproc)"
if [ -f play/totk.ini ] && [ ! -f "build/$version/totk.ini" ]; then
    run cp play/totk.ini "build/$version/totk.ini"
fi

say "done"
printf 'play it with:  play/run.sh\n'
printf 'or install a menu entry:  python tools/install_linux.py\n'
