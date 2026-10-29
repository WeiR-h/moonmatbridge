"""Fixed-tree write cohorts: preloaded encoder and atomic file pipelines reported separately."""
from pathlib import Path
import argparse,hashlib,importlib.util,json,platform,statistics,subprocess,time,uuid
R=Path(__file__).resolve().parents[1]

def load(name,file):
 s=importlib.util.spec_from_file_location(name,R/'scripts'/file);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
perf=load('codec_perf','performance.py');evidence=load('write_evidence','performance-summary.py')
OUT=R/'verification/local/write-performance'

def write(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,indent=2)+'\n',encoding='utf-8',newline='\n')
def digest(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for b in iter(lambda:f.read(1048576),b''):h.update(b)
 return h.hexdigest()

def main():
 parser=argparse.ArgumentParser();parser.add_argument('--candidate-ref',required=True);parser.add_argument('--baseline-ref',default='85fef84de68b69b7e762c3c6317266bb6674ff84');parser.add_argument('--case',action='append');args=parser.parse_args()
 revisions=load('write_revisions','performance-revisions.py')
 folder,commit=revisions.prepare(args.candidate_ref)
 version=json.loads((folder/'package.json').read_bytes())['version']
 # The old public path runs in the same candidate with the same filesystem adapter.
 # Pin and compare its complete original writer implementations to the reference.
 old_files=[n for n in subprocess.check_output(['git','ls-tree','-r','--name-only',args.baseline_ref,'--','src'],cwd=R,text=True).splitlines() if Path(n).parent==Path('src') and n.endswith('.mbt') and not n.endswith(('_wbtest.mbt','_test.mbt')) and Path(n).name!='version.mbt']
 original={}
 for n in old_files:
  a=subprocess.check_output(['git','show',args.baseline_ref+':'+n],cwd=R)
  b=(folder/n).read_bytes();assert a.replace(b'\r\n',b'\n')==b.replace(b'\r\n',b'\n'),n
  original[n]=hashlib.sha256(a).hexdigest()
 fixtures=perf.fixtures();OUT.mkdir(parents=True,exist_ok=True)
 cases=[dict(next(x for x in fixtures if x['name']==n)) for n in ['dense-16m','nested-4m','sparse-100k']]
 seed=20261029;block=bytearray()
 for _ in range(32768):seed=(seed*1664525+1013904223)&0xffffffff;block.append(seed>>24)
 h=hashlib.sha256()
 for _ in range(8192):h.update(block)
 cases.append({'name':'resident-256m','path':'@large','payload_bytes':268435456,'raw_sha256':h.hexdigest(),'generator':{'seed':20261029,'block_bytes':32768,'repeats':8192,'lcg_multiplier':1664525,'lcg_increment':1013904223,'byte':'high 8 bits; unsigned 32-bit wrap'}})
 env=json.loads(perf.command(['node',R/'scripts/toolchain.mjs']))
 report={'status':'running','version':version,'candidate_commit':commit,'candidate_runtime_source_sha256':evidence.snapshot(commit)[1],'reference_commit':perf.command(['git','rev-parse',args.baseline_ref]),'old_writer_source_sha256':original,'comparison':'Retained memory writer versus bounded sink writer in the same frozen candidate; original writer files checked against fixed new-toolchain baseline; identical positional filesystem policy','environment':{'toolchain':env,'platform':platform.platform(),'node':perf.command(['node','--version'])},'protocol':{'warmup_per_batch':5,'batches':3,'samples_per_batch':10,'independent_memory_processes':3,'core':'Resident tree and discard sink; excludes preparation, startup and disk I/O','file':'Resident tree through same positional adapter, close and no-overwrite publication; excludes preparation and startup; warm filesystem cache; no fsync durability claim','process_wall':'Separate complete benchmark invocation including startup and tree preparation; not labeled CLI codec timing','memory':'Whole-process high-water RSS including resident input; pre-operation high-water separately recorded, not a direct encoder allocation counter'},'fixtures':[{k:v for k,v in c.items() if k!='path'} for c in cases],'results':[]}
 report['workspace_configuration']={'basis':'Logical live codec workspaces from the frozen source, not process RSS or a heap allocation counter; resident input, metadata plans and target-specific array representation are separate','chunk_bytes':1048576,'plain_output_block_max_bytes':1048576,'compressed_output_block_max_bytes':1048576,'compressed_raw_block_max_bytes':1048576,'compressed_history_and_raw_window_bytes':98303,'compressed_hash_tables_int32_entries':65536,'compressed_candidate_max_byte_entries':80000,'compressed_candidate_copy_max_bytes':80000,'backpatch_max_bytes':4,'metadata_budget_bytes':8388608,'max_tree_nodes':65536}
 partial=bool(args.case);runid=uuid.uuid4().hex
 def measure(host,case,implementation,encoding,scope,kind):
  target=OUT/(uuid.uuid4().hex+'.mat')
  if host=='native':cmd=[folder/'_build/native/release/build/cmd/bench'/('bench.exe' if platform.system()=='Windows' else 'bench'),'sink-write',case['path'],implementation,encoding,scope,kind,target]
  else:cmd=['node','--expose-gc',R/'scripts/bench-sink-js.mjs',folder/'_build/js/release/build/bench_bridge/bench_bridge.js',case['path'],implementation,encoding,scope,kind,target]
  start=time.perf_counter();result=json.loads(perf.command(cmd,timeout=1800));result['process_wall_ms']=(time.perf_counter()-start)*1000
  if result['status']=='ok':
   assert result['max_request']<=1048576 and result['written_bytes']>=result['output_bytes']
   if scope=='file':
    assert target.stat().st_size==result['output_bytes'];result['output_sha256']=digest(target)
    if kind=='memory':
     if case['name']=='resident-256m':
      import numpy as np
      from scipy.io import loadmat
      a=loadmat(target,variable_names=['simulation'])['simulation']
      assert a.shape==(33554432,1) and a.dtype==np.float64
      assert hashlib.sha256(memoryview(a.ravel(order='F')).cast('B')).hexdigest()==case['raw_sha256']
      del a
     else:perf.mixed.assert_file_equal(target,Path(case['path']))
     result['independent_consumption']='SciPy type/shape and exact raw numeric bytes, including the fixed large generator'
    target.unlink()
  else:assert not target.exists() and not Path(str(target)+'.tmp').exists()
  return result
 for case in cases:
  if args.case and case['name'] not in args.case:continue
  for host in ['native','js']:
   for encoding in ['plain','compressed']:
    for scope in ['core','file']:
     all_results={}
     for implementation in ['old','sink']:
      probe=measure(host,case,implementation,encoding,scope,'memory')
      if probe['status']=='error':
       assert case['name']=='resident-256m' and encoding=='compressed' and implementation=='old' and probe['code']=='file-limit',probe
       all_results[implementation]={'status':'unsupported','probe':probe,'reason':'Retained in-memory DEFLATE input quota is 64 MiB; not a speedup denominator'};continue
      batches=[measure(host,case,implementation,encoding,scope,'timing') for _ in range(3)]
      memory=[probe]+[measure(host,case,implementation,encoding,scope,'memory') for _ in range(2)]
      assert all(b['status']=='ok' for b in batches+memory)
      samples=[s for b in batches for s in b['samples_ms']];assert len(samples)==30
      median=statistics.median(samples)
      output=batches[0]['output_bytes'];assert all(b['output_bytes']==output for b in batches+memory)
      hashes={b.get('output_sha256') for b in batches+memory};assert len(hashes)==1
      all_results[implementation]={'status':'measured','batches':batches,'memory_processes':memory,'samples_ms':samples,'median_ms':median,'p95_ms':sorted(samples)[28],'payload_MiB_per_second':case['payload_bytes']/1048576/(median/1000),'peak_bytes':statistics.median(b['peak_bytes'] for b in memory),'output_bytes':output,'output_sha256':hashes.pop(),'max_request':max(b['max_request'] for b in batches+memory),'written_bytes':batches[0]['written_bytes']}
     row={'case':case['name'],'host':host,'encoding':encoding,'scope':scope,**all_results}
     if all_results['old']['status']=='measured':
      row['speedup']=all_results['old']['median_ms']/all_results['sink']['median_ms'];row['memory_reduction']=1-all_results['sink']['peak_bytes']/all_results['old']['peak_bytes']
      if encoding=='plain' and scope=='file':assert all_results['old']['output_sha256']==all_results['sink']['output_sha256']
     report['results'].append(row);write(OUT/f'{runid}.json',report)
     print(case['name'],host,encoding,scope,round(row.get('speedup',0),3),flush=True)
 report['status']='measured';report['partial']=partial
 assert evidence.snapshot(commit)[1]==report['candidate_runtime_source_sha256']
 write(R/f'verification/reports/write-performance{"-partial" if partial else ""}-v{version}.json',report)

if __name__=='__main__':main()
