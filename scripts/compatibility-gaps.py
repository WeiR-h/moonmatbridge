"""Persist minimal compatibility cases and tool disagreement without claiming closure."""
from pathlib import Path
import hashlib
import importlib.util
import json
import platform
import struct
import subprocess
import numpy as np
import scipy
from scipy.io import loadmat
from scipy.sparse import csc_matrix

ROOT = Path(__file__).resolve().parents[1]
VERSION = json.loads((ROOT / 'package.json').read_text())['version']
spec = importlib.util.spec_from_file_location('mixed', ROOT / 'examples/python/mixed_types.py')
mixed = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mixed)
OUT = ROOT / 'examples/compatibility'
OUT.mkdir(exist_ok=True)


def element(kind, payload):
    return struct.pack('<II', kind, len(payload)) + payload + bytes((-len(payload)) % 8)


def character(name, units, shape):
    return element(14, element(6, struct.pack('<II', 4, 0)) + element(5, struct.pack('<'+'i'*len(shape), *shape))
                   + element(1, name) + element(17, units))


def tag(data, offset):
    kind, size = struct.unpack_from('<II', data, offset)
    if kind >> 16:
        return offset + 4, offset + 8
    return offset + 8, offset + 8 + size + (-size) % 8


def char_units(data):
    position = tag(data, tag(data, 128)[1])[0]
    for _ in range(3):
        position = tag(data, position)[1]
    kind, size = struct.unpack_from('<II', data, position)
    if kind >> 16:
        return kind & 65535, data[position+4:position+4+(kind >> 16)]
    return kind, data[position+8:position+8+size]


