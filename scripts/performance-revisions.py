"""Fixed-revision, paired codec/CLI measurements with all samples retained."""
from pathlib import Path
import argparse
import importlib.util
import json
import platform
import shutil
import statistics
import subprocess
import uuid
import zipfile

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('codec_perf',ROOT/'scripts/performance.py')
perf=importlib.util.module_from_spec(spec);spec.loader.exec_module(perf)
spec=importlib.util.spec_from_file_location('runtime_fingerprint',ROOT/'scripts/performance-summary.py')
evidence=importlib.util.module_from_spec(spec);spec.loader.exec_module(evidence)

def write(path,data):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8',newline='\n')

def revision(ref):
    return perf.command(['git','rev-parse',f'{ref}^{{commit}}'])

def prepare(ref):
    commit=revision(ref)
    directory=ROOT/'.local-tools'/f'performance-ref-{commit[:12]}'
    marker=directory/'.measured-revision.json'
    if not marker.exists():
        assert not directory.exists(), 'Use a new empty revision directory'
        directory.mkdir(parents=True)
        archive=perf.LOCAL/f'{commit}.zip'
        perf.command(['git','archive','--format=zip',f'--output={archive}',commit],cwd=Path(perf.command(['git','rev-parse','--show-toplevel'])))
        with zipfile.ZipFile(archive) as package:
            for item in package.infolist(): assert (directory/item.filename).resolve().is_relative_to(directory.resolve())
            package.extractall(directory)
        # Only timing adapters are added to older revisions that predate them.
        for name in ('src/bench_bridge','src/cmd/bench'):
            if not (directory/name).exists(): shutil.copytree(ROOT/name,directory/name)
        version=json.loads((directory/'package.json').read_bytes())['version']
        if tuple(map(int,version.split('.'))) < (0,0,8):
            for name in ('src/bench_bridge/bench.mbt','src/cmd/bench/main.mbt'):
                p=directory/name
                p.write_text(p.read_text(encoding='utf-8').replace('@mat.read_selected(bytes, ["v00"]).variables','@mat.read_tree(bytes).select(["v00"])'),encoding='utf-8',newline='\n')
        write(marker,{'commit':commit,'version':version})
    assert json.loads(marker.read_bytes())['commit']==commit
    previous_root=evidence.ROOT
    evidence.ROOT=Path(perf.command(['git','rev-parse','--show-toplevel']))
    expected=evidence.snapshot(commit)
    evidence.ROOT=directory
    assert evidence.snapshot()==expected, 'Frozen revision source differs from its Git commit'
    evidence.ROOT=previous_root
    if (ROOT/'.local-toolchain.json').exists():
        shutil.copyfile(ROOT/'.local-toolchain.json',directory/'.local-toolchain.json')
    build(directory)
    return directory,commit

def build(directory):
    perf.command(['node',ROOT/'scripts/build-bench.mjs',directory])
    perf.command(['node',directory/'scripts/build-native.mjs'],cwd=directory)
    perf.command(['node',directory/'scripts/moon.mjs','build','src/bridge','--target','js','--release','--deny-warn'],cwd=directory)

