"""Fixed-revision file pipelines. Builds identical development adapters around old/new APIs."""
from pathlib import Path
import argparse,hashlib,importlib.util,json,platform,shutil,statistics,subprocess,zipfile,zlib,struct,time
import numpy as np
ROOT=Path(__file__).resolve().parents[1]
LOCAL=ROOT/'verification/local/file-performance'

def load(name,file):
 s=importlib.util.spec_from_file_location(name,ROOT/'scripts'/file);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
perf=load('codec_perf','performance.py')
evidence=load('runtime_evidence','performance-summary.py')
original_production=evidence.production
evidence.production=lambda n: original_production(n) and not any(x in ('file_bench','file_bench_bridge') for x in Path(n).parts)

def write(p,v):
 p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,indent=2)+'\n',encoding='utf-8',newline='\n')

def fixtures():
 LOCAL.mkdir(parents=True,exist_ok=True)
 manifest=perf.LOCAL/'manifest.json'
 if not manifest.exists():perf.fixtures()
 one=next(v for v in json.loads(manifest.read_bytes())['cases'] if v['name']=='select-1-of-16')
 cases=[{'name':'select-1-of-16','path':one['path'],'variable':'v00','payload_bytes':16777216,'minimum_version':[0,0,16]}]
 rng=np.random.default_rng(20261017)
 block=rng.standard_normal(4096).astype('<f8').tobytes()
 wanted=rng.standard_normal(131072).astype('<f8').tobytes()
 def element(k,b):return struct.pack('<II',k,len(b))+b+bytes(-len(b)%8)
 def prefix(name,shape,size):return element(6,struct.pack('<II',6,0))+element(5,struct.pack('<ii',*shape))+element(1,name)+struct.pack('<II',9,size)
 big_prefix=prefix(b'big',(4096,8192),268435456)
 small=prefix(b'wanted',(256,512),len(wanted))+wanted
 header=b'MATLAB 5.0 MAT-file, MoonMatBridge fixed file benchmark'.ljust(116,b' ')+bytes(8)+b'\x00\x01IM'
 for compressed in (False,True):
  path=LOCAL/('large-compressed.mat' if compressed else 'large-uncompressed.mat')
  if not path.exists():
   with path.open('wb') as f:
    f.write(header)
    if compressed:
     encoder=zlib.compressobj(6);out=bytearray(encoder.compress(struct.pack('<II',14,len(big_prefix)+268435456)+big_prefix))
     for _ in range(8192):out.extend(encoder.compress(block))
     out.extend(encoder.flush());f.write(struct.pack('<II',15,len(out)));f.write(out)
     data=zlib.compress(struct.pack('<II',14,len(small))+small);f.write(struct.pack('<II',15,len(data)));f.write(data)
    else:
     f.write(struct.pack('<II',14,len(big_prefix)+268435456));f.write(big_prefix)
     for _ in range(8192):f.write(block)
     f.write(struct.pack('<II',14,len(small)));f.write(small)
  cases.append({'name':'large-compressed' if compressed else 'large-uncompressed','path':str(path),'variable':'wanted','payload_bytes':269484032,'minimum_version':[0,0,18] if compressed else [0,0,17]})
 for x in cases:x.update(bytes=Path(x['path']).stat().st_size,sha256=hashlib.sha256(Path(x['path']).read_bytes()).hexdigest())
 write(LOCAL/'manifest.json',{'seed':20261017,'big_block_bytes':32768,'big_repeats':8192,'cases':cases})
 return cases

