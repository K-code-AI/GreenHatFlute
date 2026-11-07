"""Check the translator's default/opt-in source preparation and cache separation.

Applies the actual patches to disposable vendor copies, without building .NET or
running a GPU. The strict numeric regression remains float_minmax_test.py and
requires a translator built with --defined-float-minmax.
"""
import contextlib
import importlib.util
import io
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('build_xlate', ROOT / 'tools/build_xlate.py')
builder = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(builder)
OPTIONAL = '0014-numeric-float-minmax-and-saturation.patch'


class TranslatorOptions(unittest.TestCase):
    def setUp(self):
        output = ROOT / 'build/test/build-xlate-options'
        output.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=output)
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)

    def prepare(self, opt_in=False):
        with patch.object(builder, 'BUILD', self.work), contextlib.redirect_stdout(io.StringIO()):
            if opt_in:
                return builder.prepare_sources(defined_float_minmax=True)
            return builder.prepare_sources()

    def minmax_bodies(self, source):
        """The three min/max/clamp method bodies, so a failure names the lines that moved instead of the whole file."""
        text = (source / 'src/Ryujinx.Graphics.Shader/CodeGen/Spirv/Instructions.cs').read_text()
        bodies = {}
        for name in ('GenerateClamp', 'GenerateMaximum', 'GenerateMinimum'):
            start = text.index(f'private static OperationResult {name}(CodeGenContext context, AstOperation operation)')
            bodies[name] = text[start:text.index('\n        }', start)]
        return bodies

    def test_default_keeps_the_patched_minmax_delegates(self):
        source = self.prepare()
        instructions = (source / 'src/Ryujinx.Graphics.Shader/CodeGen/Spirv/Instructions.cs').read_text()
        folding = (source / 'src/Ryujinx.Graphics.Shader/Translation/Optimizations/ConstantFolding.cs').read_text()
        bodies = self.minmax_bodies(source)
        self.assertFalse('EmitNumericMinMax' in instructions, 'default unexpectedly applies the integer min/max patch')
        # 0031-maxwell-nan-semantics is in every build and rewrites these three returns to the NaN-propagating
        # GLSL.std.450 NMin/NMax/NClamp (79/80/81); 0014's integer-key selection is the part that stays opt-in.
        self.assertIn('context.GlslNClamp', bodies['GenerateClamp'])
        self.assertIn('context.GlslNMax', bodies['GenerateMaximum'])
        self.assertIn('context.GlslNMin', bodies['GenerateMinimum'])
        self.assertIn('EvaluateFPTernary(operation, (x, y, z) => Math.Clamp(x, y, z));', folding)

    def test_opt_in_applies_integer_selection_and_numeric_folding(self):
        source = self.prepare(opt_in=True)
        instructions = (source / 'src/Ryujinx.Graphics.Shader/CodeGen/Spirv/Instructions.cs').read_text()
        folding = (source / 'src/Ryujinx.Graphics.Shader/Translation/Optimizations/ConstantFolding.cs').read_text()
        bodies = self.minmax_bodies(source)
        self.assertIn('private static SpvInstruction EmitNumericMinMax(', instructions)
        self.assertIn('context.Bitcast(isFP64 ? context.TypeFP64() : context.TypeFP32(), selected)', instructions)
        self.assertIn('float.MinNumber(float.MaxNumber(x, y), z)', folding)
        # 0014 inserts into the same three methods 0031 rewrites, and it is applied last: both must be present, or one
        # of the two patches has silently stopped landing there.
        self.assertIn('GenerateNumericMinMax(context, operation, maximum: true)', bodies['GenerateMaximum'])
        self.assertIn('context.GlslNMax', bodies['GenerateMaximum'])
        self.assertIn('GenerateNumericMinMax(context, operation, maximum: false)', bodies['GenerateMinimum'])
        self.assertIn('context.GlslNMin', bodies['GenerateMinimum'])

    def test_modes_cannot_share_a_cache_identity(self):
        self.assertNotEqual(builder.identity(), builder.identity(defined_float_minmax=True))

    def test_unused_patch_does_not_change_default_identity(self):
        xlate = self.work / 'xlate'
        shutil.copytree(builder.XLATE, xlate)
        with patch.object(builder, 'XLATE', xlate):
            fast = builder.identity()
            defined = builder.identity(defined_float_minmax=True)
            optional = xlate / 'patches' / OPTIONAL
            optional.write_bytes(optional.read_bytes() + b'\n')
            self.assertEqual(fast, builder.identity())
            self.assertNotEqual(defined, builder.identity(defined_float_minmax=True))

    def test_shared_patch_changes_both_identities(self):
        xlate = self.work / 'xlate'
        shutil.copytree(builder.XLATE, xlate)
        with patch.object(builder, 'XLATE', xlate):
            fast = builder.identity()
            defined = builder.identity(defined_float_minmax=True)
            shared = next((xlate / 'patches').glob('0001-*.patch'))
            shared.write_bytes(shared.read_bytes() + b'\n')
            self.assertNotEqual(fast, builder.identity())
            self.assertNotEqual(defined, builder.identity(defined_float_minmax=True))

    def test_id_only_cli_uses_the_selected_mode(self):
        for opt_in in (False, True):
            command = [sys.executable, '-B', str(ROOT / 'tools/build_xlate.py'), '--id-only', '--out', str(self.work)]
            if opt_in:
                command.append('--defined-float-minmax')
            result = subprocess.run(command, capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((self.work / 'greenhatflute_xlate.id').read_text().strip(),
                             builder.identity(defined_float_minmax=opt_in))


if __name__ == '__main__':
    unittest.main()
