"""Require real compatibility, runtime and public-consumption evidence."""
from pathlib import Path
import argparse,hashlib,importlib.util,json,sys

ROOT=Path(__file__).resolve().parents[1]

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--evidence-version')
    parser.add_argument('--performance-version',required=True)
    parser.add_argument('--followup',action='append',default=[])
    args=parser.parse_args()
    current=json.loads((ROOT/'package.json').read_bytes())['version']
    version=args.evidence_version or current
    reports=ROOT/'verification/reports'
    problems=[];sources={}
    def read(file,statuses):
        path=reports/file
        if not path.exists():problems.append('missing:'+file);return {}
        data=json.loads(path.read_bytes());sources[file]=hashlib.sha256(path.read_bytes()).hexdigest()
        if data.get('status') not in statuses:problems.append('status:'+file)
        return data
    for kind in ['v','compatibility','name-encoding','api-contract','ci','mooncakes','public-downloads','workflows-public','tree-operations-public','source-operations-public','tree-close-public','licenses']:
        file=f'v{version}.json' if kind=='v' else f'{kind}-v{version}.json'
        read(file,{'passed'})
    octave=read(f'octave-v{version}.json',{'passed'})
    if octave.get('unicode_storage',{}).get('status')!='passed':problems.append('actual-unicode-producer-receipt')
    variants=read(f'producer-variants-v{version}.json',{'classified'})
    classified={r['sha256'] for r in variants.get('cases',[]) if r.get('classification')=='nonconforming_producer_variant'}
    gaps=read(f'compatibility-gaps-v{version}.json',{'characterized'})
    for case in gaps.get('cases',[]):
        state=case.get('compatibility_state','')
        if state.startswith('unresolved') and case.get('sha256') not in classified:problems.append('unresolved:'+case['file'])
    spec=importlib.util.spec_from_file_location('production',ROOT/'scripts/performance-summary.py')
    production=importlib.util.module_from_spec(spec);spec.loader.exec_module(production)
    _,runtime=production.snapshot()
    perf=read(f'performance-vs-8a1f479-v{args.performance_version}.json',{'measured'})
    files=read(f'file-performance-v{args.performance_version}.json',{'measured'})
    for label,data,count in [('core',perf,24),('file',files,6)]:
        if not data.get('baseline_commit','').startswith('8a1f479'):problems.append(label+':wrong-fixed-baseline')
        if data.get('candidate_runtime_source_sha256')!=runtime:problems.append(label+':runtime-source-changed')
        if len(data.get('results',[]))!=count:problems.append(label+':incomplete-fixed-cohort')
        if data.get('partial'):problems.append(label+':partial-cohort')
    followups=[read(name,{'measured'}) for name in args.followup]
    for label,data in [('core',perf),('file',files)]:
        for row in data.get('results',[]):
            if row.get('speedup',0)>=1/1.1 and row.get('memory_reduction',-1)>=-.1:continue
            # Explicit later follow-up reports only; never choose the best sample
            # or silently replace the fixed full cohort.
            expected=sources[f'performance-vs-8a1f479-v{args.performance_version}.json'] if label=='core' else sources[f'file-performance-v{args.performance_version}.json']
            matches=[r for report in followups if report.get('candidate_runtime_source_sha256')==runtime and report.get('followup_of_sha256')==expected for r in report.get('results',[]) if (r.get('case'),r.get('operation'),r.get('host'))==(row.get('case'),row.get('operation'),row.get('host'))]
            if not matches or matches[-1]['speedup']<1/1.1 or matches[-1]['memory_reduction']<-.1:problems.append(label+':repeat-required:'+str(row.get('case'))+':'+row.get('host',''))
    result={'status':'blocked' if problems else 'ready','version':current,'evidence_version':version,'performance_version':args.performance_version,'runtime_source_sha256':runtime,'evidence_sha256':sources,'blockers':problems,'scope':'Public basic-class data compatibility, real Octave Unicode, fixed-runtime performance and public package/assets; MATLAB execution is not asserted.'}
    (reports/f'stable-gate-v{current}.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(result,indent=2))
    if problems:raise SystemExit(1)

if __name__=='__main__':main()
