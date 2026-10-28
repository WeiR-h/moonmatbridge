"""Inherit measurements only after comparing the complete production file set."""
from pathlib import Path
import hashlib, json, subprocess
ROOT = Path(__file__).resolve().parents[1]
VERSION = json.loads((ROOT / 'package.json').read_text(encoding='utf-8'))['version']
REPORTS = ROOT / 'verification/reports'
REFERENCE = 'v0.0.8'
def production(name):
    p = Path(name)
    return (name.startswith('src/') and p.name != 'version.mbt'
        and not p.name.endswith(('_wbtest.mbt', '_test.mbt'))
        and not any(x in ('bench_bridge','bench','examples') for x in p.parts)
        and (p.suffix in ('.mbt','.c') or p.name == 'moon.pkg'))
def snapshot(ref=None):
    names = subprocess.check_output(['git','ls-tree','-r','--name-only',ref,'--','src'],cwd=ROOT).decode().splitlines() if ref else [p.relative_to(ROOT).as_posix() for p in (ROOT/'src').rglob('*') if p.is_file()]
    names = sorted(n for n in names if production(n))
    h=hashlib.sha256()
    for n in names:
        data=subprocess.check_output(['git','show',f'{ref}:{n}'],cwd=ROOT) if ref else (ROOT/n).read_bytes()
        h.update(n.encode()+b'\0'+data.replace(b'\r\n',b'\n')+b'\0')
    return names,h.hexdigest()
def main():
    names,fingerprint=snapshot()
    assert (names,fingerprint)==snapshot(REFERENCE), 'Runtime changed: fresh measurements required; historical inheritance forbidden'
    reports=[]
    for v in ('0.0.7','0.0.8'):
        path=REPORTS/f'performance-v{v}.json'
        r=json.loads(path.read_text(encoding='utf-8'))
        assert r['status']=='measured' and r['version']==v and r['results']
        reports.append({**r,'report_sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
    result={'status':'summarized','version':VERSION,'measured_versions':[r['version'] for r in reports],
        'inherited_from':REFERENCE,'runtime_source_sha256':fingerprint,'runtime_files':len(names),
        'hash_policy':'Complete sorted production source set, LF normalized; excludes tests, benches, examples and version text',
        'baseline_commit':reports[0]['baseline_commit'],'measurements':reports,
        'scope':'Historical measurements guarded by production source/file-set equality; no new timing claimed.'}
    (REPORTS/f'performance-summary-v{VERSION}.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'status':'summarized','version':VERSION,'runtime_source_sha256':fingerprint}))
if __name__=='__main__': main()
