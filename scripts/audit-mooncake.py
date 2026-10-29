"""Audit the exact Mooncakes archive against an independent file allowlist."""
from pathlib import Path
import hashlib
import json
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]
version = json.loads((ROOT / 'package.json').read_text(encoding='utf-8'))['version']
archive = ROOT / '_build/publish' / f'WeiR-h-moonmatbridge-{version}.zip'
allowed = {'.moonignore', 'moon.mod', 'README.md', 'CHANGELOG.md', 'LICENSE', 'NOTICE', 'THIRD_PARTY.md', 'benchmarks/manifest.json'}
allowed.update('docs/' + name for name in ['NAME_ENCODING.md', 'TREE_CLOSE.md', 'SOURCES.md', 'TREE_SNAPSHOT.md', 'TREE_DIFF.md', 'ACCEPTANCE.md', 'API.md', 'FORMAT.md', 'JSON.md', 'RECIPES.md',
                                         'DIFFERENTIATION.md', 'ITERATIONS-v0.0.3.md', 'COMPATIBILITY.md',
                                         'COMPATIBILITY_MATRIX.md', 'NEXT_RELEASES.md', 'PERFORMANCE.md',
                                         'SCIENTIFIC_WORKFLOWS.md', 'REVIEW_EVIDENCE-v0.0.9.md'])
allowed.update('examples/' + name for name in ['sample.mat', 'sample.json', 'transform-plan.json'])
for directory in ['src', 'examples/python', 'examples/matlab', 'examples/octave', 'examples/registry_consumer', 'examples/mixed', 'examples/workflows', 'examples/compatibility', 'examples/unicode']:
    allowed.update(path.relative_to(ROOT).as_posix() for path in (ROOT / directory).rglob('*') if path.is_file() and '__pycache__' not in path.parts)
entries = []
seen = set()
with zipfile.ZipFile(archive) as package:
    assert package.testzip() is None
    for entry in package.infolist():
        if entry.is_dir():
            continue
        name = entry.filename.replace('\\', '/')
        assert name in allowed and name not in seen, ('Unexpected package member', name)
        seen.add(name)
        assert entry.file_size < 2 * 1024 * 1024
        payload = package.read(entry)
        assert payload == (ROOT / name).read_bytes(), ('Archive differs from source', name)
        assert not re.search(rb'-----BEGIN [A-Z ]*PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{20,}', payload), name
        entries.append({'file': name, 'bytes': len(payload), 'sha256': hashlib.sha256(payload).hexdigest()})
assert seen == allowed, ('Missing package members', sorted(allowed - seen))
manifest = (ROOT / 'moon.mod').read_text(encoding='utf-8')
assert 'name = "WeiR-h/moonmatbridge"' in manifest and f'version = "{version}"' in manifest
report = {'status': 'passed', 'module': 'WeiR-h/moonmatbridge', 'version': version,
          'archive': archive.relative_to(ROOT).as_posix(),
          'archive_sha256': hashlib.sha256(archive.read_bytes()).hexdigest(),
          'files': sorted(entries, key=lambda entry: entry['file']),
          'scope': 'Exact file allowlist, source byte equality and private-key/token markers; tools, local settings, registration and verification directories excluded.'}
(ROOT / 'verification/reports').mkdir(parents=True, exist_ok=True)
(ROOT / f'verification/reports/mooncake-audit-v{version}.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'status': 'passed', 'version': version, 'files': len(entries), 'archive_sha256': report['archive_sha256']}))
