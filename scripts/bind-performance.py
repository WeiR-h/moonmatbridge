"""Bind complete paired measurements to explicit immutable revisions."""
import argparse, itertools, math, statistics
from pathlib import Path
import release_evidence as e

CORE = {'dense-16m':['read','write'], 'dense-be-16m':['read'], 'complex-16m':['read','write'], 'nested-4m':['read','write'], 'sparse-100k':['read','write'], 'compressed-random-16m':['read'], 'zeros-16m':['compress'], 'select-1-of-16':['select']}

def expected_rows(kind):
    if kind=='core':return {(c,h,o) for c,ops in CORE.items() for h in ['native','js'] for o in ops}
    if kind=='file':return set(itertools.product(['select-1-of-16','large-uncompressed','large-compressed'],['native','js']))
    return set(itertools.product(['dense-16m','nested-4m','sparse-100k','resident-256m'],['native','js'],['plain','compressed'],['core','file']))

def row_key(row,kind):
    case=row['case']['name'] if isinstance(row['case'],dict) else row['case']
    return (case,row['host'],row['operation']) if kind=='core' else (case,row['host']) if kind=='file' else (case,row['host'],row['encoding'],row['scope'])


def validate_samples(data,kind,baseline,candidate,runtime,toolchain,complete=True):
    assert data['status']=='measured' and (not complete or not data.get('partial')),'Incomplete measurement'
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
    assert actual and len(actual)==len(set(actual)) and set(actual)<=expected_rows(kind),'Duplicate or substituted case'
    if complete:assert set(actual)==expected_rows(kind),'Missing measurement case'
    assert data['protocol']['warmup_per_batch']==5 and data['protocol']['batches']==3 and data['protocol']['samples_per_batch']==10,'Wrong measurement protocol'


def metric_flags(data,kind):
    flags=set()
    for r in data['results']:
        key=row_key(r,kind)
        medians=[];peaks=[]
        for role in ['baseline','candidate']:
            batches=r[role]['batches'] if kind=='write' else r['batches'][role]
            medians.append(statistics.median(t for b in batches for t in b['samples_ms']))
            memory=r[role]['memory_processes'] if kind=='write' else r['memory_processes'][role] if kind=='file' else r['baseline_peak_bytes_samples' if role=='baseline' else 'peak_bytes_samples']
            peaks.append(statistics.median(p['peak_bytes'] if isinstance(p,dict) else p for p in memory))
        speed=medians[0]/medians[1];memory=1-peaks[1]/peaks[0]
        assert math.isclose(speed,r['speedup'],rel_tol=1e-9) and math.isclose(memory,r['memory_reduction'],abs_tol=1e-9),'Summary differs from retained samples'
        if speed<1/1.1:flags.add((key,'time'))
        if memory<-.1:flags.add((key,'peak'))
    declared=[row_key(r,kind) for r in data['regressions_over_10_percent']]
    assert len(declared)==len(set(declared)) and set(declared)=={key for key,metric in flags},'Raw regression flags differ from samples'
    return flags


def regression_review(data,kind,rechecks=()):
    histories={}
    for index,report in enumerate([data,*rechecks]):
        flags=metric_flags(report,kind)
        for row in report['results']:
            key=row_key(row,kind)
            for metric in ['time','peak']:
                histories.setdefault((key,metric),[]).append({'report_index':index,'over_threshold':(key,metric) in flags})
    result={'status':'verified','policy':'Retain the initial cohort and every recheck. Two threshold exceedances for the same case and metric block publication; a single exceedance needs a later matching non-exceedance.','resolved':[],'pending':[],'confirmed':[]}
    for (key,metric),history in histories.items():
        count=sum(x['over_threshold'] for x in history)
        if not count:continue
        item={'case_key':list(key),'metric':metric,'history':history}
        result['confirmed' if count>=2 else 'pending' if history[-1]['over_threshold'] else 'resolved'].append(item)
    if result['confirmed'] or result['pending']:result['status']='blocked'
    return result


def validate_report(data,kind,baseline,candidate,runtime,toolchain,rechecks=()):
    validate_samples(data,kind,baseline,candidate,runtime,toolchain)
    original={row_key(r,kind):r for r in data['results']}
    for report in rechecks:
        validate_samples(report,kind,baseline,candidate,runtime,toolchain,complete=False)
        assert report['version']==data['version'] and report['protocol']==data['protocol'],'Recheck protocol differs'
        env=lambda d:{k:v for k,v in d['environment'].items() if k!='processor_affinity_receipt'}
        assert env(report)==env(data),'Recheck environment differs'
        if 'processor_affinity_receipt' in report['environment'] and 'processor_affinity_receipt' in data['environment']:
            assert report['environment']['processor_affinity_receipt']==data['environment']['processor_affinity_receipt'],'Recheck processor context differs'
        for field in ['fixtures','measurement_adapters','measurement_adapter_sha256']:
            if field in data:assert report.get(field)==data[field],'Recheck input or adapter differs'
        for row in report['results']:
            assert row['case']==original[row_key(row,kind)]['case'],'Recheck fixture differs'
    result=regression_review(data,kind,rechecks)
    assert result['status']=='verified',('Unresolved or reproducible regression',result)
    return result


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--baseline-ref');p.add_argument('--candidate-ref',default='HEAD')
    p.add_argument('--core-report',type=Path);p.add_argument('--file-report',type=Path);p.add_argument('--write-report',type=Path)
    for kind in ['core','file','write']:p.add_argument('--'+kind+'-recheck',action='append',type=Path,default=[])
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
        data=e.read(path);checks=[p.resolve() for p in getattr(a,kind+'_recheck')]
        assert all(p.parent==e.REPORTS.resolve() for p in checks),'Recheck must be retained'
        review=validate_report(data,kind,baseline,source,scopes['runtime']['sha256'],tool,[e.read(p) for p in checks])
        cohorts.append({'file':path.name,'kind':kind,'rows':len(data['results']),'sha256':e.digest(path),'measured_commit':source,'rechecks':[{'file':p.name,'sha256':e.digest(p)} for p in checks],'regression_review':review})
    e.save(f'performance-binding-v{v}.json',{'status':'verified','version':v,'reference':a.baseline_ref or baseline,'scopes':scopes,'toolchain':tool,'cohorts':cohorts,'scope':'Complete fixed-input paired 24 core, 6 file and 32 sink scenarios; all original samples retained.'})
    print('Fixed revisions, complete case matrices, samples and environment verified')

if __name__=='__main__':main()
