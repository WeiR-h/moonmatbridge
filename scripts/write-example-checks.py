"""Run the shipped resident-tree example and consume its files independently."""
from pathlib import Path
import hashlib,json,subprocess,tempfile
import numpy as np
from scipy.io import loadmat
R=Path(__file__).resolve().parents[1]
version=json.loads((R/'package.json').read_bytes())['version']
d=Path(tempfile.mkdtemp(prefix='write-example-',dir=R/'verification/local'));checks=[]
for compressed in (False,True):
 p=d/('compressed.mat' if compressed else 'plain.mat')
 args=['node','scripts/moon.mjs','run','src/examples/write_large','--target','native','--',str(p),'--small']
 if compressed:args+=['--compressed']
 result=subprocess.run(args,cwd=R,capture_output=True,text=True,encoding='utf-8',timeout=180);assert result.returncode==0,(result.stdout,result.stderr)
 a=loadmat(p)['simulation'];assert a.shape==(131072,1) and a.dtype==np.float64 and np.all(a==0)
 checks.append({'compressed':compressed,'command':args,'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'shape':list(a.shape),'oracle':'scipy.io.loadmat'})
(R/f'verification/reports/write-example-v{version}.json').write_text(json.dumps({'status':'passed','version':version,'checks':checks},indent=2)+'\n',encoding='utf-8',newline='\n')
print('Shipped resident-tree example: both encodings independently consumed')
