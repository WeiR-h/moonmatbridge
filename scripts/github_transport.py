"""Local GitHub REST transport; credentials remain in process memory."""
import json,os,subprocess,time,urllib.parse,urllib.request
from pathlib import Path

def endpoint_url(endpoint):
    url=endpoint if endpoint.startswith('https://') else 'https://api.github.com/'+endpoint
    parts=urllib.parse.urlparse(url)
    assert parts.scheme=='https' and parts.netloc in ('api.github.com','uploads.github.com')
    assert parts.path.startswith('/repos/WeiR-h/moonmatbridge/')
    assert '..' not in urllib.parse.unquote(parts.path).split('/')
    assert not any(ord(c)<32 for c in url)
    return url

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,*args,**kwargs):return None

def api(method,endpoint,body=None,binary=None,retry=True):
    url=endpoint_url(endpoint)
    from github_identity import token
    credential=token()
    headers={'Authorization':'Bearer '+credential,'User-Agent':'MoonMatBridge-local-release','Accept':'application/vnd.github+json'}
    data=None
    if binary is not None:
        data=Path(binary).read_bytes();headers['Content-Type']='application/octet-stream'
        print('Uploading verified asset: '+Path(binary).name,flush=True)
    elif body is not None:
        data=json.dumps(body,ensure_ascii=False).encode('utf-8');headers['Content-Type']='application/json'
    route=os.environ.get('MOONMATBRIDGE_GITHUB_ROUTE','direct')
    assert route in ('direct','system')
    opener=urllib.request.build_opener(NoRedirect(),*([urllib.request.ProxyHandler({})] if route=='direct' else []))
    for attempt in range(4 if retry and method=='GET' else 1):
        try:
            request=urllib.request.Request(url,data=data,headers=headers,method=method)
            with opener.open(request,timeout=90) as response:
                payload=response.read()
                return json.loads(payload) if payload else None
        except Exception as error:
            if attempt+1==(4 if retry and method=='GET' else 1):
                raise RuntimeError('GitHub '+method+' failed; reconcile remote state before retry ('+('HTTP '+str(error.code) if isinstance(error,urllib.error.HTTPError) else type(error).__name__)+')') from None
            time.sleep(2**attempt)
