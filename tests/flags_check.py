"""Build and run tests/flags_check.c: runtime/cpu.h's function-local flag helpers against its packed flag helpers.

Usage: flags_check.py
"""
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tests' / 'diff'))
from common import compiler  # noqa: E402


def main():
    work = ROOT / 'build' / 'test' / 'flags'
    work.mkdir(parents=True, exist_ok=True)
    exe = work / 'flags_check'
    for opt in ('-O0', '-O1'):
        subprocess.check_call([compiler(), opt, '-fno-strict-aliasing', '-I', str(ROOT / 'runtime'),
                               str(ROOT / 'tests' / 'flags_check.c'), '-o', str(exe)])
        print(opt, end=': ', flush=True)
        if subprocess.run([str(exe)]).returncode:
            return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
