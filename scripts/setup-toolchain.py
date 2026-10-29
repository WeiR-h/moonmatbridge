"""Install the SHA-256 pinned compiler/core into this project's ignored tools directory."""
from pathlib import Path
import argparse, hashlib, json, os, platform, subprocess, tarfile, zipfile

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--configure', action='store_true', help='Update only this project local toolchain config')
    args = parser.parse_args()
    lock = json.loads((ROOT/'toolchain.lock.json').read_bytes())
    target = 'windows-x86_64' if os.name == 'nt' else 'linux-x86_64'
    if platform.machine().lower() not in ('amd64', 'x86_64'): raise SystemExit('This lock supports x86_64 hosts')
    dest = ROOT/'.local-tools'/('moon-'+lock['compiler'])
    downloads = ROOT/'.local-tools/downloads'
    downloads.mkdir(parents=True, exist_ok=True)
    for item, output in [(lock['archives'][target], dest), (lock['core'], dest/'lib')]:
        archive = downloads/item['filename']
        if not archive.exists() or hashlib.sha256(archive.read_bytes()).hexdigest() != item['sha256']:
            subprocess.run(['curl.exe' if os.name=='nt' else 'curl', '--fail', '--location', '--retry', '3',
                            '--connect-timeout', '20', '--max-time', '1800', '--output', str(archive), item['url']], check=True)
        if hashlib.sha256(archive.read_bytes()).hexdigest() != item['sha256']: raise SystemExit('Toolchain archive checksum mismatch: '+archive.name)
        output.mkdir(parents=True, exist_ok=True)
        if archive.suffix == '.zip':
            with zipfile.ZipFile(archive) as z:
                for name in z.namelist():
                    if not (output/name).resolve().is_relative_to(output.resolve()): raise SystemExit('Unsafe archive member')
                z.extractall(output)
        else:
            with tarfile.open(archive) as t: t.extractall(output, filter='data')
    env = {**os.environ, 'MOON_HOME':str(dest), 'MOONBIT_NEW_NATIVE':'0', 'PATH':str(dest/'bin')+os.pathsep+os.environ.get('PATH','')}
    moon = dest/'bin'/('moon.exe' if os.name=='nt' else 'moon')
    if os.name!='nt':
        for file in (dest/'bin').rglob('*'):
            if file.is_file():file.chmod(file.stat().st_mode|0o111)
    subprocess.run([moon,'version','--all'],env=env,check=True)
    subprocess.run([moon,'-C',dest/'lib/core','bundle','--warn-list','-a','--all'],env=env,check=True)
    if args.configure:
        path=ROOT/'.local-toolchain.json'
        config=json.loads(path.read_bytes()) if path.exists() else {}
        config['moonHome']=str(dest)
        path.write_text(json.dumps(config,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('Pinned compiler and core installed: '+str(dest))

if __name__=='__main__': main()
