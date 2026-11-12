"""Recheck current-toolchain compatibility without replacing historical reports."""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import os
import subprocess
import sys
import uuid

ROOT = Path(__file__).resolve().parents[1]
REPORTS = ROOT / 'verification/reports'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--published', required=True, help='Exact existing Mooncakes consumer version')
    parser.add_argument('--octave', action='store_true', help='Also require real GNU Octave')
    args = parser.parse_args()
    version = json.loads((ROOT / 'package.json').read_bytes())['version']
    run_id = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ') + '-' + uuid.uuid4().hex[:8]
    output = ROOT / 'verification/local/maintenance' / run_id
    output.mkdir(parents=True, exist_ok=False)
    env = {**os.environ, 'MOONMAT_PYTHON': sys.executable, 'PYTHONUTF8': '1'}
    original = {p.name: p.read_bytes() for p in REPORTS.iterdir() if p.is_file()}
    receipt = {'schema': 'moonmatbridge/maintenance/1', 'status': 'running', 'run_id': run_id,
               'version': version, 'published_consumer': args.published,
               'checked_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
               'commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
               'worktree_status': subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True, encoding='utf-8').splitlines(),
               'steps': [], 'reports': []}
    tasks = [('toolchain', ['node', 'scripts/toolchain.mjs']),
             ('verify', ['node', 'scripts/verify.mjs']),
             ('coverage', [sys.executable, 'scripts/coverage.py']),
             ('published-consumer', ['node', 'scripts/registry-verify.mjs', '--published', args.published])]
    if args.octave:
        tasks.append(('octave', [sys.executable, 'scripts/octave-interop.py']))
    try:
        for index, (name, command) in enumerate(tasks, 1):
            print(f'[{index}/{len(tasks)}] {name}', flush=True)
            log = output / (name + '.log')
            with log.open('w', encoding='utf-8') as stream:
                result = subprocess.run(command, cwd=ROOT, env=env, stdout=stream,
                                        stderr=subprocess.STDOUT, timeout=1200)
            receipt['steps'].append({'name': name, 'command': command, 'exit_code': result.returncode,
                                     'log': log.name, 'sha256': digest(log.read_bytes())})
            if result.returncode:
                print(log.read_text(encoding='utf-8')[-16000:], flush=True)
                raise RuntimeError(name + ' failed; full log: ' + str(log))
            if name == 'toolchain':
                receipt['toolchain'] = json.loads(log.read_text(encoding='utf-8'))
            print(name + ': passed', flush=True)
        verified = json.loads((REPORTS / f'v{version}.json').read_bytes())
        receipt['source_sha256'] = verified['source']['sha256']
        receipt['verification_groups'] = len(verified['checks'])
        receipt['status'] = 'passed'
    except Exception as error:
        receipt['status'] = 'failed'
        receipt['error'] = str(error)
    finally:
        generated = output / 'reports'
        generated.mkdir()
        for path in REPORTS.iterdir():
            if path.is_file() and original.get(path.name) != path.read_bytes():
                data = path.read_bytes()
                (generated / path.name).write_bytes(data)
                receipt['reports'].append({'file': 'reports/' + path.name, 'sha256': digest(data)})
                if path.name not in original:
                    path.unlink()
        for name, data in original.items():
            path = REPORTS / name
            if not path.exists() or path.read_bytes() != data:
                path.write_bytes(data)
        after = {p.name: digest(p.read_bytes()) for p in REPORTS.iterdir() if p.is_file()}
        receipt['historical_reports_unchanged'] = after == {n: digest(b) for n, b in original.items()}
        if not receipt['historical_reports_unchanged']:
            receipt['status'] = 'failed'
        receipt['scope'] = ('Fresh checks, builds, tests, coverage and public API consumer with the recorded toolchain. '
                            'Real Octave is included only when requested. No new performance measurements.')
        receipt['finished_at'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        (output / 'maintenance.json').write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
    print(json.dumps({'status': receipt['status'], 'receipt': str(output / 'maintenance.json')}, ensure_ascii=False), flush=True)
    return 0 if receipt['status'] == 'passed' else 1


if __name__ == '__main__':
    raise SystemExit(main())
