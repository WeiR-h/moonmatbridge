"""Immutable GitHub REST publication and unauthenticated public downloads."""
import os
import hashlib
import json
import subprocess
import time
import urllib.parse
import urllib.request
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor

ROOT = Path(__file__).resolve().parents[1]
REPO = 'WeiR-h/moonmatbridge'
API = f'repos/{REPO}'

def api(method, endpoint, body=None, binary=None, retry=True):
    if os.name=='nt':
        from github_transport import api as windows_api
        return windows_api(method,endpoint,body,binary,retry)
    args = ['gh', 'api', '--method', method, endpoint]
    if body is not None:
        path = ROOT / 'verification/local/github-request.json'
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(body, ensure_ascii=False), encoding='utf-8')
        args += ['--input', str(path)]
    if binary is not None:
        args += ['-H', 'Content-Type: application/octet-stream', '--input', str(binary)]
    for attempt in range(5 if retry else 1):
        try:
            value = subprocess.run(args, cwd=ROOT, capture_output=True, timeout=120)
        except subprocess.TimeoutExpired as error:
            if not retry or attempt == 4:
                raise RuntimeError("GitHub request timed out; refresh remote state before retry") from error
            continue
        if value.returncode == 0:
            return json.loads(value.stdout)
        if not retry or attempt == 4:
            raise RuntimeError(value.stderr.decode('utf-8', errors='replace'))
        time.sleep(min(2 ** attempt, 8))

def checksum(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def find_release(tag):
    # Authenticated listing includes resumable drafts as well as public releases.
    values = api('GET', f'{API}/releases?per_page=100')
    matches = [r for r in values if r['tag_name'] == tag]
    assert len(matches) <= 1, 'Ambiguous release tag'
    return matches[0] if matches else None

def ensure_release(tag, assets, notes):
    local = subprocess.check_output(['git','rev-parse',tag], cwd=ROOT, text=True).strip()
    assert api('GET',f'{API}/git/ref/tags/{tag}')['object']['sha'] == local
    assert len({p.name for p in assets}) == len(assets)
    release = find_release(tag)
    if release is None:
        try:
            release = api('POST',f'{API}/releases', {'tag_name':tag,'name':f'MoonMatBridge {tag}',
                'body':notes.read_text(encoding='utf-8'),'draft':True,'prerelease':'-' in tag}, retry=False)
        except RuntimeError:
            release = find_release(tag)
            if release is None:
                raise
    rid = release['id']
    for path in assets:
        for attempt in range(5):
            current = api('GET',f'{API}/releases/{rid}')
            matches = [a for a in current['assets'] if a['name'] == path.name]
            if matches:
                assert len(matches) == 1 and matches[0]['size'] == path.stat().st_size
                assert matches[0].get('digest') == 'sha256:' + checksum(path), path.name
                break
            assert current['draft'], 'Published assets are immutable'
            url = f'https://uploads.github.com/repos/{REPO}/releases/{rid}/assets?name={urllib.parse.quote(path.name)}'
            try:
                uploaded = api('POST',url,binary=path,retry=False)
                assert uploaded.get('digest') == 'sha256:' + checksum(path)
                break
            except RuntimeError:
                if attempt == 4:
                    raise
                time.sleep(min(2 ** attempt,8))
        print('Release asset verified: ' + path.name, flush=True)
    current = api('GET',f'{API}/releases/{rid}')
    assert {a['name'] for a in current['assets']} == {p.name for p in assets}
    if current['draft']:
        current = api('PATCH',f'{API}/releases/{rid}',{'draft':False})
    assert current['published_at'] and not current['draft']
    return current

def download_release(release, directory, assets):
    expected = {p.name:checksum(p) for p in assets}
    assert set(expected) == {a['name'] for a in release['assets']}
    def download(asset):
        name = asset['name']
        assert Path(name).name == name and '/' not in name and chr(92) not in name
        target = directory / name
        assert not target.exists()
        for attempt in range(5):
            try:
                request = urllib.request.Request(asset['browser_download_url'], headers={'User-Agent':'MoonMatBridge-public-verifier'})
                with urllib.request.urlopen(request, timeout=45) as response:
                    data = response.read()
                assert len(data) == asset['size'] and hashlib.sha256(data).hexdigest() == expected[name], name
                target.write_bytes(data)
                print('Public download verified: '+name, flush=True)
                return {'file':name,'sha256':expected[name],'url':asset['browser_download_url']}
            except Exception:
                if attempt == 4:
                    raise
                time.sleep(min(2 ** attempt,8))
    # Independent public reads; a receipt is written only after every future succeeds.
    with ThreadPoolExecutor(max_workers=4) as executor:
        receipts = list(executor.map(download, release['assets']))
    (directory/'public-http-downloads.json').write_text(json.dumps({'method':'Unauthenticated public HTTPS',
        'assets':receipts},indent=2)+'\n',encoding='utf-8',newline='\n')
