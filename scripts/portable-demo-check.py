import hashlib
import json
import shutil
import subprocess
import uuid
from pathlib import Path


def check_long_windows_paths(executable, directory):
    folder = directory / ('科研数据 ' + 'a' * 95) / ('实验结果 ' + 'b' * 95)
    # Prefix only the Python fixture access. The CLI receives ordinary paths.
    filesystem_folder = Path('\\\\?\\' + str(folder))
    filesystem_folder.mkdir(parents=True)
    sample = folder / '样例.mat'
    archive = folder / '压缩.mat'
    selected = folder / '选取.mat'
    report = folder / '比较.json'
    relative_archive = archive.relative_to(directory).as_posix()
    assert len(str(sample)) >= 260 and len(relative_archive) < 260

    def invoke(*args, error=None):
        result = subprocess.run([executable, *args], cwd=directory, capture_output=True,
                                text=True, encoding='utf-8', timeout=30)
        expected_exit = 1 if error else 0
        assert result.returncode == expected_exit, (args, result.stdout, result.stderr)
        payload = json.loads(result.stderr if error else result.stdout)
        if error:
            assert payload['code'] == error, payload
        return payload

    invoke('sample', sample)
    original = (filesystem_folder / sample.name).read_bytes()
    info = invoke('info', sample)
    assert invoke('info', filesystem_folder / sample.name) == info
    invoke('compress', sample, relative_archive)
    roots = invoke('roots', relative_archive)['roots']
    invoke('select', relative_archive, selected, roots[0]['name'])
    assert len(invoke('roots', selected)['roots']) == 1
    invoke('diff-tree', sample, relative_archive, report)
    assert json.loads((filesystem_folder / report.name).read_bytes())['content_equal']
    invoke('sample', sample, error='output-exists')
    invoke('roundtrip', relative_archive, sample, error='output-exists')
    assert (filesystem_folder / sample.name).read_bytes() == original
    assert not list(filesystem_folder.glob('.mmb-*.tmp'))
    return {'status': 'passed', 'absolute_path_length': len(str(sample)),
            'relative_path_length': len(relative_archive)}


root = Path(__file__).resolve().parents[1]
shell = shutil.which('pwsh') or shutil.which('powershell.exe')
assert shell
output = root / 'verification/local' / ('portable-demo-' + uuid.uuid4().hex)
executable = root / 'dist/moonmat.exe'
demo = root / 'examples/workflows/demo.ps1'
process = subprocess.run(
    [shell, '-NoProfile', '-File', demo, '-Executable', executable, '-OutputDirectory', output],
    cwd=root, capture_output=True, text=True, encoding='utf-8', timeout=180,
)
assert process.returncode == 0, (process.stdout, process.stderr)
result = json.loads((output / 'demo-receipt.json').read_text(encoding='utf-8-sig'))
assert result['status'] == 'passed'
long_paths = check_long_windows_paths(executable, output)
version = json.loads((root / 'package.json').read_bytes())['version']
receipt = {
    'status': 'passed', 'version': version,
    'executable_sha256': hashlib.sha256(executable.read_bytes()).hexdigest(),
    'commands': len(result['commands']), 'files': result['files'], 'long_paths': long_paths,
    'scope': 'Actual shipped PowerShell demo and native Windows long path checks in a new directory',
}
report = root / f'verification/reports/workflows-demo-v{version}.json'
report.write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8', newline='\n')
print('Portable demo: all three workflows, comparison exits and Windows long paths passed')
