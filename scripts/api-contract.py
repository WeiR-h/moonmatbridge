"""Compare published v0.0.19 public signatures with additive codec changes."""
from pathlib import Path
import json,re,subprocess
ROOT=Path(__file__).resolve().parents[1]
VERSION=json.loads((ROOT/'package.json').read_bytes())['version']
checks=[]
for file in ['src/pkg.generated.mbti','src/interchange/pkg.generated.mbti','src/bridge/pkg.generated.mbti']:
    old=subprocess.check_output(['git','show','v0.0.19:'+file],cwd=ROOT).decode('utf-8')
    new=(ROOT/file).read_text(encoding='utf-8')
    # Keep every previous declaration. The only permitted signature extension is
    # an optional trailing codec argument on the core MAT read/write family.
    normalized=re.sub(r', name_encoding\? : NameEncoding','',new)
    lines=set(normalized.splitlines())
    for line in old.splitlines():
        if line.startswith('pub fn ') or line.startswith('pub type '):
            assert line in lines,(file,line)
    for match in re.finditer(r'pub(?:\(all\))? (?:struct|enum) \w+[^\n]*\{.*?^\}',old,re.M|re.S):
        assert match[0] in new,(file,match[0])
    checks.append(file)
report={'status':'passed','version':VERSION,'baseline':'v0.0.19','checks':checks,'scope':'Existing generated functions and public struct/enum definitions; additive optional codec arguments and new declarations allowed.'}
(ROOT/f'verification/reports/api-contract-v{VERSION}.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(json.dumps(report))
