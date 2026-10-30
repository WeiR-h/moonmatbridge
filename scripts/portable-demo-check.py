from pathlib import Path
import hashlib,json,shutil,subprocess,uuid
R=Path(__file__).resolve().parents[1]
shell=shutil.which('pwsh') or shutil.which('powershell.exe');assert shell
output=R/'verification/local'/('portable-demo-'+uuid.uuid4().hex)
executable=R/'dist/moonmat.exe'
p=subprocess.run([shell,'-NoProfile','-File',str(R/'examples/workflows/demo.ps1'),'-Executable',str(executable),'-OutputDirectory',str(output)],cwd=R,capture_output=True,text=True,encoding='utf-8',timeout=180)
assert p.returncode==0,(p.stdout,p.stderr)
result=json.loads((output/'demo-receipt.json').read_text(encoding='utf-8-sig'));assert result['status']=='passed'
version=json.loads((R/'package.json').read_bytes())['version']
(R/f'verification/reports/workflows-demo-v{version}.json').write_text(json.dumps({'status':'passed','version':version,'executable_sha256':hashlib.sha256(executable.read_bytes()).hexdigest(),'commands':len(result['commands']),'files':result['files'],'scope':'Actual shipped PowerShell demo in a new directory'},indent=2)+'\n',encoding='utf-8',newline='\n')
print('Portable demo: all three workflows and comparison exits passed')
