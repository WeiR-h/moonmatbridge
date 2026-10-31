"""Bind complete paired measurements to explicit immutable revisions."""
import argparse, itertools, math
from pathlib import Path
import release_evidence as e

CORE = {'dense-16m':['read','write'], 'dense-be-16m':['read'], 'complex-16m':['read','write'], 'nested-4m':['read','write'], 'sparse-100k':['read','write'], 'compressed-random-16m':['read'], 'zeros-16m':['compress'], 'select-1-of-16':['select']}

def expected_rows(kind):
    if kind=='core':return {(c,h,o) for c,ops in CORE.items() for h in ['native','js'] for o in ops}
    if kind=='file':return set(itertools.product(['select-1-of-16','large-uncompressed','large-compressed'],['native','js']))
    return set(itertools.product(['dense-16m','nested-4m','sparse-100k','resident-256m'],['native','js'],['plain','compressed'],['core','file']))

def validate_report(data,kind,baseline,candidate,runtime,toolchain):
    assert data['status']=='measured' and not data.get('partial'),'Incomplete measurement'
    assert data['baseline_commit']==baseline and data.get('candidate_commit',data.get('candidate_head_commit'))==candidate,'Wrong measured revision'
    assert data['candidate_runtime_source_sha256']==runtime and data['environment']['toolchain']==toolchain,'Measurement identity differs'
    actual=[]
    for r in data['results']:
        case=r['case']['name'] if kind=='file' else r['case']
        actual.append((case,r['host'],r['operation']) if kind=='core' else (case,r['host']) if kind=='file' else (case,r['host'],r['encoding'],r['scope']))
        for role in ['baseline','candidate']:
            batches=r[role]['batches'] if kind=='write' else r['batches'][role]
            assert len(batches)==3 and all(len(b['samples_ms'])==10 for b in batches),'Missing timing samples'
            assert all(math.isfinite(t) and t>0 for b in batches for t in b['samples_ms']),'Invalid timing sample'
            if kind=='core' and 'native_repetitions' in data['protocol']:
                counts=data['protocol']['native_repetitions']
                assert set(counts)==set(CORE) and data['protocol']['js_repetitions']==1,'Incomplete repeat policy'
                repeat=counts[case] if r['host']=='native' else 1
                assert type(repeat) is int and 1<=repeat<=1024,'Invalid repeat policy'
                for b in batches:
                    assert b['operations_per_sample']==repeat,'Different operation counts'
                    totals=b['samples_total_ms']
                    assert len(totals)==10 and all(math.isfinite(t) and t>0 for t in totals),'Missing raw totals'
                    assert all(math.isclose(s,t/repeat,rel_tol=1e-12,abs_tol=1e-9) for s,t in zip(b['samples_ms'],totals)),'Incorrect sample normalization'
            peaks=r[role]['memory_processes'] if kind=='write' else r['memory_processes'][role] if kind=='file' else r['baseline_peak_bytes_samples' if role=='baseline' else 'peak_bytes_samples']
            assert len(peaks)==3,'Missing process memory samples'
    assert len(actual)==len(set(actual)) and set(actual)==expected_rows(kind),'Missing, duplicate or substituted case'
    assert data['protocol']['warmup_per_batch']==5 and data['protocol']['batches']==3 and data['protocol']['samples_per_batch']==10,'Wrong measurement protocol'
    assert not data['regressions_over_10_percent'],'Unresolved regression'


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--baseline-ref');p.add_argument('--candidate-ref',default='HEAD')
    p.add_argument('--core-report',type=Path);p.add_argument('--file-report',type=Path);p.add_argument('--write-report',type=Path)
    a=p.parse_args();source=e.run(['git','rev-parse',a.candidate_ref+'^{commit}']);v=e.read(e.ROOT/'package.json')['version']
    assert e.scopes(source)==e.scopes(),'Working source differs from measured candidate'
    if a.core_report:core=a.core_report
    else:
        choices=[q for q in e.REPORTS.glob(f'performance-vs-*-v{v}.json') if 'partial' not in q.name and e.read(q).get('candidate_head_commit')==source]
        assert len(choices)==1,'Specify one complete core report';core=choices[0]
    baseline=e.run(['git','rev-parse',(a.baseline_ref or e.read(core)['baseline_commit'])+'^{commit}'])
    scopes=e.scopes();tool=e.read_toolchain();cohorts=[]
    for kind,path in [('core',core),('file',a.file_report or e.REPORTS/f'file-performance-v{v}.json'),('write',a.write_report or e.REPORTS/f'write-regression-v{v}.json')]:
        path=path.resolve();assert path.parent==e.REPORTS.resolve(),'Report must be retained in verification/reports'
        data=e.read(path);validate_report(data,kind,baseline,source,scopes['runtime']['sha256'],tool)
        cohorts.append({'file':path.name,'rows':len(data['results']),'sha256':e.digest(path),'measured_commit':source})
    e.save(f'performance-binding-v{v}.json',{'status':'verified','version':v,'reference':a.baseline_ref or baseline,'scopes':scopes,'toolchain':tool,'cohorts':cohorts,'scope':'Complete fixed-input paired 24 core, 6 file and 32 sink scenarios; all original samples retained.'})
    print('Fixed revisions, complete case matrices, samples and environment verified')

if __name__=='__main__':main()
