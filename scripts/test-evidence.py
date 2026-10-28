"""Regression tests for inherited performance evidence (isolated temporary Git repo)."""
from pathlib import Path
import importlib.util
import subprocess
import tempfile

spec = importlib.util.spec_from_file_location('performance_summary', Path(__file__).with_name('performance-summary.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
with tempfile.TemporaryDirectory(prefix='moonmat-evidence-') as directory:
    root = Path(directory)
    module.ROOT = root
    def git(*args):
        subprocess.run(['git', *args], cwd=root, check=True, capture_output=True)
    git('init')
    (root/'src').mkdir()
    source = root/'src/runtime.mbt'
    source.write_bytes(b'production\n')
    git('add', '.')
    git('-c', 'user.name=Evidence test', '-c', 'user.email=evidence@example.invalid', 'commit', '-m', 'fixed reference')
    reference = module.snapshot('HEAD')
    assert module.snapshot() == reference
    source.write_bytes(b'production\r\n')
    assert module.snapshot() == reference, 'LF normalization'
    source.write_bytes(b'changed\n')
    assert module.snapshot() != reference, 'Changed runtime must invalidate evidence'
    source.write_bytes(b'production\n')
    addition = root/'src/added.mbt'
    addition.write_bytes(b'new runtime\n')
    assert module.snapshot() != reference, 'New runtime file must invalidate evidence'
    addition.unlink()
    source.unlink()
    assert module.snapshot() != reference, 'Removed runtime file must invalidate evidence'
    source.write_bytes(b'production\n')
    (root/'src/check_wbtest.mbt').write_bytes(b'test-only\n')
    assert module.snapshot() == reference, 'Test changes are not runtime changes'
print('Performance evidence guards: unchanged, LF, changed, added, removed, test-only passed')