NATIVE=r'''///|
extern "C" fn host_init() -> Unit = "moonmat_init"
///|
extern "C" fn argc(fallback : Int) -> Int = "moonmat_arg_count"
///|
#borrow(fallback)
extern "C" fn arg(i : Int, fallback : String) -> String = "moonmat_arg"
///|
#borrow(path)
#warnings("-unused_value")
extern "C" fn read(path : Bytes, limit : Int) -> Bytes = "moonmat_read"
///|
#warnings("-unused_value")
extern "C" fn io_error() -> Int = "moonmat_error"
///|
extern "C" fn now() -> Double = "moonmat_now"
///|
extern "C" fn peak() -> Double = "moonmat_peak"
@FFI@
///|
priv struct Stats { mut bytes : Int; mut largest : Int; mut input : Int }
///|
fn run(path : String, name : String, stats : Stats) -> Int raise @mat.MatError {
 let encoded = @utf8.encode((path + "\u{0000}")[:])
 let basic : @mat.Limits = { ..@mat.default_limits(), max_file_bytes: 1073741824, max_expanded_bytes: 1073741824, max_elements: 134217728, }
 @READ@
 @mat.write_tree(tree.variables, limits={ ..basic, max_file_bytes: 67108864, }).length()
}
///|
fn main {
 host_init()
 let args = @env.args()
 if argc(args.length()) != 4 { abort("file_bench INPUT VARIABLE timing|memory") }
 let path = arg(1,args.get(1).unwrap_or(""))
 let name = arg(2,args.get(2).unwrap_or(""))
 let memory = arg(3,args.get(3).unwrap_or("")) == "memory"
 let stats : Stats = { bytes: 0, largest: 0, input: 0, }
 try {
  let mut checksum = 0
  if !memory { for _i = 0; _i < 5; _i = _i + 1 { checksum = checksum + run(path,name,stats) } }
  let samples = []
  for _i = 0; _i < (if memory { 1 } else { 10 }); _i = _i + 1 {
   let start = now(); checksum = checksum + run(path,name,stats); samples.push(now()-start)
  }
  println(({ "samples_ms": Json::array(samples.map(v => Json::number(v))), "checksum": checksum, "peak_bytes": peak(), "input_bytes": stats.input, "read_bytes": stats.bytes, "maximum_read_request": stats.largest } : Json).stringify())
 } catch { _ => abort("File pipeline failed") }
}
'''
SOURCE_FFI=r'''///|
#borrow(path)
extern "C" fn open_source(path : Bytes, limit : Int) -> Int = "moonmat_source_open"
///|
extern "C" fn size_source(handle : Int) -> Int = "moonmat_source_size"
///|
#borrow(buffer)
extern "C" fn read_source(handle : Int, offset : Int, buffer : FixedArray[Byte], start : Int, count : Int) -> Int = "moonmat_source_read"
///|
extern "C" fn close_source(handle : Int) -> Int = "moonmat_source_close"
'''
SOURCE_READ=r'''let handle = open_source(encoded,1073741824)
 if handle < 0 { raise @mat.MatError("io-error",0,"Cannot open benchmark source") }
 defer { ignore(close_source(handle)) }
 stats.bytes = 0; stats.largest = 0; stats.input = size_source(handle)
 let source : @mat.MatSource = { size: stats.input, read_into: (offset,buffer,start,count) => {
  let n = read_source(handle,offset,buffer,start,count)
  if n > 0 { stats.bytes = stats.bytes + n }
  if count > stats.largest { stats.largest = count }
  n
 }, }
 let tree = @mat.read_selected_from(source,[name])
 if close_source(handle) != 0 { raise @mat.MatError("source-changed",0,"Changed benchmark source") }
'''
BYTES_READ=r'''let bytes = read(encoded,1073741824)
 if io_error() != 0 { raise @mat.MatError("io-error",0,"Cannot read benchmark file") }
 stats.input = bytes.length(); stats.bytes = bytes.length(); stats.largest = bytes.length()
 let tree = @mat.read_selected(bytes,[name],limits=basic)
'''
JS_BRIDGE=r'''///|
@SOURCE@
///|
#export_name("file_select")
pub fn file_select(@ARGS@, name : String) -> Int {
 let basic : @mat.Limits = { ..@mat.default_limits(), max_file_bytes: 1073741824, max_expanded_bytes: 1073741824, max_elements: 134217728, }
 @mat.write_tree(@READ@.variables, limits={ ..basic, max_file_bytes: 67108864, }).length() catch { _ => abort("File benchmark failed") }
}
'''
DRIVER=r'''import {openSync,closeSync,fstatSync,readSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {performance} from 'node:perf_hooks';
const [modulePath,path,name,kind]=process.argv.slice(2);
const api=await import(pathToFileURL(modulePath));
let stats;
function run(){
 const fd=openSync(path,'r');
 try{
  const before=fstatSync(fd,{bigint:true}); const size=Number(before.size);
  stats={input_bytes:size,read_bytes:0,maximum_read_request:0};
  const readInto=(offset,target,start,length)=>{try{const n=readSync(fd,target,start,length,offset);stats.read_bytes+=n;stats.maximum_read_request=Math.max(stats.maximum_read_request,length);return n;}catch{return -1;}};
  let result;
  if(api.file_source)result=api.file_select(api.file_source(size,readInto),name);
  else{const bytes=Buffer.alloc(size);let done=0;while(done<size){const n=readInto(done,bytes,done,Math.min(1048576,size-done));if(n<=0)throw new Error('short file');done+=n;}result=api.file_select(bytes,name);}
  const after=fstatSync(fd,{bigint:true});if(before.size!==after.size||before.mtimeNs!==after.mtimeNs||before.ctimeNs!==after.ctimeNs)throw new Error('changed source');return result;
 }finally{closeSync(fd);}
}
const memory=kind==='memory';let checksum=0;
if(!memory)for(let i=0;i<5;i++)checksum+=run();
const samples=[];
for(let i=0;i<(memory?1:10);i++){if(global.gc)global.gc();const start=performance.now();checksum+=run();samples.push(performance.now()-start);}
console.log(JSON.stringify({samples_ms:samples,checksum,peak_bytes:process.resourceUsage().maxRSS*1024,...stats}));
'''

