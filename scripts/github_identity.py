"""Project-scoped stored GitHub account; never changes the global active login."""
import functools,json,os,re,subprocess,urllib.error,urllib.request


def selected_user(settings=None):
    value=(os.environ if settings is None else settings).get('MOONMATBRIDGE_GITHUB_USER','WeiR-h')
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9-]{0,38}',value):
        raise ValueError('Invalid project GitHub account name')
    return value


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,*args,**kwargs):return None


def _get(path,credential):
    assert path in ('/user','/repos/WeiR-h/moonmatbridge')
    route=os.environ.get('MOONMATBRIDGE_GITHUB_ROUTE','direct' if os.name=='nt' else 'system')
    assert route in ('direct','system')
    opener=urllib.request.build_opener(NoRedirect(),*([urllib.request.ProxyHandler({})] if route=='direct' else []))
    request=urllib.request.Request('https://api.github.com'+path,headers={'Authorization':'Bearer '+credential,'User-Agent':'MoonMatBridge-release'})
    try:
        with opener.open(request,timeout=30) as response:return json.load(response)
    except urllib.error.HTTPError as error:
        raise RuntimeError('GitHub account check failed: HTTP '+str(error.code)) from None


@functools.lru_cache(maxsize=1)
def token():
    account=selected_user()
    settings={k:v for k,v in os.environ.items() if k not in ('GH_TOKEN','GITHUB_TOKEN')}
    result=subprocess.run(['gh','auth','token','--hostname','github.com','--user',account],env=settings,capture_output=True,text=True)
    if result.returncode:raise RuntimeError('Stored GitHub login unavailable for '+account)
    credential=result.stdout.strip()
    if not credential or any(c.isspace() for c in credential):raise RuntimeError('Invalid stored GitHub credential')
    if _get('/user',credential).get('login','').lower()!=account.lower():raise RuntimeError('Stored credential does not match the requested project account')
    os.environ['GH_TOKEN']=credential
    return credential


def authorize(require_write=False):
    credential=token()
    if require_write and not _get('/repos/WeiR-h/moonmatbridge',credential).get('permissions',{}).get('push'):
        raise RuntimeError('Selected project account cannot publish this repository')
