#!/bin/sh
# Abre o Ocarina Recomp no Linux (o equivalente de jogar-ocarina.ps1).
#
#   instalador/jogar-ocarina.sh [--seconds S] [--shot PNG] [outros argumentos do ocarina]
#
# Os argumentos extras vao para o jogo: veja `build/oot111/ocarina --help` para as modos de teste.
# A saida e os erros de cada partida vao para ultima-partida.log e ultima-partida-erros.log.

raiz=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
pasta="$raiz/build/oot111"

[ -x "$pasta/ocarina" ] || { echo "nao ha $pasta/ocarina: faca a compilacao (docs/build-by-hand-linux.md)" >&2; exit 1; }

# As mesmas variaveis do atalho do Windows.
TOTK_GPL=0               # bindless set 2 + an allocated vertex set in an independent layout loses the device
TOTK_ASYNC_PREEMPT=0
DKB_SKIP_CS="3bdfe449de832903,909139c13b510f1f,753f8ab880fe7923,c968ad44272dcbb4,785a41d2df6dc095,db8c39bdb420e068,dec1feb3c7fa967a,09931d0c57c6b67f,13cab66ee383c4f4,3f6f2b1d671badcd"   # the game's upscaler: giant shaders that take many minutes to compile
TOTK_PROFILE_DIR="$raiz/perfil"
case "$(lspci -mm 2>/dev/null | grep -i 'vga\|3d\|display')" in
    *[Nn][Vv][Ii][Dd][Ii][Aa]*) TOTK_GPU_NAME=NVIDIA ;;
esac
export TOTK_GPL TOTK_ASYNC_PREEMPT DKB_SKIP_CS TOTK_PROFILE_DIR TOTK_GPU_NAME

# As sondas de janela abrem uma janela: numa sessao SSH, aponte para o display da sessao grafica.
if [ -z "$DISPLAY" ] && [ -z "$WAYLAND_DISPLAY" ]; then
    export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
    export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-1}
    export SDL_VIDEODRIVER=${SDL_VIDEODRIVER:-wayland}
    echo "aviso: sem DISPLAY no ambiente; tentando Wayland em $XDG_RUNTIME_DIR" >&2
fi

mkdir -p "$TOTK_PROFILE_DIR"

# O jogo pede algumas GB de VRAM local ao dispositivo: a primeira coisa a falhar e o pool fisico de 320 MB
# ("device-local allocation failed"), e o jogo morre em seguida. Avisa antes, em vez de deixar parecer bug.
free_mib=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits 2>/dev/null | head -1)
if [ -n "$free_mib" ] && [ "$free_mib" -lt 2048 ]; then
    echo "aviso: a placa de video so tem ${free_mib} MiB livres; o jogo precisa de algumas GB de VRAM." >&2
    echo "       feche o que estiver segurando a memoria (nvidia-smi mostra os processos) e abra de novo." >&2
fi

cd "$pasta" || exit 1
echo "abrindo $pasta/ocarina (perfil em $TOTK_PROFILE_DIR)"
exec ./ocarina "$@" > "$raiz/ultima-partida.log" 2> "$raiz/ultima-partida-erros.log"