def prepare(ref):
 commit=perf.command(['git','rev-parse',f'{ref}^{{commit}}'])
 folder=ROOT/'.local-tools'/f'file-benchmark-{commit[:12]}'
 if not folder.exists():
  folder.mkdir(parents=True)
  archive=LOCAL/f'{commit}.zip';perf.command(['git','archive','--format=zip',f'--output={archive}',commit])
  with zipfile.ZipFile(archive) as package:
   for item in package.infolist():assert (folder/item.filename).resolve().is_relative_to(folder.resolve())
   package.extractall(folder)
 if (ROOT/'.local-toolchain.json').exists():shutil.copyfile(ROOT/'.local-toolchain.json',folder/'.local-toolchain.json')
 evidence.ROOT=ROOT;expected=evidence.snapshot(commit);evidence.ROOT=folder;assert evidence.snapshot()==expected
 version=json.loads((folder/'package.json').read_bytes())['version'];source=tuple(map(int,version.split('-')[0].split('.'))) >= (0,0,16)
 d=folder/'src/cmd/file_bench';d.mkdir(parents=True,exist_ok=True)
 (d/'moon.pkg').write_text('import { "WeiR-h/moonmatbridge" @mat, "moonbitlang/core/env", "moonbitlang/core/encoding/utf8", }\nsupported_targets = "native"\npkgtype(kind: "executable")\noptions("native-stub": [ "bench.c" ],)\n',encoding='utf-8')
 shutil.copyfile(folder/'src/cmd/bench/bench.c',d/'bench.c')
 (d/'main.mbt').write_text(NATIVE.replace('@FFI@',SOURCE_FFI if source else '').replace('@READ@',SOURCE_READ if source else BYTES_READ),encoding='utf-8')
 d=folder/'src/file_bench_bridge';d.mkdir(exist_ok=True)
 (d/'moon.pkg').write_text('import { "WeiR-h/moonmatbridge" @mat, }\nsupported_targets = "js"\npkgtype(kind: "foreign_library")\n',encoding='utf-8')
 extra='''#export_name("file_source")
pub fn file_source(size : Int, reader : (Int, FixedArray[Byte], Int, Int) -> Int) -> @mat.MatSource { { size, read_into: reader, } }''' if source else ''
 (d/'bench.mbt').write_text(JS_BRIDGE.replace('@SOURCE@',extra).replace('@ARGS@','source : @mat.MatSource' if source else 'bytes : Bytes').replace('@READ@','@mat.read_selected_from(source,[name])' if source else '@mat.read_selected(bytes,[name],limits=basic)'),encoding='utf-8')
 code="import {pathToFileURL} from 'node:url';import{join}from'node:path';const r=process.argv[1];const {runMoon}=await import(pathToFileURL(join(r,'scripts/moon.mjs')));const {nativeEnv}=await import(pathToFileURL(join(r,'scripts/build-native.mjs')));console.log(runMoon(['build','src/cmd/file_bench','--target','native','--release','--deny-warn'],nativeEnv()));console.log(runMoon(['build','src/file_bench_bridge','--target','js','--release','--deny-warn']));"
 perf.command(['node','--input-type=module','-e',code,folder])
 return folder,commit,expected[1],version