def measure(directory,host,fixture,operation,kind):
    if host=='native':
        executable=directory/'_build/native/release/build/cmd/bench'/('bench.exe' if platform.system()=='Windows' else 'bench')
        args=[executable,fixture['path'],operation,kind]
    else:
        args=['node','--expose-gc',ROOT/'scripts/bench-js.mjs',directory/'_build/js/release/build/bench_bridge/bench_bridge.js',fixture['path'],operation,kind]
    result=json.loads(perf.command(args))
    assert result['checksum']>0 and result['peak_bytes']>0
    return result

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--baseline-ref',default='v0.0.9')
    parser.add_argument('--candidate-ref',help='Frozen Git revision; omit to measure the current source tree')
    parser.add_argument('--case',action='append')
    parser.add_argument('--host',action='append',choices=['native','js'])
    args=parser.parse_args()
    fixtures=perf.fixtures()
    if args.case: assert set(args.case)<=set(f['name'] for f in fixtures)
    baseline,base_sha=prepare(args.baseline_ref)
    if args.candidate_ref:
        candidate,candidate_sha=prepare(args.candidate_ref)
    else:
        candidate=ROOT;candidate_sha=revision('HEAD');build(candidate)
    evidence.ROOT=baseline
    baseline_before=evidence.snapshot()
    evidence.ROOT=candidate
    runtime_before=evidence.snapshot()
    version=json.loads((candidate/'package.json').read_bytes())['version']
    config_path=ROOT/'.local-toolchain.json'
    config=json.loads(config_path.read_bytes()) if config_path.exists() else {}
    report={'status':'running','version':version,'baseline_ref':args.baseline_ref,'baseline_commit':base_sha,'baseline_version':json.loads((baseline/'package.json').read_bytes())['version'],
        'baseline_runtime_source_sha256':baseline_before[1],'candidate_ref':args.candidate_ref,'candidate_head_commit':candidate_sha,'candidate_runtime_source_sha256':runtime_before[1],
        'candidate_source_mode':'fixed Git revision' if args.candidate_ref else 'current working source; runtime hash checked before and after',
        'environment':{'platform':platform.platform(),'architecture':platform.machine(),'node':perf.command(['node','--version']),
            'moon':perf.command(['node',ROOT/'scripts/moon.mjs','version']),
            'compiler':perf.command([config.get('gcc','cc'),'--version']).splitlines()[0],'build':'same toolchain, --release, one compiler job'},
        'protocol':{'warmup_per_batch':5,'batches':3,'samples_per_batch':10,'paired_order':'baseline then candidate, repeated three times',
            'core_scope':'input preloaded; write tree prepared; no startup or filesystem timing; JS GC outside samples',
            'memory':'three independent processes per revision, one operation, no warmup; full process peak working set/RSS',
            'cli':'five warmups followed by 30 full process invocations per revision; includes startup and disk I/O'},
        'fixtures':[{k:v for k,v in f.items() if k!='path'} for f in fixtures],'results':[]}
    partial=bool(args.case or args.host)
    stem=f'performance-v{version}-vs-{base_sha[:7]}'
    run_id=uuid.uuid4().hex
    report['run_id']=run_id
    run_path=perf.LOCAL/f'{stem}-{run_id}.json'
    for fixture in fixtures:
        if args.case and fixture['name'] not in args.case: continue
        for operation in fixture['operations']:
            for host in args.host or ['native','js']:
                batches={'baseline':[],'candidate':[]}
                for _ in range(3):
                    for label,directory in [('baseline',baseline),('candidate',candidate)]:
                        batches[label].append(measure(directory,host,fixture,operation,'timing'))
                raw={k:[s for b in v for s in b['samples_ms']] for k,v in batches.items()}
                peaks={k:[measure(d,host,fixture,operation,'memory')['peak_bytes'] for _ in range(3)] for k,d in [('baseline',baseline),('candidate',candidate)]}
                times={k:statistics.median(v) for k,v in raw.items()}
                rss={k:statistics.median(v) for k,v in peaks.items()}
                row={'case':fixture['name'],'operation':operation,'host':host,'batches':batches,
                    'samples_ms':raw['candidate'],'baseline_samples_ms':raw['baseline'],'median_ms':times['candidate'],
                    'baseline_median_ms':times['baseline'],'p95_ms':sorted(raw['candidate'])[28],
                    'baseline_p95_ms':sorted(raw['baseline'])[28],'speedup':times['baseline']/times['candidate'],
                    'time_reduction':1-times['candidate']/times['baseline'],'peak_bytes_samples':peaks['candidate'],
                    'baseline_peak_bytes_samples':peaks['baseline'],'peak_bytes':rss['candidate'],'baseline_peak_bytes':rss['baseline'],
                    'memory_reduction':1-rss['candidate']/rss['baseline'],
                    'payload_MiB_per_second':fixture['payload_bytes']/1048576/(times['candidate']/1000)}
                row['baseline_cli']=perf.cli_measure(baseline,host,fixture,operation)
                row['cli']=perf.cli_measure(candidate,host,fixture,operation)
                row['output_bytes']=row['cli']['output_bytes']
                row['baseline_output_bytes']=row['baseline_cli']['output_bytes']
                row['cli_speedup']=row['baseline_cli']['median_ms']/row['cli']['median_ms']
                report['results'].append(row)
                write(run_path,report)
                print(f"{fixture['name']}:{operation}:{host}: {row['speedup']:.3f}x; peak reduction {row['memory_reduction']:.1%}",flush=True)
    assert evidence.snapshot()==runtime_before, 'Runtime changed while measurements were running'
    evidence.ROOT=baseline
    assert evidence.snapshot()==baseline_before, 'Baseline runtime changed during measurement'
    report['status']='measured'
    report['partial']=partial
    report['runtime_unchanged']=True
    report['targets']=[]
    for row in report['results']:
        if row['case']=='compressed-random-16m' and base_sha.startswith('4d1e261'):
            report['targets'].append({'case':row['case'],'host':row['host'],'goal':'compressed core read time -25%','passed':row['time_reduction']>=.25})
        if row['operation']=='select' and row['host']=='native' and base_sha.startswith(('4d1e261','b9df1ed')):
            report['targets'].append({'case':row['case'],'host':row['host'],'goal':'native select process peak -10% versus v0.0.9' if base_sha.startswith('4d1e261') else 'native select process peak -40% versus v0.0.5',
                'passed':row['memory_reduction']>=(.10 if base_sha.startswith('4d1e261') else .40)})
    report['regressions_over_10_percent']=[{'case':r['case'],'operation':r['operation'],'host':r['host'],'speedup':r['speedup'],'memory_reduction':r['memory_reduction']} for r in report['results'] if r['speedup']<1/1.1 or r['memory_reduction']<-.1]
    report['scope']='Fixed inputs and same-machine paired revisions. Per-case engineering targets; historical measurements remain independent.'
    write(run_path,report)
    destination=ROOT/'verification/reports'/f'performance-vs-{base_sha[:7]}{"-partial-"+run_id[:8] if partial else ""}-v{version}.json'
    write(destination,report)
    print(str(destination),flush=True)

if __name__=='__main__':main()
