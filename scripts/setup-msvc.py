"""Project-local Microsoft C compiler; reuses an installed Windows SDK."""
from pathlib import Path
import argparse, concurrent.futures, hashlib, json, os, urllib.parse, urllib.request, zipfile

ROOT=Path(__file__).resolve().parents[1]

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--configure',action='store_true')
    parser.add_argument('--sdk-root',type=Path,default=Path('C:/Program Files (x86)/Windows Kits/10'))
    args=parser.parse_args()
    if os.name!='nt':raise SystemExit('This installer is for Windows x64')
    lock=json.loads((ROOT/'msvc.lock.json').read_bytes())
    dest=ROOT/'.local-tools'/lock['directory'];downloads=ROOT/'.local-tools/downloads'
    downloads.mkdir(parents=True,exist_ok=True)
    def fetch(info):
        archive=downloads/info['fileName']
        if not archive.exists() or hashlib.sha256(archive.read_bytes()).hexdigest()!=info['sha256']:
            with urllib.request.urlopen(info['url'],timeout=120) as response:archive.write_bytes(response.read())
        if hashlib.sha256(archive.read_bytes()).hexdigest()!=info['sha256']:raise RuntimeError('Microsoft package checksum mismatch')
        with zipfile.ZipFile(archive) as z:
            for entry in z.infolist():
                if entry.is_dir() or not entry.filename.startswith('Contents/'):continue
                out=dest/urllib.parse.unquote(entry.filename[len('Contents/'):])
                if not out.resolve().is_relative_to(dest.resolve()):raise RuntimeError('Unsafe compiler archive member')
                payload=z.read(entry)
                if out.exists() and out.read_bytes()==payload:continue
                out.parent.mkdir(parents=True,exist_ok=True);out.write_bytes(payload)
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:list(pool.map(fetch,lock['packages']))
    versions=sorted(p.name for p in (args.sdk_root/'Lib').glob('*') if (p/'um/x64/kernel32.lib').exists() and (p/'ucrt/x64/libucrt.lib').exists())
    if not versions:raise SystemExit('Install a Windows SDK or supply --sdk-root')
    vc=dest/'VC/Tools/MSVC'/lock['vc_directory']
    if args.configure:
        path=ROOT/'.local-toolchain.json';config=json.loads(path.read_bytes()) if path.exists() else {}
        config['msvc']={'vcRoot':str(vc),'bin':str(vc/'bin/Hostx64/x64'),'sdkRoot':str(args.sdk_root),'sdkVersion':versions[-1]}
        path.write_text(json.dumps(config,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('Project-local MSVC installed; SDK '+versions[-1]+'; Microsoft package hashes verified')

if __name__=='__main__':main()