def measure(folder,host,case,kind):
 if host=='native':args=[folder/'_build/native/release/build/cmd/file_bench'/('file_bench.exe' if platform.system()=='Windows' else 'file_bench'),case['path'],case['variable'],kind]
 else:args=['node','--expose-gc',LOCAL/'driver.mjs',folder/'_build/js/release/build/file_bench_bridge/file_bench_bridge.js',case['path'],case['variable'],kind]
 start=time.perf_counter();r=json.loads(perf.command(args));r['process_wall_ms']=(time.perf_counter()-start)*1000;assert r['checksum']>0 and r['peak_bytes']>0;return r

def main():
 parser=argparse.ArgumentParser();parser.add_argument('--baseline-ref',default='v0.0.14');parser.add_argument('--candidate-ref',default='HEAD');parser.add_argument('--case',action='append');args=parser.parse_args()
 cases=fixtures();(LOCAL/'driver.mjs').write_text(DRIVER,encoding='utf-8',newline='\n')
 baseline,bsha,bhash,_=prepare(args.baseline_ref);candidate,csha,chash,version=prepare(args.candidate_ref)
 report={'version':version,'status':'running','baseline_commit':bsha,'candidate_commit':csha,'baseline_runtime_source_sha256':bhash,'candidate_runtime_source_sha256':chash,'protocol':{'warmup_per_batch':5,'batches':3,'samples_per_batch':10,'memory_processes':3,'timing':'open, read, validate, select, close and serialize; process startup excluded; generated input excluded; warm OS cache; JS GC outside timing'},'results':[]}
 report['environment']={'toolchain':json.loads(perf.command(['node',ROOT/'scripts/toolchain.mjs'])),'platform':platform.platform(),'architecture':platform.machine(),'node':perf.command(['node','--version']),'moon':perf.command(['node',ROOT/'scripts/moon.mjs','version']),'build':'same toolchain, release mode, one compiler job'}
 config=ROOT/'.local-toolchain.json'
 toolchain=json.loads(config.read_bytes()) if config.exists() else {}
 report['environment']['compiler']=report['environment']['toolchain']['c_compiler']
 for case in cases:
  if args.case and case['name'] not in args.case:continue
  if tuple(map(int,version.split('-')[0].split('.')))<tuple(case['minimum_version']):continue
  for host in ['native','js']:
   batches={'baseline':[],'candidate':[]}
   for _ in range(3):
    for label,folder in [('baseline',baseline),('candidate',candidate)]:batches[label].append(measure(folder,host,case,'timing'))
   samples={k:[t for b in bs for t in b['samples_ms']] for k,bs in batches.items()}
   memory={k:[measure(d,host,case,'memory') for _ in range(3)] for k,d in [('baseline',baseline),('candidate',candidate)]}
   med={k:statistics.median(v) for k,v in samples.items()};rss={k:statistics.median(x['peak_bytes'] for x in v) for k,v in memory.items()}
   row={'case':{k:v for k,v in case.items() if k!='path'},'host':host,'batches':batches,'memory_processes':memory,'median_ms':med['candidate'],'baseline_median_ms':med['baseline'],'p95_ms':sorted(samples['candidate'])[28],'baseline_p95_ms':sorted(samples['baseline'])[28],'speedup':med['baseline']/med['candidate'],'peak_bytes':rss['candidate'],'baseline_peak_bytes':rss['baseline'],'memory_reduction':1-rss['candidate']/rss['baseline'],'payload_MiB_per_second':case['payload_bytes']/1048576/(med['candidate']/1000),'output_bytes':batches['candidate'][0]['checksum']/15}
   if host=='native' and bsha.startswith('21291ce'):row['memory_goal']=.4 if case['name']=='select-1-of-16' else .75;row['memory_goal_passed']=row['memory_reduction']>=row['memory_goal']
   report['results'].append(row);write(LOCAL/f'file-performance-v{version}.json',report);print(case['name'],host,round(row['speedup'],3),round(row['memory_reduction'],4),flush=True)
 for folder,ref in [(baseline,bsha),(candidate,csha)]:
  evidence.ROOT=ROOT;expected=evidence.snapshot(ref);evidence.ROOT=folder;assert evidence.snapshot()==expected
 report['status']='measured';report['scope']='File pipeline measurements; independent from preloaded codec benchmarks. Every previous case remains available.'
 report['regressions_over_10_percent']=[{'case':r['case']['name'],'host':r['host'],'speedup':r['speedup'],'memory_reduction':r['memory_reduction']} for r in report['results'] if r['speedup']<1/1.1 or r['memory_reduction']<-.1]
 write(ROOT/f'verification/reports/file-performance-v{version}.json',report)

if __name__=='__main__':main()
