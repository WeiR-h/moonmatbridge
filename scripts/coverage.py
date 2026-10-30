"""Produce local, inspectable MoonBit coverage; no external coverage service."""
from pathlib import Path
import json,os,subprocess,hashlib
ROOT=Path(__file__).resolve().parents[1]
VERSION=json.loads((ROOT/'package.json').read_bytes())['version']
OUT=ROOT/'verification/local/coverage';OUT.mkdir(exist_ok=True,parents=True)
BUILD=OUT/'build'
def run(args):
 args=([args[0],'--target-dir',str(BUILD),*args[1:]] if args[0]=='coverage' else [*args,'--target-dir',str(BUILD)])
 p=subprocess.run(['node','scripts/moon.mjs',*args],cwd=ROOT,capture_output=True,text=True,encoding='utf-8',env={**os.environ,'PYTHONUTF8':'1'},timeout=180)
 assert p.returncode==0,p.stdout+p.stderr
 return p.stdout+p.stderr
run(['coverage','clean'])
tests=run(['test','--target','js','--enable-coverage','--deny-warn'])
traces=sorted(BUILD.rglob('*.trace.source'))
logs=sorted(BUILD.glob('moonbit_coverage_*.txt'))
assert traces and logs,'Missing actual compiler coverage records'
combined=OUT/'runtime.txt';combined.write_bytes(b'\n'.join(p.read_bytes() for p in logs))
# Explicit records prevent discovery of archived consumers with the same module id.
inputs=['--runtime-log',str(combined),*[str(p) for p in traces]]
summary=run(['coverage','report','--format','summary',*inputs])
run(['coverage','report','--format','coveralls','--output',str(OUT/'coveralls.json'),*inputs])
run(['coverage','report','--format','html','--output',str(OUT/'html'),*inputs])
raw=json.loads((OUT/'coveralls.json').read_bytes())
files=[]
for row in raw['source_files']:
 name=row['name'].replace('\\','/')
 if '_wbtest.' in name or '_test.' in name or 'pkg.generated' in name:continue
 marks=row['coverage'];valid=[n for n in marks if n is not None]
 if not valid:continue
 files.append({'file':name,'covered':sum(n>0 for n in valid),'instrumented':len(valid),'uncovered_lines':[i+1 for i,n in enumerate(marks) if n==0]})
assert files and all(sum(row['covered'] for row in files if part in row['file'])>0 for part in ['tree','inflate','deflate','snapshot','close'])
report={'status':'passed','version':VERSION,'target':'js','metric':'MoonBit compiler instrumented source lines; not branch coverage','tests':tests,'summary':summary,'covered':sum(r['covered'] for r in files),'instrumented':sum(r['instrumented'] for r in files),'files':files,'raw_sha256':hashlib.sha256((OUT/'coveralls.json').read_bytes()).hexdigest(),'html':'verification/local/coverage/html/index.html','scope':'Local compiler coverage, all instrumented source files and uncovered lines preserved; independent scientific tests are reported separately.'}
report['domains']={}
for domain,predicate in [('core',lambda n:n.startswith('src/') and n.count('/')==1),('interchange',lambda n:n.startswith('src/interchange/')),('bridge',lambda n:n.startswith('src/bridge/'))]:
    group=[r for r in files if predicate(r['file'])]
    report['domains'][domain]={'covered':sum(r['covered'] for r in group),'instrumented':sum(r['instrumented'] for r in group),'metric':'compiler source lines from the unit-test trace only'}
report['functional_evidence']={}
for name in ['js','sink-operations','source-operations','tree-operations','tree-close']:
    evidence=ROOT/f'verification/reports/{name}-v{VERSION}.json'
    if evidence.exists():
        value=json.loads(evidence.read_bytes());report['functional_evidence'][name]={'status':value['status'],'file':evidence.name,'sha256':hashlib.sha256(evidence.read_bytes()).hexdigest()}
report['coverage_note']='Bridge unit traces and external functional evidence are separate; zero trace lines do not assert untested exports. This is not branch coverage.'
(ROOT/f'verification/reports/coverage-v{VERSION}.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8',newline='\n')
print(summary)
print(json.dumps({'status':'passed','covered':report['covered'],'instrumented':report['instrumented']}))