def main():
    good = mixed.deterministic_mat({'good': np.array([[1.0]])})
    ordered = csc_matrix((np.array([2., 3.]), np.array([0, 2], dtype='int32'), np.array([0, 2], dtype='int32')), shape=(3, 1))
    cases = []
    def add(name, data, expected, state, note):
        path = OUT / (name + '.mat')
        path.write_bytes(data)
        cases.append({'file': path.name, 'sha256': hashlib.sha256(data).hexdigest(), 'bytes': len(data),
                      'expected_error': expected, 'compatibility_state': state, 'note': note})
    add('utf16-surrogate-units', good + character(b'text', b'\x3d\xd8\x00\xde', [1, 2]), None,
        'verified_storage_units', 'UTF16 surrogate units preserved; does not prove every producer dimension convention')
    add('utf16-empty', good + character(b'text', b'', [0, 2, 0]), None, 'verified', 'Empty multidimensional UTF16')
    add('csc-sorted', mixed.deterministic_mat({'good': np.array([[1.]]), 's': ordered}), None, 'verified', 'Canonical CSC')
    for name, indices in [('csc-unsorted', [2, 0]), ('csc-duplicate', [0, 0])]:
        # savemat sorts CSC indexes, so explicitly change only the stored row vector
        # in the independently produced valid file; retain lengths and all data.
        data = bytearray(mixed.deterministic_mat({'good': np.array([[1.]]), 's': ordered}))
        position = tag(data, tag(data, 128)[1])[0]
        for _ in range(3):
            position = tag(data, position)[1]
        rows = tag(data, position)[0]
        struct.pack_into('<ii', data, rows, *indices)
        add(name, bytes(data), None,
            'verified_storage', 'Original row order and duplicate slots retained; densification uses mathematical values')
    add('legacy-object-data', mixed.deterministic_mat({'good': np.array([[1.]]), 'record': mixed.all_base_values()['legacy_record']}),
        None, 'verified_data_only', 'Legacy class name and fields; MATLAB runtime behavior unverified')
    add('legacy-latin1-name', good + character(b'caf\xe9', b'A\x00', [1, 1]), 'invalid-name',
        'unresolved', 'Explicit Latin1 name bytes; no guessed decoding or silent rename')
    checks = []
    for case in cases:
        source = OUT / case['file']
        try:
            loadmat(source, chars_as_strings=False)
            case['scipy'] = 'readable'
        except Exception as error:
            case['scipy'] = type(error).__name__ + ': ' + str(error)
        for host in ('native', 'js'):
            prefix = [str(ROOT / 'dist' / ('moonmat.exe' if platform.system() == 'Windows' else 'moonmat'))] if host == 'native' else ['node', str(ROOT / 'scripts/cli.mjs')]
            for operation in ('info', 'roots', 'select'):
                output = ROOT / 'verification/local' / f'gaps-{host}-{case["file"]}'
                output.unlink(missing_ok=True)
                args = [operation, str(source)] + ([str(output), 'good'] if operation == 'select' else [])
                result = subprocess.run(prefix + args, cwd=ROOT, capture_output=True, text=True, encoding='utf-8', timeout=60)
                response = json.loads(result.stdout.strip() or result.stderr.strip())
                expected = case['expected_error']
                assert (result.returncode == 0) == (expected is None), (case, host, operation, response)
                if expected:
                    assert response['code'] == expected and not output.exists(), (case, response)
                checks.append({'case': case['file'], 'host': host, 'operation': operation, 'actual': response.get('code', 'accepted'),
                               'compatibility_state': case['compatibility_state']})
            if case['expected_error'] is None:
                output = ROOT / 'verification/local' / f'gaps-roundtrip-{host}-{case["file"]}'
                output.unlink(missing_ok=True)
                result = subprocess.run(prefix + ['roundtrip', str(source), str(output)], cwd=ROOT, capture_output=True, text=True, encoding='utf-8', timeout=60)
                assert result.returncode == 0, (case, result.stderr)
                if case['file'].startswith('utf16-'):
                    assert char_units(source.read_bytes()) == char_units(output.read_bytes()), 'Character storage tag/units changed'
                if case['scipy'] == 'readable':
                    mixed.assert_file_equal(output, source)
                if case['file'].startswith('csc-'):
                    before = loadmat(source, spmatrix=False)['s']
                    after = loadmat(output, spmatrix=False)['s']
                    np.testing.assert_array_equal(before.indices, after.indices)
                    np.testing.assert_array_equal(before.indptr, after.indptr)
                    assert before.data.tobytes()==after.data.tobytes()
                    dense = output.with_suffix('.dense.mat')
                    dense.unlink(missing_ok=True)
                    run = subprocess.run(prefix+['densify',str(source),'s',str(dense)],capture_output=True,text=True,encoding='utf-8')
                    assert run.returncode==0,run.stderr
                    np.testing.assert_array_equal(loadmat(dense)['s'],before.toarray())
                checks.append({'case': case['file'], 'host': host, 'operation': 'roundtrip', 'actual': 'storage_verified',
                               'compatibility_state': case['compatibility_state']})
    for path in sorted((ROOT / 'examples/octave/variants').glob('producer-*.mat')):
        cases.append({'file': '../octave/variants/' + path.name, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                      'compatibility_state': 'unresolved_producer_variant', 'note': 'Current execution is recorded separately by real Octave CI'})
    report = {'status': 'characterized', 'version': VERSION, 'producer': f'SciPy {scipy.__version__}; independent Level 5 unit fixture encoder',
              'reference': 'https://www.mathworks.com/help/pdf_doc/matlab/matfile_format.pdf', 'cases': cases, 'checks': checks,
              'scope': 'Assertions check observed supported/rejected behavior; unresolved cases are NOT compatibility passes. MATLAB execution not claimed.'}
    (ROOT / f'verification/reports/compatibility-gaps-v{VERSION}.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n', encoding='utf-8', newline='\n')
    (OUT / 'manifest.json').write_text(json.dumps({'reference': report['reference'], 'cases': cases}, ensure_ascii=False, indent=2)+'\n', encoding='utf-8', newline='\n')
    print(f'{len(checks)} gap characterization checks; unresolved cases retained')


if __name__ == '__main__':
    main()
