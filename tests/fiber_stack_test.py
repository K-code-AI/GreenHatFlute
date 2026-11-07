"""plat_stack_base() and the host setjmp/longjmp mechanism on fibers, with no game, window or GPU.

Run: python tests/fiber_stack_test.py [--cc /path/to/clang]

The guest's decoders and parsers leave through longjmp as ordinary flow, so a host that cannot take it stops the game
after it has already loaded in. This proves the mechanism holds here, where the fibers run on our own mmap'd stacks
that the platform layer tracks.
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cc', default=os.environ.get('CC') or shutil.which('clang'))
    args = parser.parse_args()
    if not args.cc:
        parser.error('pass --cc with the project Clang executable')
    out = ROOT / 'build' / 'tests' / 'fiber-stack'
    out.mkdir(parents=True, exist_ok=True)
    exe = out / 'fiber_stack'
    # -no-pie and -march=x86-64-v3 as the runtime build uses (tools/build_game.py RT_FLAGS), so the canary and the
    # control-flow hardening around the stack switch are the ones the game actually runs under.
    cmd = [args.cc, '-no-pie', '-std=gnu11', '-O2', '-g', '-Wall', '-fno-strict-aliasing', '-march=x86-64-v3',
           '-I', str(ROOT / 'runtime'), str(ROOT / 'tests/fiber_stack.c'),
           str(ROOT / 'runtime/platform/linux.c'), '-pthread', '-o', str(exe)]
    subprocess.run(cmd, check=True)
    return subprocess.run([str(exe)], timeout=30).returncode


if __name__ == '__main__':
    raise SystemExit(main())
