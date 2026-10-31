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

from github_identity import selected_user
assert selected_user({})=='WeiR-h'
assert selected_user({'MOONMATBRIDGE_GITHUB_USER':'Reviewer-1'})=='Reviewer-1'
for invalid in ['', 'bad/name', 'bad name', 'https://github.com']:
    try:selected_user({'MOONMATBRIDGE_GITHUB_USER':invalid})
    except ValueError:continue
    raise AssertionError('Invalid project account accepted')
print('Project account selection boundaries passed without loading credentials')

# Validate the matrix independently of filenames and reject case substitution.
validator=e.load('performance_binding_checks','bind-performance.py')
base=e.read(e.REPORTS/'performance-vs-70f87e2-v0.1.8.json')
args=('core',base['baseline_commit'],base['candidate_head_commit'],base['candidate_runtime_source_sha256'],base['environment']['toolchain'])
validator.validate_report(base,*args)
for corrupt in ['duplicate','samples','revision']:
    changed=copy.deepcopy(base)
    if corrupt=='duplicate':changed['results'][1]=copy.deepcopy(changed['results'][0])
    elif corrupt=='samples':changed['results'][0]['batches']['candidate'][0]['samples_ms'].pop()
    else:changed['baseline_commit']='0'*40
    try:validator.validate_report(changed,*args)
    except AssertionError:continue
    raise AssertionError('Malformed performance cohort accepted: '+corrupt)
print('Performance matrix, sample-count and fixed-reference guards passed')

repeated=copy.deepcopy(base)
repeated['protocol'].update(native_repetitions={name:2 if name=='dense-16m' else 1 for name in validator.CORE},js_repetitions=1)
for row in repeated['results']:
    repeat=repeated['protocol']['native_repetitions'][row['case']] if row['host']=='native' else 1
    for batches in row['batches'].values():
        for batch in batches:
            batch.update(operations_per_sample=repeat,samples_total_ms=[s*repeat for s in batch['samples_ms']])
validator.validate_report(repeated,*args)
for corrupt in ['total','repeat','missing-total']:
    changed=copy.deepcopy(repeated);batch=changed['results'][0]['batches']['candidate'][0]
    if corrupt=='total':batch['samples_total_ms'][0]*=2
    elif corrupt=='repeat':batch['operations_per_sample']+=1
    else:batch['samples_total_ms'].pop()
    try:validator.validate_report(changed,*args)
    except AssertionError:continue
    raise AssertionError('Invalid repeated sample accepted: '+corrupt)
print('Repeated sample totals, normalization and paired operation-count guards passed')

# First observations remain unchanged; a retained matching recheck can resolve
# an isolated observation, while recurrence or a changed setup must fail.
suspect=copy.deepcopy(base);first=suspect['results'][0]
for b,c in zip(first['batches']['baseline'],first['batches']['candidate']):
    c['samples_ms']=[v*2 for v in b['samples_ms']]
first['speedup']=.5;first['median_ms']=first['baseline_median_ms']*2
suspect['regressions_over_10_percent']=[{k:first[k] for k in ['case','host','operation','speedup','memory_reduction']}]
healthy=copy.deepcopy(base);healthy['partial']=True;healthy['results']=[copy.deepcopy(base['results'][0])]
review=validator.validate_report(suspect,*args,[healthy])
assert review['status']=='verified' and len(review['resolved'])==1
recurring=copy.deepcopy(suspect);recurring['partial']=True;recurring['results']=[copy.deepcopy(first)]
wrong=copy.deepcopy(healthy);wrong['candidate_head_commit']='0'*40
protocol=copy.deepcopy(healthy);protocol['protocol']['warmup_per_batch']=6
missing=copy.deepcopy(healthy);missing['results']=[copy.deepcopy(base['results'][1])]
for checks in [[],[recurring],[wrong],[protocol],[missing]]:
    try:validator.validate_report(suspect,*args,checks)
    except AssertionError:continue
    raise AssertionError('Unresolved, recurring or mismatched recheck accepted')
print('Retained rechecks: isolated observations, recurrence, missing cases and setup changes passed')
