"""Independent mixed-tree operations through both public command line adapters."""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
import sys
import numpy as np
from scipy.io import loadmat
import importlib.util

ROOT = Path(__file__).resolve().parents[1]
VERSION = json.loads((ROOT / 'package.json').read_bytes())['version']
spec = importlib.util.spec_from_file_location('mixed_tree_oracle', ROOT / 'examples/python/mixed_types.py')
mixed = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mixed)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--native-executable')
    parser.add_argument('--js-cli')
    args = parser.parse_args()
    directory = ROOT / 'verification/local/tree-operations'
    directory.mkdir(parents=True, exist_ok=True)
    cell = np.empty((1, 1), dtype=object)
    cell[0, 0] = np.array([[-0.0, np.nan]], dtype=np.float64)
    def fixture(value):
        return {'root': {'a.b[0]': value, 'label': '实验🌙'}, 'ids': np.array([[2**64-1]], dtype=np.uint64)}
    left = directory / 'left.mat'
    right = directory / 'right.mat'
    left.write_bytes(mixed.deterministic_mat(fixture(cell), False))
    changed = cell.copy()
    changed[0, 0] = np.array([[0.0, np.nan]], dtype=np.float64)
    right.write_bytes(mixed.deterministic_mat(fixture(changed), True))
    snapshots = tuple(map(int,VERSION.split('.'))) >= (0,0,13)
    checks = []
    def run(prefix, operation, *paths, expected=0):
        result = subprocess.run([*map(str,prefix), operation, *map(str,paths)], cwd=ROOT,
                                capture_output=True, encoding='utf-8', timeout=90)
        assert result.returncode == expected, (operation,result.returncode,result.stdout,result.stderr)
        return result
    executable = 'moonmat.exe' if sys.platform == 'win32' else 'moonmat'
    for host, prefix in [('native',[args.native_executable or str(ROOT/'dist'/executable)]),
                         ('js',['node',args.js_cli or str(ROOT/'scripts/cli.mjs')])]:
        report = directory / f'{host}-changed.json'
        report.unlink(missing_ok=True)
        run(prefix,'diff-tree',left,right,report,expected=2)
        change = json.loads(report.read_bytes())
        assert change['schema']=='moonmatbridge/tree-diff/1' and change['differences']==1
        assert change['samples'][0]['path']==[{'kind':'root','name':'root'},
            {'kind':'struct_element','index':0},{'kind':'field','name':'a.b[0]'},
            {'kind':'cell','index':0}]
        assert change['samples'][0]['before_hex']=='0000000000000080'
        assert change['samples'][0]['after_hex']=='0000000000000000'
        same = directory / f'{host}-same.json'
        same.unlink(missing_ok=True)
        run(prefix,'diff-tree',left,left,same)
        assert json.loads(same.read_bytes())['content_equal']
        before = same.read_bytes()
        run(prefix,'diff-tree',left,right,same,expected=1)
        assert same.read_bytes()==before
        bad = directory/'truncated.mat'
        bad.write_bytes(left.read_bytes()[:-1])
        output = directory/f'{host}-invalid.json'
        output.unlink(missing_ok=True)
        run(prefix,'diff-tree',left,bad,output,expected=1)
        assert not output.exists()
        checks.append({'host':host,'operation':'diff-tree','status':'passed','cases':4,
                       'report_sha256':hashlib.sha256(report.read_bytes()).hexdigest()})
        if snapshots:
            cases = [ROOT/'examples/mixed'/name for name in ('research-mixed.mat','research-mixed-compressed.mat','research-mixed-big-endian.mat')]
            cases.append(ROOT/'examples/workflows/all-base-classes.mat')
            for index, source in enumerate(cases):
                snapshot = directory/f'{host}-snapshot-{index}.json'
                restored = directory/f'{host}-restored-{index}.mat'
                compared = directory/f'{host}-restored-{index}-diff.json'
                for path in (snapshot,restored,compared): path.unlink(missing_ok=True)
                run(prefix,'snapshot-tree',source,snapshot)
                data=json.loads(snapshot.read_bytes())
                assert data['schema']=='moonmatbridge/tree-snapshot/1'
                run(prefix,'restore-tree',snapshot,restored)
                mixed.assert_file_equal(restored,source)
                run(prefix,'diff-tree',source,restored,compared)
                assert json.loads(compared.read_bytes())['content_equal']
            broken=json.loads(snapshot.read_bytes())
            broken['variables'][0]['unknown_field']=True
            invalids=[broken,{'schema':'moonmatbridge/tree-snapshot/1','order':'row-major','byte_order':'little','variables':[]}]
            for index,data in enumerate(invalids):
                bad=directory/f'{host}-invalid-snapshot-{index}.json'
                out=directory/f'{host}-invalid-snapshot-{index}.mat'
                bad.write_text(json.dumps(data),encoding='utf-8')
                out.unlink(missing_ok=True)
                run(prefix,'restore-tree',bad,out,expected=1)
                assert not out.exists()
            checks.append({'host':host,'operation':'snapshot-tree','status':'passed','cases':len(cases)+len(invalids)})
    result={'status':'passed','version':VERSION,'checks':checks,'passed':sum(c['cases'] for c in checks),
            'inputs':[{'file':p.name,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in (left,right)]}
    reports=ROOT/'verification/reports'
    reports.mkdir(parents=True,exist_ok=True)
    (reports/f'tree-operations-v{VERSION}.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8',newline='\n')
    print(f'Mixed tree operations: {result["passed"]} independent host checks passed')

if __name__=='__main__':
    main()
