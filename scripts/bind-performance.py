from pathlib import Path
import json,sys
R=Path(__file__).resolve().parents[1];sys.path.insert(0,str(R/'scripts'));import release_evidence as e
v=e.read(R/'package.json')['version'];source=e.run(['git','rev-parse','HEAD']);tool=e.read_toolchain();scopes=e.scopes();cohorts=[]
for file,count in [(f'performance-vs-70f87e2-v{v}.json',24),(f'file-performance-v{v}.json',6),(f'write-regression-v{v}.json',32)]:
 p=e.REPORTS/file;r=e.read(p);assert r['status']=='measured' and len(r['results'])==count and not r.get('partial')
 assert r.get('candidate_commit',r.get('candidate_head_commit'))==source and r['candidate_runtime_source_sha256']==scopes['runtime']['sha256']
 assert r['environment']['toolchain']==tool
 assert not r['regressions_over_10_percent'],(file,r['regressions_over_10_percent'])
 cohorts.append({'file':file,'rows':count,'sha256':e.digest(p),'measured_commit':source})
e.save(f'performance-binding-v{v}.json',{'status':'verified','version':v,'reference':'v0.1.5','scopes':scopes,'toolchain':tool,'cohorts':cohorts,'scope':'Fresh paired fixed-revision 24 core, 6 file and 32 same-interface sink measurements. Historical memory-versus-sink results remain separate.'})
print('Fresh 24+6+32 rows, exact source/environment and regression limits verified')
