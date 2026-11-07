"""What the run says when the fault is not in our own code; no game, window or GPU.

Run: python tests/crash_report_test.py [--cc /path/to/clang]

A crash in a driver or in the C runtime's heap is outside runtime/'s own report (main.c names the faulting
instruction as GreenHatFlute+<offset>, which is a lie for another module), and the process used to end with nothing
in the log: the two crashes this cost us were only located afterwards, by systemd-coredump naming the thread.
platform/linux.c's fault handler now writes the module, the offset, the thread's name, what that thread said it was
working on (plat_crash_note) and the memory numbers. This fixture faults on purpose, inside libc and inside its own
code, and the test reads what came out.
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def run(exe, mode):
    p = subprocess.run([str(exe), mode], capture_output=True, text=True, timeout=30)
    return p.returncode, p.stderr


def check(mode, code, err, want_module):
    bad = []
    if code != -11:                       # killed by SIGSEGV, as the default action after our line
        bad.append(f'{mode}: exit {code}, expected a SIGSEGV death')
    line = next((l for l in err.splitlines() if 'crash: SIGSEGV at ' in l), None)
    if not line:
        bad.append(f'{mode}: no "[host] crash: SIGSEGV at ..." line in:\n{err}')
    else:
        if want_module not in line:
            bad.append(f'{mode}: the line does not name {want_module}: {line}')
        if 'thread ' not in line:
            bad.append(f'{mode}: the line does not name the thread: {line}')
    if 'working on: fixture' not in err:
        bad.append(f'{mode}: the note the thread set is missing:\n{err}')
    if 'crash: memory:' not in err:
        bad.append(f'{mode}: no memory line:\n{err}')
    return bad


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cc', default=os.environ.get('CC') or shutil.which('clang'))
    args = parser.parse_args()
    if not args.cc:
        parser.error('pass --cc with the project Clang executable')
    out = ROOT / 'build' / 'tests' / 'crash-report'
    out.mkdir(parents=True, exist_ok=True)
    exe = out / 'crash_report'
    # linux.c from source, as tests/fiber_stack_test.py does: the platform layer is what is under test.
    subprocess.run([args.cc, '-std=gnu11', '-O1', '-g', '-Wall', '-fno-strict-aliasing', '-no-pie',
                    '-I', str(ROOT / 'runtime'), str(ROOT / 'tests/crash_report.c'),
                    str(ROOT / 'runtime/platform/linux.c'), '-pthread', '-o', str(exe)], check=True)

    failures = []
    code, err = run(exe, 'libc')
    failures += check('libc', code, err, '.so')
    print(f"libc: {'ok' if not failures else 'FAIL'}: "
          + next((l for l in err.splitlines() if 'crash: SIGSEGV at ' in l), '(no line)'))
    code, err = run(exe, 'self')
    before = len(failures)
    failures += check('self', code, err, 'crash_report+')
    print(f"self: {'ok' if len(failures) == before else 'FAIL'}: "
          + next((l for l in err.splitlines() if 'crash: SIGSEGV at ' in l), '(no line)'))
    for f in failures:
        print('  FAIL: ' + f)
    print(f'crash report: {2 - len(failures)} of 2 cases ok' if failures else 'crash report: 2 of 2 cases ok')
    return 1 if failures else 0


if __name__ == '__main__':
    raise SystemExit(main())
