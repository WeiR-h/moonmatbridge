"""Reject mismatched version/source/CI and preserve exact measurement scopes."""
import copy,json
import release_evidence as e

local=e.read(e.REPORTS/'v0.1.5.json');ci=e.read(e.REPORTS/'ci-v0.1.5.json')
actual=local['source']['sha256'];source=ci['commit']
e.validate_identity('0.1.5',source,local,ci,actual)
def rejected(edit):
    a,b=copy.deepcopy(local),copy.deepcopy(ci);edit(a,b)
    try:e.validate_identity('0.1.5',source,a,b,actual)
    except (AssertionError,KeyError):return
    raise AssertionError('Invalid evidence accepted')
for edit in [lambda a,b:b.update(commit='0'*40),lambda a,b:b.update(version='0.1.4'),lambda a,b:b.update(source_sha256='0'*64),lambda a,b:b['platforms'].pop('windows'),lambda a,b:a['environment'].update(compiler_version='0.10.14'),lambda a,b:b['platforms']['linux'].update(source_sha256='0'*64),lambda a,b:b.update(status='failed')]:rejected(edit)
assert e.compiler_ok('0.10.16+b1a0e846e') and not e.compiler_ok('0.10.15') and not e.compiler_ok('date-20261020')
assert all(e.scopes('v0.1.5')[k]['files'] for k in ['runtime','hosts','adapters','build'])
print('Release identity: valid receipt, seven mismatch cases, compiler floor and scope identity passed')

from github_transport import endpoint_url
assert endpoint_url('repos/WeiR-h/moonmatbridge/releases').startswith('https://api.github.com/')
for endpoint in ['https://evil.invalid/repos/WeiR-h/moonmatbridge/releases','https://api.github.com/repos/another/project/releases','https://api.github.com.evil.invalid/repos/WeiR-h/moonmatbridge/releases']:
    try:endpoint_url(endpoint)
    except AssertionError:continue
    raise AssertionError('Foreign endpoint accepted')
print('Local HTTPS transport endpoint boundaries passed without loading credentials')
