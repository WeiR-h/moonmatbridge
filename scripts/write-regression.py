"""Paired fixed-revision MatSink measurements; separate from same-version interface comparisons."""
from pathlib import Path
import argparse,hashlib,json,platform,statistics,time,uuid
import release_evidence as e
R=e.ROOT;OUT=R/'verification/local/write-regression'

def main():
    p=argparse.ArgumentParser();p.add_argument('--baseline-ref',default='v0.1.5');p.add_argument('--candidate-ref',required=True);p.add_argument('--case',action='append');a=p.parse_args()
    rev=e.load('paired_write_revisions','performance-revisions.py');perf=e.load('paired_write_perf','performance.py');prod=e.load('paired_write_sources','performance-summary.py')
    roots={};commits={}
    for role,ref in [('baseline',a.baseline_ref),('candidate',a.candidate_ref)]:roots[role],commits[role]=rev.prepare(ref)
    version=e.read(roots['candidate']/'package.json')['version'];OUT.mkdir(parents=True,exist_ok=True)
    cases=[dict(x) for x in perf.fixtures() if x['name'] in ['dense-16m','nested-4m','sparse-100k']]
    seed=20261029;block=bytearray()
    for _ in range(32768):seed=(seed*1664525+1013904223)&0xffffffff;block.append(seed>>24)
    h=hashlib.sha256()
    for _ in range(8192):h.update(block)
    cases.append({'name':'resident-256m','path':'@large','payload_bytes':268435456,'raw_sha256':h.hexdigest(),'generator':{'seed':20261029,'block_bytes':32768,'repeats':8192,'lcg_multiplier':1664525,'lcg_increment':1013904223}})
    report={'status':'running','version':version,'comparison':'Same MatSink API, paired frozen revisions; historical memory-versus-sink reports remain separate','baseline_commit':commits['baseline'],'candidate_commit':commits['candidate'],'baseline_runtime_source_sha256':prod.snapshot(commits['baseline'])[1],'candidate_runtime_source_sha256':prod.snapshot(commits['candidate'])[1],'source_scopes':{k:e.scopes(c) for k,c in commits.items()},'environment':{'toolchain':e.read_toolchain(),'platform':platform.platform()},'protocol':{'warmup_per_batch':5,'batches':3,'samples_per_batch':10,'memory_processes':3,'paired_order':'baseline then candidate per batch','core':'Resident tree, discard sink; excludes startup/preparation/disk','file':'Resident tree, positional write, close and no-overwrite publication; warm OS cache; startup excluded','memory':'Whole-process high-water RSS, includes resident input and preparation; not encoder-only allocation'},'fixtures':[{k:v for k,v in c.items() if k!='path'} for c in cases],'measurement_adapter_sha256':{n:e.digest(R/'scripts'/n) for n in ['write-regression.py','bench-sink-js.mjs','performance.py']},'partial':bool(a.case),'results':[]}
    runid=uuid.uuid4().hex
    def sample(role,host,case,encoding,scope,kind):
        root=roots[role];target=OUT/(uuid.uuid4().hex+'.mat')
        prefix=[root/'_build/native/release/build/cmd/bench'/('bench.exe' if platform.system()=='Windows' else 'bench'),'sink-write'] if host=='native' else ['node','--expose-gc',R/'scripts/bench-sink-js.mjs',root/'_build/js/release/build/bench_bridge/bench_bridge.js']
        start=time.perf_counter();r=json.loads(perf.command(prefix+[case['path'],'sink',encoding,scope,kind,target],timeout=1800));r['process_wall_ms']=(time.perf_counter()-start)*1000
        assert r['status']=='ok' and r['max_request']<=1048576
        if scope=='file':
            assert target.stat().st_size==r['output_bytes']
            h=hashlib.sha256();canonical=hashlib.sha256()
            with target.open('rb') as f:
                first=f.read(116);h.update(first)
                for b in iter(lambda:f.read(1048576),b''):h.update(b);canonical.update(b)
            r['output_sha256']=h.hexdigest();r['without_creation_description_sha256']=canonical.hexdigest()
            if kind=='memory':
                if case['name']=='resident-256m':
                    import numpy as np
                    from scipy.io import loadmat
                    data=loadmat(target,variable_names=['simulation'])['simulation'];assert data.shape==(33554432,1) and data.dtype==np.float64
                    assert hashlib.sha256(memoryview(data.ravel(order='F')).cast('B')).hexdigest()==case['raw_sha256'];del data
                else:perf.mixed.assert_file_equal(target,Path(case['path']))
                r['independent_consumption']='SciPy with exact large raw-byte hash'
            target.unlink()
        return r
    for c in cases:
        if a.case and c['name'] not in a.case:continue
        for host in ['native','js']:
            for encoding in ['plain','compressed']:
                for scope in ['core','file']:
                    memory={k:[sample(k,host,c,encoding,scope,'memory')] for k in roots};batches={k:[] for k in roots}
                    for _ in range(3):
                        for k in roots:batches[k].append(sample(k,host,c,encoding,scope,'timing'))
                    row={'case':c['name'],'host':host,'encoding':encoding,'scope':scope}
                    for k in roots:
                        memory[k]+=[sample(k,host,c,encoding,scope,'memory') for _ in range(2)]
                        samples=[s for b in batches[k] for s in b['samples_ms']];assert len(samples)==30
                        hashes={b.get('output_sha256') for b in batches[k]+memory[k]};assert len(hashes)==1
                        median=statistics.median(samples)
                        row[k]={'status':'measured','batches':batches[k],'memory_processes':memory[k],'samples_ms':samples,'median_ms':median,'p95_ms':sorted(samples)[28],'peak_bytes':statistics.median(b['peak_bytes'] for b in memory[k]),'payload_MiB_per_second':c['payload_bytes']/1048576/(median/1000),'output_bytes':batches[k][0]['output_bytes'],'output_sha256':hashes.pop()}
                    row['speedup']=row['baseline']['median_ms']/row['candidate']['median_ms'];row['memory_reduction']=1-row['candidate']['peak_bytes']/row['baseline']['peak_bytes']
                    if scope=='file' and encoding=='plain':assert memory['baseline'][0]['without_creation_description_sha256']==memory['candidate'][0]['without_creation_description_sha256']
                    report['results'].append(row);(OUT/(runid+'.json')).write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8',newline='\n');print(c['name'],host,encoding,scope,round(row['speedup'],3),flush=True)
    report['status']='measured';report['regressions_over_10_percent']=[{k:r[k] for k in ['case','host','encoding','scope','speedup','memory_reduction']} for r in report['results'] if r['speedup']<1/1.1 or r['memory_reduction']<-.1]
    report['engineering_targets']=[{'case':r['case'],'scope':r['scope'],'time_reduction':1-1/r['speedup'],'goal':.10,'passed':r['speedup']>=1/.9} for r in report['results'] if r['case']=='sparse-100k' and r['host']=='js' and r['encoding']=='plain']
    e.save(f'write-regression{"-partial-"+runid[:8] if a.case else ""}-v{version}.json',report)

if __name__=='__main__':main()
