"""Run a build of the game headless on a copy of the user's profile with a backed-up save and scripted input.

The user's profile (build/profile) is never written: each run copies it to <exe dir>/prof-<tag>, swaps in the save
backup, and deletes the copy afterwards. The log records how many other GreenHatFlute and ninja processes ran, because
timings taken next to them are not comparable.

    python tools/run_game.py build/v143 --save <backup> --seconds 15 --tag idle --env GHF_TRACE=perf
    python tools/run_game.py build/v143 --save <backup> --script <input.txt> --seconds 18 --tag fight --quiet \
        --env GHF_TRACE=perf,sched

<backup> is a folder of build/save-backup; --script defaults to tools/input/load_save.txt (title screen to the first
save slot), and a recording made with GHF_INPUT_RECORD replays the same way.
"""
import argparse
import fcntl
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROFILE = ROOT / 'build' / 'profile'
SAVES = ROOT / 'build' / 'save-backup'
SLOTS = ROOT / 'build' / 'run-slots'
GPU_LOCK = ROOT / 'build' / '.gpu-run.lock'
MAX_RUNS = int(os.environ.get('GHF_MAX_RUNS', '3'))   # more parallel runs exhaust device memory (16 GB RX 9070)


def count(image):
    """How many processes run under the executable name `image` (their /proc comm)."""
    n = 0
    for entry in os.listdir('/proc'):
        if not entry.isdigit():
            continue
        try:
            with open(f'/proc/{entry}/comm', encoding='utf-8', errors='replace') as f:
                if f.read().strip() == image:
                    n += 1
        except OSError:
            pass   # the process exited between the listing and the read
    return n


def busy():
    return count('GreenHatFlute') + count('ninja')


def take_slot():
    """Block until one of MAX_RUNS run slots is free and hold it (a locked file) until this process exits."""
    SLOTS.mkdir(parents=True, exist_ok=True)
    while True:
        for i in range(MAX_RUNS):
            f = open(SLOTS / f'slot{i}.lock', 'a+b')
            try:
                fcntl.flock(f.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                return f
            except OSError:
                f.close()
        time.sleep(5)


def try_lock(f):
    """Take an exclusive OS lock on the open file without blocking; False if another process holds it."""
    try:
        fcntl.flock(f.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        return False
    return True


def holder_of(path):
    try:
        return path.read_text(encoding='utf-8', errors='replace').strip() or 'unknown'
    except OSError:
        return 'unknown'


def take_gpu_lock(exe_dir, poll=2.0):
    """Block until this process holds the machine-wide measured-run lock (build/.gpu-run.lock) and return the open
    file. The OS drops the lock when the process exits or dies, so a stale file never blocks. The file text names the
    holder (pid and build path) for the waiters."""
    GPU_LOCK.parent.mkdir(parents=True, exist_ok=True)
    f = open(GPU_LOCK, 'a+b')
    waiting = False
    while not try_lock(f):
        if not waiting:
            print(f'run_game: --quiet waits for the GPU run lock held by {holder_of(GPU_LOCK)}', flush=True)
            waiting = True
        time.sleep(poll)
    f.seek(0)
    f.truncate()
    f.write(f'pid {os.getpid()}, build {exe_dir}'.encode())
    f.flush()
    return f


def release_gpu_lock(f):
    if f is None:
        return
    try:
        fcntl.flock(f.fileno(), fcntl.LOCK_UN)
    except OSError:
        pass
    f.close()


def profile_copy(dest, save):
    if dest.exists():
        shutil.rmtree(dest)
    shutil.copytree(PROFILE, dest)
    if save:
        users = [d for d in (dest / 'save').iterdir() if d.is_dir()]
        if len(users) != 1:
            sys.exit(f'run_game: expected one save directory in {dest / "save"}, found {len(users)}')
        shutil.rmtree(users[0])
        shutil.copytree(SAVES / save, users[0])


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('exe_dir', type=Path, help='build directory holding GreenHatFlute')
    ap.add_argument('--save', help='directory name under build/save-backup; default: the profile as it is')
    ap.add_argument('--script', type=Path, default=ROOT / 'tools' / 'input' / 'load_save.txt', help='GHF_INPUT_SCRIPT')
    ap.add_argument('--seconds', type=float, required=True,
                    help='game time to run: the run ends once the world clock (game time since the save loaded) passed '
                         'this many seconds (shot is taken of that frame)')
    ap.add_argument('--tag', default='run', help='names the profile copy and the log')
    ap.add_argument('--shot', type=Path, help='PNG of the last frame; turns async pipeline builds off (boot.c)')
    ap.add_argument('--log', type=Path, help='default: <exe dir>/logs/<tag>.log')
    ap.add_argument('--env', action='append', default=[], metavar='KEY=VALUE', help='extra environment, repeatable')
    ap.add_argument('--quiet', action='store_true', help='wait until no other GreenHatFlute or ninja runs (benchmarks)')
    a = ap.parse_args()

    exe_dir = a.exe_dir.resolve()
    log = (a.log or exe_dir / 'logs' / f'{a.tag}.log').resolve()
    log.parent.mkdir(parents=True, exist_ok=True)
    gpu = take_gpu_lock(exe_dir) if a.quiet else None
    try:
        slot = take_slot()
        if a.quiet:
            while busy():
                time.sleep(10)
        prof = exe_dir / f'prof-{a.tag}'
        profile_copy(prof, a.save)

        env = dict(os.environ, GHF_ASSUME_FOCUS='1', GHF_INPUT='none', GHF_INPUT_SCRIPT=str(a.script.resolve()))
        for kv in a.env:
            k, _, v = kv.partition('=')
            env[k] = v
        args = [str(exe_dir / 'GreenHatFlute'), '--profile', str(prof), '--seconds', str(a.seconds)]
        if a.shot:
            args += ['--shot', str(a.shot.resolve())]
        try:
            with open(log, 'w', encoding='utf-8', errors='replace') as f:
                f.write(f'run_game: others running before: GreenHatFlute {count("GreenHatFlute")}, ninja {count("ninja")}\n')
                f.flush()
                start = time.time()
                proc = subprocess.Popen(args, cwd=exe_dir, env=env, stdout=f, stderr=subprocess.STDOUT)
                rc = proc.wait()
                f.write(f'run_game: rc={rc} wall={time.time() - start:.0f}s; others running after: '
                        f'GreenHatFlute {count("GreenHatFlute")}, ninja {count("ninja")}\n')
        finally:
            shutil.rmtree(prof, ignore_errors=True)
    finally:
        release_gpu_lock(gpu)
    print(f'{log}: rc={rc}')
    sys.exit(rc)


if __name__ == '__main__':
    main()
