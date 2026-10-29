"""Independent zlib expansion and data-level checks of bounded compressed output."""
from pathlib import Path
import argparse,hashlib,json,platform,struct,subprocess,sys,tempfile,zlib
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'examples/python'))
from mixed_types import assert_file_equal
VERSION=json.loads((ROOT/'package.json').read_bytes())['version']

def expanded(data):
    pos=128;parts=[data[:128]];sizes=[]
    while pos<len(data):
        kind,n=struct.unpack_from('<II',data,pos);assert kind==15 and n>0
        dec=zlib.decompressobj();plain=dec.decompress(data[pos+8:pos+8+n])+dec.flush()
        assert dec.eof and not dec.unused_data and not dec.unconsumed_tail
        assert struct.unpack_from('<I',plain)[0]==14
        assert len(plain)==8+struct.unpack_from('<I',plain,4)[0]
        parts.append(plain);sizes.append(n);pos+=8+n
    assert pos==len(data)
    return b''.join(parts),sizes

def main():
    d=Path(tempfile.mkdtemp(prefix='compressed-sink-',dir=ROOT/'verification/local'))
    native=ROOT/'dist'/('moonmat.exe' if platform.system()=='Windows' else 'moonmat')
    files=sorted((ROOT/'verification/local/compatibility').glob('all-classes-*.mat'))
    assert len(files)==8
    checks=[]
    for fixture in files:
        outputs=[]
        for host,prefix in [('native',[str(native)]),('js',['node',str(ROOT/'scripts/cli.mjs')])]:
            plain=d/(host+'-plain-'+fixture.name);compressed=d/(host+'-compressed-'+fixture.name)
            for operation,target in [('roundtrip',plain),('compress',compressed)]:
                r=subprocess.run(prefix+[operation,str(fixture),str(target)],cwd=ROOT,capture_output=True,text=True,encoding='utf-8',timeout=60)
                assert r.returncode==0,(host,operation,r.stdout,r.stderr)
            content,sizes=expanded(compressed.read_bytes());assert content==plain.read_bytes()
            assert_file_equal(compressed,fixture)
            outputs.append(compressed.read_bytes())
            checks.append({'host':host,'case':fixture.name,'roots':len(sizes),'bytes':compressed.stat().st_size,'sha256':hashlib.sha256(outputs[-1]).hexdigest(),'expanded_equals_canonical':True})
        assert outputs[0]==outputs[1],'Host filesystem adapters changed compressed bytes'
    report={'status':'passed','version':VERSION,'oracle':'Python zlib, SciPy/NumPy','checks':checks,'scope':'All 15 public base classes, global flags, endian and compressed/plain inputs; independent per-root zlib checks and exact canonical expansion; both hosts byte-identical'}
    (ROOT/f'verification/reports/compressed-sink-v{VERSION}.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8',newline='\n')
    print('Incremental sink: 16 independent zlib / all-class host checks passed')

if __name__=='__main__':main()
