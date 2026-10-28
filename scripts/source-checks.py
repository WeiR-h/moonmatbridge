"""Large-file and source-lifetime checks for both thin filesystem hosts."""
from pathlib import Path
import argparse,hashlib,importlib.util,json,os,platform,shutil,subprocess,time
import numpy as np
from scipy.io import loadmat
ROOT=Path(__file__).resolve().parents[1]
VERSION=json.loads((ROOT/'package.json').read_bytes())['version']
OUT=ROOT/'verification/local/source-checks';OUT.mkdir(parents=True,exist_ok=True)
spec=importlib.util.spec_from_file_location('file_perf',ROOT/'scripts/file-performance.py')
fixtures=importlib.util.module_from_spec(spec);spec.loader.exec_module(fixtures)

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--native-executable');parser.add_argument('--js-cli');parser.add_argument('--fixture-manifest');args=parser.parse_args()
    checks=[]
    cases=json.loads(Path(args.fixture_manifest).read_bytes())['cases'] if args.fixture_manifest else fixtures.fixtures()
    native_executable=args.native_executable or str(ROOT/'dist'/('moonmat.exe' if platform.system()=='Windows' else 'moonmat'))
    js_cli=args.js_cli or str(ROOT/'scripts/cli.mjs')
    expected=np.random.default_rng(20261017);expected.standard_normal(4096)
    wanted=expected.standard_normal(131072).reshape((256,512),order='F')
    for case in cases:
        if case['name']=='select-1-of-16' or tuple(map(int,VERSION.split('.')))<tuple(case['minimum_version']):continue
        source=Path(case['path'])
        assert hashlib.sha256(source.read_bytes()).hexdigest()==case['sha256']
        for host,prefix in [('native',[native_executable]),('js',['node',js_cli])]:
            roots=subprocess.run(prefix+['roots',source],capture_output=True,text=True,encoding='utf-8',timeout=150)
            assert roots.returncode==0,(host,roots.stdout,roots.stderr)
            assert [r['name'] for r in json.loads(roots.stdout)['roots']]==['big','wanted']
            output=OUT/f"{host}-{case['name']}.mat";output.unlink(missing_ok=True)
            r=subprocess.run(prefix+['select',source,output,'wanted'],capture_output=True,text=True,encoding='utf-8',timeout=150)
            assert r.returncode==0,(host,r.stdout,r.stderr)
            actual=loadmat(output)['wanted'];assert actual.dtype==wanted.dtype and actual.tobytes()==wanted.tobytes()
            checks.append({'host':host,'case':case['name'],'status':'passed','input_sha256':case['sha256'],'input_bytes':case['bytes'],'output_sha256':hashlib.sha256(output.read_bytes()).hexdigest()})
    source=Path(next(c['path'] for c in cases if c['name']=='large-uncompressed'))
    before=source.stat()
    native=[native_executable,'roots',str(source)]
    process=subprocess.Popen(native,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    counter=0
    try:
        while process.poll() is None:
            counter+=1;os.utime(source,ns=(before.st_atime_ns,before.st_mtime_ns+counter*1000000));time.sleep(.001)
        stdout,stderr=process.communicate(timeout=10)
        response=json.loads(stdout or stderr)
        assert process.returncode==1 and response['code']=='source-changed',response
    finally:os.utime(source,ns=(before.st_atime_ns,before.st_mtime_ns))
    checks.append({'host':'native','case':'source changed during full scan','status':'passed','timestamp_updates':counter})
    hook=OUT/'change-source.cjs'
    hook.write_text("const fs=require('node:fs');const path=process.argv.at(-1);const before=fs.statSync(path);const read=fs.readSync;let changed=false;fs.readSync=function(fd,...args){const n=read(fd,...args);if(!changed&&fs.fstatSync(fd).size===before.size){changed=true;fs.utimesSync(path,before.atime,new Date(before.mtimeMs+2000));}return n;};require('node:module').syncBuiltinESMExports();",encoding='utf-8')
    try:
        result=subprocess.run(['node','--require',hook,js_cli,'roots',source],capture_output=True,text=True,encoding='utf-8',timeout=150)
        assert result.returncode==1 and json.loads(result.stderr)['code']=='source-changed',(result.stdout,result.stderr)
    finally:os.utime(source,ns=(before.st_atime_ns,before.st_mtime_ns))
    checks.append({'host':'js','case':'source changed inside read callback','status':'passed'})
    report={'status':'passed','version':VERSION,'checks':checks,'passed':len(checks),'oracle':'Fixed seed NumPy expected data and SciPy output consumption; file fixture hashes and generator retained','seed':20261017,'block_bytes':32768,'repeats':8192}
    (ROOT/f'verification/reports/source-operations-v{VERSION}.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8',newline='\n')
    print(f"Large-file and source lifetime checks: {len(checks)} passed")

if __name__=='__main__':main()
