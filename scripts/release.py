"""Local immutable publication: check, package, publish and public re-verification."""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,sys,time,uuid,zipfile,urllib.request
import release_evidence as e
ROOT=e.ROOT;REPO='WeiR-h/moonmatbridge'

def command(args):return e.run(args,False)
def api(method,path,body=None):
    import github_release
    return github_release.api(method,'repos/'+REPO+'/'+path,body)

def collect_ci(version,source):
    runs=api('GET','actions/runs?head_sha='+source+'&per_page=20')['workflow_runs']
    runs=[r for r in runs if r['head_sha']==source and r['name']=='scientific-interop']
    assert runs,'CI has not started'
    row=max(runs,key=lambda r:r['id'])
    assert row['status']=='completed' and row['conclusion']=='success',f"CI not successful: {row['html_url']}"
    previous=ROOT/f'verification/reports/ci-v{version}.json'
    if previous.exists():
        value=e.read(previous)
        if value.get('run_id')==row['id'] and value.get('commit')==source:return value
    directory=ROOT/'verification/local'/('ci-release-'+uuid.uuid4().hex);directory.mkdir(parents=True)
    values={}
    for platform,artifact in [('linux','linux-interop-'),('windows','windows-validation-')]:
        dest=directory/platform
        command(['gh','run','download',str(row['id']),'--repo',REPO,'--name',artifact+source,'--dir',dest])
        value=e.read(dest/f'reports/v{version}.json');assert value['status']=='passed'
        coverage=dest/f'reports/coverage-v{version}.json';assert e.read(coverage)['status']=='passed'
        (e.REPORTS/f'coverage-{platform}-v{version}.json').write_bytes(coverage.read_bytes())
        values[platform]={'environment':value['environment'],'source_sha256':value['source']['sha256'],'verification_groups':len(value['checks']),'coverage_sha256':e.digest(coverage)}
        if platform=='linux':
            octave=dest/f'reports/octave-v{version}.json';assert e.read(octave)['status']=='passed' and e.read(octave)['unicode_storage']['status']=='passed'
            (e.REPORTS/octave.name).write_bytes(octave.read_bytes())
    result={'status':'passed','version':version,'run_id':row['id'],'commit':source,'url':row['html_url'],'environment':values['linux']['environment'],'source_sha256':values['linux']['source_sha256'],'platforms':values,'scope':'Actual newest Windows/Linux three-target CI run and real Octave artifacts for the fixed source commit.'}
    e.save(f'ci-v{version}.json',result);return result

def check(version,source,online=True,current_environment=True):
    assert e.read(ROOT/'package.json')['version']==version,'Checkout does not match requested version'
    assert e.run(['git','show',source+':package.json']) and json.loads(e.run(['git','show',source+':package.json']))['version']==version
    assert subprocess.run(['git','merge-base','--is-ancestor',source,'HEAD'],cwd=ROOT).returncode==0,'Source commit is not an ancestor'
    local=e.read(e.REPORTS/f'v{version}.json');actual=e.fingerprint()
    # Check every verified source byte against the immutable source commit.
    archive=subprocess.check_output(['git','archive','--format=zip',source],cwd=ROOT)
    import io
    with zipfile.ZipFile(io.BytesIO(archive)) as z:
        for item in local['source']['entries']:
            assert hashlib.sha256(z.read(item['file'])).hexdigest()==item['sha256'],'Source commit differs: '+item['file']
    ci=collect_ci(version,source) if online else e.read(e.REPORTS/f'ci-v{version}.json')
    e.validate_identity(version,source,local,ci,actual)
    for kind in ['compatibility','name-encoding','api-contract','workflows','source-operations','sink-operations','tree-operations','tree-close']:
        r=e.read(e.REPORTS/f'{kind}-v{version}.json');assert r['status']=='passed' and r['version']==version,kind
    binding=e.validate_binding(version,current_environment)
    result={'status':'passed','version':version,'source_commit':source,'source_sha256':actual,'ci_run_id':ci['run_id'],'performance_binding_sha256':e.digest(e.REPORTS/f'performance-binding-v{version}.json')}
    e.save(f'release-check-v{version}.json',result);return result

def package(version,source):
    check(version,source)
    command(['node','scripts/package.mjs'])
    packed=e.read(ROOT/f'dist/release-v{version}.json')
    assert packed['source_sha256']==e.fingerprint()
    assert e.read(e.REPORTS/f'licenses-v{version}.json')['status']=='passed'
    for row in packed['archives']:
        p=ROOT/'dist'/row['file'];assert p.stat().st_size==row['bytes'] and e.digest(p)==row['sha256']
    e.save(f'release-ready-v{version}.json',{'status':'passed','version':version,'source_commit':source,'package_commit':e.run(['git','rev-parse','HEAD']),'source_sha256':packed['source_sha256'],'manifest_sha256':e.digest(ROOT/f'dist/release-v{version}.json')})

