"""Independent Latin1 producers, both hosts, snapshots and failure atomicity."""
from pathlib import Path
import hashlib, json, platform, subprocess, struct, zlib, io
import numpy as np
import scipy
from scipy.io import savemat, loadmat
from scipy.io.matlab import MatlabObject

ROOT = Path(__file__).resolve().parents[1]
VERSION = json.loads((ROOT/'package.json').read_text(encoding="utf-8"))['version']

def main():
    out = ROOT/'verification/local/names'
    out.mkdir(parents=True, exist_ok=True)
    source = out/'latin1.mat'
    record = np.zeros((1,1), dtype=[('donnee', object)])
    record['donnee'][0,0] = np.array([[2**64-1]], dtype=np.uint64)
    values = {'café': np.array([[-0., 2.]]), 'résumé': MatlabObject(record, 'Experience')}
    # SciPy encodes roots as Latin1 but requires ASCII in its object writer.
    # Equal-length patches independently exercise raw miINT8 field/class bytes.
    savemat(source, values)
    raw=source.read_bytes().replace(b'donnee\x00', 'donnée\x00'.encode('latin1')).replace(b'Experience', 'Expérience'.encode('latin1'))
    source.write_bytes(raw)
    checks = []
    for host in ('native','js'):
        command = [str(ROOT/'dist'/('moonmat.exe' if platform.system()=='Windows' else 'moonmat'))] if host=='native' else ['node',str(ROOT/'scripts/cli.mjs')]
        def run(args, expected=0, codec=True):
            result = subprocess.run(command+(['--name-encoding=latin1'] if codec else [])+list(map(str,args)), capture_output=True, text=True, encoding='utf-8', timeout=90)
            assert result.returncode==expected, (host,args,result.stdout,result.stderr)
            return result
        for compressed in (False,True):
            path = source if not compressed else out/'latin1-compressed.mat'
            if compressed:
                data=bytearray(raw[:128]); pos=128
                while pos<len(raw):
                    _,size=struct.unpack_from('<II',raw,pos);end=pos+8+size+(-size)%8
                    compressed_bytes=zlib.compress(raw[pos:end]);data.extend(struct.pack('<II',15,len(compressed_bytes))+compressed_bytes);pos=end
                path.write_bytes(data)
            roots=json.loads(run(['roots',path]).stdout)
            assert [r['name'] for r in roots['roots']] == list(values), roots
            for op in ('info','roots'):
                assert json.loads(run([op,path],1,False).stderr)['code']=='invalid-name'
            for op in ('roundtrip','compress'):
                target=out/f'{host}-{compressed}-{op}.mat';target.unlink(missing_ok=True)
                run([op,path,target])
                output=target.read_bytes();plain=bytearray(output[:128]);pos=128
                while pos<len(output):
                    kind,size=struct.unpack_from('<II',output,pos)
                    end=pos+8+size+(0 if kind==15 else (-size)%8)
                    plain.extend(zlib.decompress(output[pos+8:end]) if kind==15 else output[pos:end]);pos=end
                # SciPy's field decoder mandates UTF8, so validate all raw Latin1
                # name bytes first, then consume an equal-length ASCII projection.
                for text,ascii_text in [('café','cafe'),('résumé','resume'),('donnée','donnee'),('Expérience','Experience')]:
                    encoded=text.encode('latin1');assert encoded in plain
                    plain=plain.replace(encoded,ascii_text.encode('ascii'))
                actual=loadmat(io.BytesIO(plain),struct_as_record=True)
                assert actual['cafe'].tobytes()==values['café'].tobytes()
                assert actual['resume'].classname=='Experience'
                assert actual['resume'].dtype.names==('donnee',)
                assert actual['resume']['donnee'][0,0][0,0]==2**64-1
            snapshot=out/f'{host}-{compressed}.json';snapshot.unlink(missing_ok=True)
            restored=out/f'{host}-{compressed}-restored.mat';restored.unlink(missing_ok=True)
            run(['snapshot-tree',path,snapshot]);run(['restore-tree',snapshot,restored])
            report=out/f'{host}-{compressed}-diff.json';report.unlink(missing_ok=True)
            run(['diff-tree',path,restored,report])
            assert json.loads(report.read_text(encoding="utf-8"))['content_equal']
            selected=out/f'{host}-{compressed}-selected.mat';selected.unlink(missing_ok=True)
            run(['select',path,selected,'résumé','café'])
            selected_roots=json.loads(run(['roots',selected]).stdout)
            assert [r['name'] for r in selected_roots['roots']]==['résumé','café']
            checks.append({'host':host,'compressed':compressed,'operations':['roots','info-default-rejection','roundtrip','compress','snapshot-tree','restore-tree','diff-tree','select'],'source_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'output_sha256':hashlib.sha256(restored.read_bytes()).hexdigest()})
        bad=out/f'{host}-bad.mat';bad.write_bytes(source.read_bytes()[:-1])
        target=out/f'{host}-atomic.mat';target.unlink(missing_ok=True)
        run(['select',bad,target,'café'],1)
        assert not target.exists()
    report={'status':'passed','version':VERSION,'producer':f'SciPy {scipy.__version__}; equal-length independent miINT8 class/field patches; Python zlib compression','checks':checks,'scope':'Independent raw Latin1 metadata checks; SciPy consumes an equal-length ASCII metadata projection because its field reader requires UTF8. Both CLI hosts check UTF8 defaults, exact uint64, negative zero, compression, snapshots, selection order and atomic failure.'}
    (ROOT/f'verification/reports/name-encoding-v{VERSION}.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'status':'passed','cases':len(checks)},ensure_ascii=False))

if __name__=='__main__': main()
