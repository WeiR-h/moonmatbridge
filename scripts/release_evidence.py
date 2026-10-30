"""Versioned release evidence, source identity and measurement provenance."""
from pathlib import Path
import hashlib,importlib.util,json,subprocess

ROOT=Path(__file__).resolve().parents[1]
REPORTS=ROOT/'verification/reports'

def run(args,capture=True):
    p=subprocess.run(list(map(str,args)),cwd=ROOT,capture_output=capture,text=True,encoding='utf-8')
    if p.returncode:raise RuntimeError((p.stdout or '')+(p.stderr or ''))
    return p.stdout.strip() if capture else None

def read(path):return json.loads(Path(path).read_bytes())
def digest(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def save(name,value):
    path=REPORTS/name;path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\n')

def load(name,file):
    s=importlib.util.spec_from_file_location(name,ROOT/'scripts'/file);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m

def fingerprint():
    return run(['node','--input-type=module','-e',"import {sourceFingerprint} from './scripts/verify.mjs'; console.log(sourceFingerprint().sha256)"])

def scopes(ref=None):
    names=run(['git','ls-tree','-r','--name-only',ref or 'HEAD']).splitlines() if ref else [p.relative_to(ROOT).as_posix() for folder in ['src','scripts'] for p in (ROOT/folder).rglob('*') if p.is_file()]
    prod=load('release_runtime','performance-summary.py')
    groups={'runtime':[],'hosts':[],'adapters':[],'build':[]}
    adapters={'performance.py','performance-revisions.py','file-performance.py','write-performance.py','bench-js.mjs','bench-sink-js.mjs','build-bench.mjs'}
    build={'toolchain.lock.json','msvc.lock.json','scripts/build-native.mjs','scripts/moon.mjs','scripts/toolchain.mjs'}
    if not ref:names+=['toolchain.lock.json','msvc.lock.json']
    for n in sorted(set(names)):
        if prod.production(n):groups['runtime'].append(n)
        if n=='scripts/cli.mjs':groups['hosts'].append(n)
        if n.startswith(('src/bench_bridge/','src/cmd/bench/')) or n.startswith('scripts/') and Path(n).name in adapters:groups['adapters'].append(n)
        if n in build:groups['build'].append(n)
    result={}
    for group,files in groups.items():
        h=hashlib.sha256()
        for n in files:
            b=subprocess.check_output(['git','show',ref+':'+n],cwd=ROOT) if ref else (ROOT/n).read_bytes()
            h.update(n.encode()+b'\0'+b.replace(b'\r\n',b'\n')+b'\0')
        result[group]={'files':files,'sha256':h.hexdigest()}
    return result

def compiler_ok(value):
    try:return tuple(map(int,value.split('+')[0].split('.'))) >= (0,10,16)
    except (ValueError,AttributeError):return False

def validate_identity(version,source,local,ci,actual):
    assert local['status']==ci['status']=='passed','Verification failed'
    assert local['version']==ci['version']==version,'Wrong evidence version'
    assert local['source']['sha256']==ci['source_sha256']==actual,'Source changed after verification'
    assert ci['commit']==source,'CI belongs to another commit'
    assert compiler_ok(local['environment']['compiler_version']) and compiler_ok(ci['environment']['compiler_version']),'Compiler below minimum'
    assert set(ci['platforms'])=={'windows','linux'},'Missing CI platform'
    assert all(p['source_sha256']==actual and compiler_ok(p['environment']['compiler_version']) for p in ci['platforms'].values()),'CI platform identity differs'

def performance_binding(version,reference='v0.1.5'):
    current=scopes();expected=scopes(reference)
    assert current==expected,'Runtime, host, adapter or build changed: fresh measurements required'
    rv=read(ROOT/'package.json')['version']
    assert version==rv
    ref_version=reference.removeprefix('v')
    previous=REPORTS/f'performance-binding-v{ref_version}.json'
    if previous.exists():
        base=read(previous);assert base['status']=='verified';cohorts=base['cohorts']
    else:
        assert reference=='v0.1.5','A reference binding is required'
        cohorts=[{'file':'performance-vs-85fef84-v0.1.4.json','rows':24},{'file':'file-performance-v0.1.4.json','rows':6},{'file':'write-performance-v0.1.5.json','rows':32}]
    actual=read_toolchain()
    records=[]
    for row in cohorts:
        p=REPORTS/row['file'];data=read(p)
        assert data['status']=='measured' and len(data['results'])==row['rows'] and not data.get('partial'),'Incomplete cohort'
        if 'sha256' in row:assert row['sha256']==digest(p),'Historical report changed'
        assert data['environment']['toolchain']==actual,'Measured toolchain differs'
        records.append({'file':p.name,'rows':row['rows'],'sha256':digest(p),'measured_commit':data.get('candidate_commit',data.get('candidate_head_commit'))})
    # The v0.1.5 release already bound its retained reading cohorts to v0.1.4.
    # Preserve that historical chain, including its original adapters and repeats.
    legacy=read(REPORTS/'performance-summary-v0.1.5.json')
    assert legacy['status']=='verified' and legacy['runtime_source_sha256']==current['runtime']['sha256']
    result={'status':'verified','version':version,'reference':reference,'scopes':current,'toolchain':actual,'cohorts':records,'historical_chain':{'file':'performance-summary-v0.1.5.json','sha256':digest(REPORTS/'performance-summary-v0.1.5.json')},'scope':'Exact identity with the previously released reference. Retained measured cohorts keep their own commits, adapters, raw samples and original follow-ups; no new timing is claimed.'}
    save(f'performance-binding-v{version}.json',result);return result

def read_toolchain():return json.loads(run(['node','scripts/toolchain.mjs']))

def validate_binding(version):
    b=read(REPORTS/f'performance-binding-v{version}.json')
    assert b['status']=='verified' and b['version']==version and b['scopes']==scopes() and b['toolchain']==read_toolchain(),'Performance binding invalidated'
    for row in b['cohorts']:
        p=REPORTS/row['file'];data=read(p)
        assert digest(p)==row['sha256'] and data['status']=='measured' and len(data['results'])==row['rows'] and not data.get('partial')
    return b
