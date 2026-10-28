"""Symmetric tolerance comparison using independent scientific MAT producers."""
from pathlib import Path
import argparse,importlib.util,json,platform,subprocess
from decimal import Decimal,localcontext
import numpy as np
from scipy.sparse import csc_matrix
ROOT=Path(__file__).resolve().parents[1]
VERSION=json.loads((ROOT/'package.json').read_bytes())['version']
OUT=ROOT/'verification/local/tree-close';OUT.mkdir(parents=True,exist_ok=True)
spec=importlib.util.spec_from_file_location('mixed',ROOT/'examples/python/mixed_types.py');mixed=importlib.util.module_from_spec(spec);spec.loader.exec_module(mixed)

def expected(a,b,atol,rtol,equal_nan=False):
    if np.isnan(a) or np.isnan(b):return equal_nan and np.isnan(a) and np.isnan(b)
    if a==b:return True
    if not np.isfinite(a) or not np.isfinite(b):return False
    with localcontext() as context:
        context.prec=1200
        x,y,t,r=map(Decimal.from_float,map(float,(a,b,atol,rtol)))
        return abs(x-y)<=t+r*max(abs(x),abs(y))

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--native-executable');parser.add_argument('--js-cli');args=parser.parse_args()
    checks=[]
    def run(host,prefix,label,left,right,options,code,equal,exact):
        l=OUT/f'{label}-left.mat';r=OUT/f'{label}-right.mat'
        l.write_bytes(mixed.deterministic_mat(left));r.write_bytes(mixed.deterministic_mat(right))
        opts=OUT/f'{label}-options.json';opts.write_text(json.dumps(options),encoding='utf-8')
        report=OUT/f'{host}-{label}.json';report.unlink(missing_ok=True)
        result=subprocess.run(prefix+['diff-tree-close',l,r,report,opts],capture_output=True,text=True,encoding='utf-8',timeout=60)
        assert result.returncode==code,(label,host,result.stdout,result.stderr)
        actual=json.loads(report.read_bytes())
        assert actual['schema']=='moonmatbridge/tree-close/1' and actual['within_tolerance']==equal and actual['exact_equal']==exact,actual
        checks.append({'host':host,'case':label,'status':'passed','exit':code})
        return actual
    cases=[(1.,1.125,.125,0.),(1.,1.125,.124,0.),(1.,2.,0.,.5),(1.,2.,0.,.499),(1e308,-1e308,0.,2.),(1e308,-1e308,1.7e308,.25),(1e308,-1e308,1.7e308,.5),(0.,5e-324,5e-324,0.),(0.,5e-324,0.,0.),(np.inf,np.inf,0.,0.),(np.inf,-np.inf,1e308,1.),(np.inf,1e308,0.,1e308),(-0.,0.,0.,0.)]
    for host,prefix in [('native',[args.native_executable or str(ROOT/'dist'/('moonmat.exe' if platform.system()=='Windows' else 'moonmat'))]),('js',['node',args.js_cli or str(ROOT/'scripts/cli.mjs')])]:
        for i,(a,b,atol,rtol) in enumerate(cases):
            ok=bool(expected(a,b,atol,rtol));exact=np.array([a],dtype='<f8').tobytes()==np.array([b],dtype='<f8').tobytes()
            run(host,prefix,f'scalar-{i}',{'v':np.array([[a]])},{'v':np.array([[b]])},{'atol':atol,'rtol':rtol},0 if ok else 2,ok,exact)
            run(host,prefix,f'reverse-{i}',{'v':np.array([[b]])},{'v':np.array([[a]])},{'atol':atol,'rtol':rtol},0 if ok else 2,ok,exact)
        for same in (False,True):
            run(host,prefix,f'nan-{same}',{'v':np.array([[np.nan]])},{'v':np.array([[np.nan]])},{'equal_nan':same},0 if same else 2,same,True)
        def experiment(delta):
            cell=np.empty((1,2),dtype=object)
            cell[0,0]=np.array([[1+delta,2+delta]],dtype=np.float32)
            cell[0,1]={'wave':np.array([[1+delta+2j,3+(4+delta)*1j]]),'mask':np.array([[True,False]]),'label':'科研🌙'}
            sparse=csc_matrix((np.array([1+delta,2+delta],dtype=np.float64),np.array([1,0]),np.array([0,2])),shape=(2,1))
            return {'experiment':{'cells':cell,'system':sparse,'ids':np.array([[2**64-1]],dtype=np.uint64)}}
        run(host,prefix,'mixed-close',experiment(0),experiment(.125),{'atol':.125},0,True,False)
        report=run(host,prefix,'mixed-truncated',experiment(0),experiment(.125),{'max_samples':1},2,False,False)
        assert report['truncated'] and len(report['samples'])==1 and report['differences']>1
        run(host,prefix,'integer-strict',{'v':np.array([[2**64-1]],dtype=np.uint64)},{'v':np.array([[2**64-2]],dtype=np.uint64)},{'atol':1e308},2,False,False)
        root_order=run(host,prefix,'root-order',{'one':np.array([[1.]]),'two':np.array([[2.]])},{'two':np.array([[2.]]),'one':np.array([[1.]])},{},2,False,False)
        assert root_order['variable_order_changed'] and root_order['samples'][0]['kind']=='root_order'
        good=OUT/'scalar-0-left.mat'
        for i,opts in enumerate([{'atol':-1},{'rtol':True},{'equal_nan':1},{'max_samples':1.5},{'max_samples':257},{'atoll':1}]):
            path=OUT/'invalid-options.json';path.write_text(json.dumps(opts),encoding='utf-8')
            out=OUT/f'failed-{host}-{i}.json';out.unlink(missing_ok=True)
            result=subprocess.run(prefix+['diff-tree-close',good,good,out,path],capture_output=True,text=True,encoding='utf-8',timeout=60)
            assert result.returncode==1 and not out.exists(),(result.stdout,result.stderr)
            checks.append({'host':host,'case':f'invalid-options-{i}','status':'passed','no_partial_output':True})
        bad=OUT/'truncated.mat';bad.write_bytes(good.read_bytes()[:-1])
        out=OUT/f'bad-{host}.json';out.unlink(missing_ok=True)
        result=subprocess.run(prefix+['diff-tree-close',good,bad,out],capture_output=True,text=True,encoding='utf-8',timeout=60)
        assert result.returncode==1 and not out.exists()
        checks.append({'host':host,'case':'invalid-right-file','status':'passed','no_partial_output':True})
    report={'status':'passed','version':VERSION,'passed':len(checks),'checks':checks,'oracle':'SciPy MAT production, NumPy raw storage and 1200-digit Decimal symmetric scalar oracle'}
    (ROOT/'verification/reports').mkdir(parents=True,exist_ok=True)
    (ROOT/f'verification/reports/tree-close-v{VERSION}.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8',newline='\n')
    print(f"Mixed-tree tolerance checks: {len(checks)} passed")

if __name__=='__main__':main()
