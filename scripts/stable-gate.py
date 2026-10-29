"""Require real compatibility, runtime and public-consumption evidence."""
from pathlib import Path
import argparse,hashlib,importlib.util,json,sys,subprocess

ROOT=Path(__file__).resolve().parents[1]

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--evidence-version')
    parser.add_argument('--baseline-ref',default='v0.0.19')
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
    if tuple(map(int,current.split('-')[0].split('.'))) >= (0,1,1):
        for kind in ['v','ci']:
            path=reports/(f'v{version}.json' if kind=='v' else f'ci-v{version}.json')
            evidence=json.loads(path.read_bytes()) if path.exists() else {}
            actual=evidence.get('environment',{}).get('compiler_version','')
            try:compiler=tuple(map(int,actual.split('+')[0].split('.')))
            except ValueError:compiler=()
            if compiler<(0,10,16):problems.append(kind+':compiler-below-minimum')
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
    baseline=subprocess.check_output(['git','rev-parse',args.baseline_ref+'^{commit}'],cwd=ROOT,text=True).strip()
    core_name=f'performance-vs-{baseline[:7]}-v{args.performance_version}.json'
    perf=read(core_name,{'measured'})
    files=read(f'file-performance-v{args.performance_version}.json',{'measured'})
    for label,data,count in [('core',perf,24),('file',files,6)]:
        if data.get('baseline_commit')!=baseline:problems.append(label+':wrong-fixed-baseline')
        if data.get('candidate_runtime_source_sha256')!=runtime:problems.append(label+':runtime-source-changed')
        if len(data.get('results',[]))!=count:problems.append(label+':incomplete-fixed-cohort')
        if data.get('partial'):problems.append(label+':partial-cohort')
    if args.baseline_ref!='v0.0.19':
        actual=json.loads(subprocess.check_output(['node','scripts/toolchain.mjs'],cwd=ROOT,text=True))
        for label,data in [('core',perf),('file',files)]:
            if data.get('environment',{}).get('toolchain')!=actual:problems.append(label+':toolchain-changed')
    followups=[read(name,{'measured'}) for name in args.followup]
    for label,data in [('core',perf),('file',files)]:
        # The first cohort captures the new toolchain baseline. Two runs of the
        # exact same frozen commit measure control variability, not a regression.
        # Both complete raw cohorts remain public. Later candidates must compare
        # with a different frozen revision or prove runtime/toolchain equality.
        candidate=data.get('candidate_head_commit') if label=='core' else data.get('candidate_commit')
        if candidate==baseline:
            if data.get('baseline_runtime_source_sha256')!=runtime:problems.append(label+':baseline-runtime-changed')
            continue
        for row in data.get('results',[]):
            if label=='core' and row.get('cli_speedup',1)<1/1.1:
                matching=[r for report in followups if report.get('candidate_runtime_source_sha256')==runtime and report.get('followup_of_sha256')==sources[core_name] for r in report.get('results',[]) if (r.get('case'),r.get('operation'),r.get('host'))==(row.get('case'),row.get('operation'),row.get('host')) and 'cli_speedup' in r]
                if not matching or matching[-1]['cli_speedup']<1/1.1:problems.append('core:cli-repeat-required:'+row['case']+':'+row['host'])
            if row.get('speedup',0)>=1/1.1 and row.get('memory_reduction',-1)>=-.1:continue
            # Explicit later follow-up reports only; never choose the best sample
            # or silently replace the fixed full cohort.
            expected=sources[core_name] if label=='core' else sources[f'file-performance-v{args.performance_version}.json']
            matches=[r for report in followups if report.get('candidate_runtime_source_sha256')==runtime and report.get('followup_of_sha256')==expected for r in report.get('results',[]) if (r.get('case'),r.get('operation'),r.get('host'))==(row.get('case'),row.get('operation'),row.get('host'))]
            if not matches or matches[-1]['speedup']<1/1.1 or matches[-1]['memory_reduction']<-.1:problems.append(label+':repeat-required:'+str(row.get('case'))+':'+row.get('host',''))
    result={'status':'blocked' if problems else 'ready','version':current,'evidence_version':version,'performance_version':args.performance_version,'runtime_source_sha256':runtime,'evidence_sha256':sources,'blockers':problems,'scope':'Public basic-class data compatibility, real Octave Unicode, fixed-runtime performance and public package/assets; MATLAB execution is not asserted.'}
    (reports/f'stable-gate-v{current}.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(result,indent=2))
    if problems:raise SystemExit(1)

if __name__=='__main__':main()
