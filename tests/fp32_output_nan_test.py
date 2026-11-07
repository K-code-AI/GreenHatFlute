"""Translate an owned Maxwell fragment shader that writes a float and an integer to one FP32 target.

The translator contains a NaN colour where it leaves the fragment shader: the blur and bloom passes have no guard of
their own, and one NaN travels through them until whole frames are white. It has to contain it by the type of the
value written, not by the type of the target. An integer that reaches an FP32 target carries plain bits - patch 0018's
F2I.S8 of a negative number is negative - and read as a float every one of those bit patterns is a NaN, so guarding
it erases the value, which is what tests/f2i_byte_test.py caught.

The fixture loads c[0][0] (dynamic, so nothing folds) and writes it four ways: R0 and R3 through FMNMX R4, R4, which
keeps the value a float (patch 0031 emits NMin, and the minimum of a value with itself is that value, NaN included),
and R1 and R2 through F2I.S32 and F2I.S8, which are integers. A NaN must become +0 in the float components while the
same input must survive in the integer ones: that pair is the whole point of the test. The emitted SPIR-V is executed
with the evaluator of tests/f2i_byte_test.py, which covers exactly the operations this fixture emits. No game data or
GPU is used.

Usage: python tests/fp32_output_nan_test.py --translator build/xlate/greenhatflute_xlate [--spirv-val PATH]
"""
import argparse
import json
import math
from pathlib import Path
import struct
import subprocess

import f2i_byte_test as f2i

ROOT = Path(__file__).resolve().parents[1]


def shader():
    header = [0] * 20
    header[0] = 5 << 10   # fragment stage
    header[18] = 15       # render target 0: R0, R1, R2, R3
    ldc = 0xef90000000000000 | (4 << 48) | (0 << 20) | (255 << 8) | (7 << 16) | 4   # LDC.32 R4, c[0][0]

    def fmnmx(dest):   # FMNMX Rd, R4, R4, PT: minimum, no FTZ, no abs/neg, no condition codes.
        return 0x5c60000000000000 | (7 << 39) | (4 << 20) | (4 << 8) | (7 << 16) | dest

    instructions = [ldc, fmnmx(0), f2i.f2i(1, 4, 2, 1), f2i.f2i(2, 4, 0, 1), fmnmx(3), 0xe30000000007000f]
    words = []
    for index in range(0, len(instructions), 3):
        words.extend([0, *instructions[index:index + 3]])   # Maxwell scheduling words
    return struct.pack('<20I', *header) + struct.pack('<' + 'Q' * len(words), *words) + bytes(256)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--translator', required=True, type=Path)
    parser.add_argument('--spirv-val', type=Path)
    args = parser.parse_args()
    out = ROOT / 'build/test/fp32-output-nan'
    out.mkdir(parents=True, exist_ok=True)
    code = out / 'fp32_output_nan.bin'
    code.write_bytes(shader())
    jobs = out / 'jobs.json'
    jobs.write_text(json.dumps([{'key': 'fp32_output_nan', 'stage': 'ps', 'code': str(code.resolve()), 'debug': False}]))
    run = subprocess.run([str(args.translator.resolve()), str(jobs.resolve()), str(out.resolve())],
                         capture_output=True, encoding='utf-8')
    if run.returncode:
        raise AssertionError('translator failed: ' + run.stderr.encode('ascii', 'backslashreplace').decode())
    spirv = out / 'fp32_output_nan.spv'
    if args.spirv_val:
        subprocess.run([str(args.spirv_val.resolve()), '--target-env', 'vulkan1.2', str(spirv)], check=True)
    module = f2i.module(spirv)

    # R0 and R3 hold the input as a float, R1 as F2I.S32 and R2 as F2I.S8. The float components are guarded, so a NaN
    # leaves as +0; the integer ones are not, so their bits - negative numbers, NaN-shaped to a float - arrive whole.
    failures, checks = 0, 0
    for x in (-63.5, -127.0, -1.0, -0.75, -0.0, 0.0, 0.5, 1.0, 63.5, 127.0, -129.0, -300.0, 255.0, 256.0,
              40000.0, -40000.0, 2.0 ** 31, 1e20, -1e20, math.inf, -math.inf, math.nan):
        got = f2i.evaluate(module, x)
        want = [0.0 if math.isnan(x) else x,                             # R0: the float, guarded
                f2i.saturate(x, -2 ** 31, 2 ** 31 - 1) & 0xffffffff,     # R1: F2I.S32
                f2i.saturate(x, -128, 127) & 0xffffffff,                 # R2: F2I.S8
                0.0 if math.isnan(x) else x]                             # R3: the float again
        defined32 = math.isfinite(x) and -2 ** 31 <= x < 2 ** 31
        for name, g, w in zip(('F32', 'S32', 'S8', 'F32b'), got, want):
            if name == 'S32' and not defined32:
                continue      # its conversion is undefined in SPIR-V there; neither patch changes that
            checks += 1
            # A float component is compared as 32-bit bits: the input reaches it through a float32, so 1e20 is stored
            # as the float32 nearest to it, not as the Python double.
            want_word = f2i.u32(w) if isinstance(w, float) else w
            if g != want_word:
                failures += 1
                print('FAIL %s(%r): got %s, want %s' % (name, x, f2i.f32(g) if isinstance(w, float) else f2i.s32(g), w))
    print('fp32 output nan: %d checks, %d failures' % (checks, failures))
    return 1 if failures else 0


if __name__ == '__main__':
    raise SystemExit(main())
