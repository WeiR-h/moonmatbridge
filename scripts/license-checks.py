"""Check byte-exact license/notice/reference files in each release archive."""
from pathlib import Path
import hashlib
import json
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = json.loads((ROOT / 'package.json').read_text(encoding='utf-8'))['version']


def main():
    release = json.loads((ROOT / f'dist/release-v{VERSION}.json').read_text(encoding='utf-8'))
    assert release['status'] == 'passed' and release['version'] == VERSION
    assert 'Apache License' in (ROOT / 'LICENSE').read_text(encoding='utf-8')
    assert 'MoonBit' in (ROOT / 'NOTICE').read_text(encoding='utf-8')
    assert 'SciPy' in (ROOT / 'THIRD_PARTY.md').read_text(encoding='utf-8')
    checks = []
    for row in release['archives']:
        path = ROOT / 'dist' / row['file']
        assert hashlib.sha256(path.read_bytes()).hexdigest() == row['sha256']
        with zipfile.ZipFile(path) as package:
            assert package.testzip() is None
            for name in ('LICENSE', 'NOTICE', 'THIRD_PARTY.md'):
                matches = [n for n in package.namelist() if n.endswith('/' + name) and n.count('/') == 1]
                assert len(matches) == 1, (path.name, name, matches)
                payload = package.read(matches[0])
                assert payload == (ROOT / name).read_bytes(), (path.name, name)
                checks.append({'archive': path.name, 'file': name, 'sha256': hashlib.sha256(payload).hexdigest()})
    assert checks
    result = {'status': 'passed', 'version': VERSION, 'source_sha256': release['source_sha256'],
              'checks': checks, 'scope': 'Every release archive carries byte-exact Apache-2.0 license, runtime attribution and reference notices; no legal certification claimed.'}
    (ROOT / f'verification/reports/licenses-v{VERSION}.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8', newline='\n')
    print(f'{len(checks)} archive license/notice checks passed')


if __name__ == '__main__':
    main()