def publish(version,source,channel):
    check(version,source)
    ready=e.read(e.REPORTS/f'release-ready-v{version}.json')
    assert ready['source_commit']==source and ready['source_sha256']==e.fingerprint() and ready['manifest_sha256']==e.digest(ROOT/f'dist/release-v{version}.json')
    tag='v'+version;head=e.run(['git','rev-parse','HEAD']);assert head==ready['package_commit'],'Package source moved before tagging'
    existing=subprocess.run(['git','rev-parse','--verify',tag],cwd=ROOT,capture_output=True,text=True)
    if existing.returncode:command(['git','tag',tag,head])
    else:assert existing.stdout.strip()==head,'Existing tag differs'
    refs=api('GET','git/matching-refs/tags/'+tag);matches=[r for r in refs if r['ref']=='refs/tags/'+tag]
    if matches:assert matches[0]['object']['sha']==head,'Published tag differs'
    else:api('POST','git/refs',{'ref':'refs/tags/'+tag,'sha':head})
    public=e.load('public_delivery','public-release.py')
    for which in (['mooncakes','github'] if channel=='both' else [channel]):
        print('Publishing '+which,flush=True);getattr(public,which)()

def verify_public_once(version,source):
    assert e.fingerprint()==e.read(e.REPORTS/f'v{version}.json')['source']['sha256']
    public=e.load('verify_delivery','public-release.py')
    public.mooncakes(verify_only=True)
    public.github(verify_only=True)
    check(version,source,current_environment=False)
    receipt={'status':'passed','version':version,'source_commit':source,'tag_commit':e.run(['git','rev-parse','v'+version]),'ci_run_id':e.read(e.REPORTS/f'ci-v{version}.json')['run_id'],'public_assets':len(e.read(e.REPORTS/f'public-downloads-v{version}.json')['assets']),'github':f'https://github.com/{REPO}/releases/tag/v{version}','mooncakes':f'https://mooncakes.io/docs/{REPO}@{version}','scope':'Both public channels, source identity, licenses and independent workflows verified. Local upload; separate post-publication evidence.'}
    for kind in ['mooncakes','public-downloads','workflows-public','tree-operations-public','source-operations-public','tree-close-public','licenses','registry']:
        p=e.REPORTS/f'{kind}-v{version}.json';r=e.read(p);assert r['status']=='passed' and r['version']==version
    e.save(f'distribution-v{version}.json',receipt)
    e.save(f'stable-gate-v{version}.json',{'status':'ready','version':version,'source_commit':source,'source_sha256':e.fingerprint(),'blockers':[],'distribution_sha256':e.digest(e.REPORTS/f'distribution-v{version}.json'),'performance_binding_sha256':e.digest(e.REPORTS/f'performance-binding-v{version}.json')})

def verify_public(version,source):
    gate=e.REPORTS/f'stable-gate-v{version}.json'
    preserve=gate.exists() and e.read(gate).get('status')=='ready'
    originals={p.name:p.read_bytes() for p in e.REPORTS.glob(f'*v{version}.json')} if preserve else {}
    try:verify_public_once(version,source)
    finally:
        if preserve:
            directory=ROOT/'verification/local'/('public-repeat-'+uuid.uuid4().hex);directory.mkdir(parents=True)
            for p in e.REPORTS.glob(f'*v{version}.json'):
                (directory/p.name).write_bytes(p.read_bytes())
                if p.name in originals:p.write_bytes(originals[p.name])
                else:p.unlink()
            print('Repeat evidence preserved separately: '+str(directory),flush=True)

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('action',choices=['check','package','publish','verify-public']);p.add_argument('--version',required=True);p.add_argument('--source-ref',required=True);p.add_argument('--channel',choices=['github','mooncakes','both'],default='both');p.add_argument('--offline',action='store_true',help='Inspect already downloaded CI receipts; never used to authorize publication')
    a=p.parse_args();source=e.run(['git','rev-parse',a.source_ref+'^{commit}'])
    if a.action=='check':check(a.version,source,not a.offline)
    elif a.action=='publish':publish(a.version,source,a.channel)
    else:{'package':package,'verify-public':verify_public}[a.action](a.version,source)
    print(json.dumps({'status':'passed','version':a.version,'action':a.action}),flush=True)

if __name__=='__main__':main()
