"""Reproducible SciPy producer and independent recursive oracle for mixed Level 5 files.

Run with Python + NumPy + SciPy. They are validation tools, not runtime dependencies.
"""
from pathlib import Path
from io import BytesIO
import hashlib
import json
import struct
import zlib
import numpy as np
import scipy
from scipy.io import savemat, loadmat
from scipy.io.matlab import MatlabObject
from scipy.sparse import csc_matrix, issparse


def mixed_values():
    cell = np.empty((2, 2), dtype=object)
    cell[0, 0] = np.array([[18446744073709551615]], dtype=np.uint64)
    cell[1, 0] = "科研🌙"
    cell[0, 1] = {"unit": "摄氏度", "values": np.array([[1., -0., 3.25]])}
    cell[1, 1] = csc_matrix(np.array([[0., 2.], [3., 0.]]))
    records = np.empty((2, 2), dtype=[("id", object), ("label", object), ("payload", object)])
    for i, index in enumerate(np.ndindex(records.shape)):
        records[index]["id"] = np.array([[i + 1]], dtype=np.int32)
        records[index]["label"] = f"实验{i + 1}"
        records[index]["payload"] = cell if i == 0 else np.array([[i + .5]], dtype=np.float32)
    legacy = MatlabObject(records[0:1, 0:1].copy(), classname="ExperimentRecord")
    return {
        "uint64_ids": np.array([[9007199254740993, 18446744073709551615]], dtype=np.uint64),
        "wave": np.array([[1. + 2.j, -3. + .5j]], dtype=np.complex128),
        "logical_mask": np.array([[True, False], [False, True]]),
        "sparse_signal": csc_matrix(np.array([[0., 2.], [3., 0.]])),
        "title": "科研数据互操作🌙",
        "char_matrix": np.array(["甲乙", "丙丁"]),
        "measurements": cell,
        "experiments": records,
        "legacy_record": legacy,
        "empty_cell": np.empty((0, 2), dtype=object),
        "empty_struct": {},
        "empty_char": "",
        "tensor": np.arange(12, dtype=np.int16).reshape((2, 2, 3)),
    }


def deterministic_mat(values, compressed=False, global_names=None):
    stream = BytesIO()
    if global_names is None:
        savemat(stream, values, do_compression=compressed, long_field_names=True)
    else:
        # Test producer only: savemat does not expose the writer's global_vars option.
        from scipy.io.matlab._mio5 import MatFile5Writer
        MatFile5Writer(stream, do_compression=compressed, long_field_names=True, unicode_strings=True,
                       global_vars=global_names).put_variables(values)
    data = bytearray(stream.getvalue())
    data[:116] = b"MATLAB 5.0 MAT-file, reproducible MoonMatBridge mixed-type fixture (SciPy producer)".ljust(116, b" ")
    return bytes(data)


def big_endian(data):
    """Independent tag/typed-unit recoder. Writes full BE tags, including nested matrices."""
    widths = {1: 1, 2: 1, 3: 2, 4: 2, 5: 4, 6: 4, 7: 4, 9: 8, 12: 8, 13: 8, 16: 1, 17: 2, 18: 4}
    def elements(buf):
        result = bytearray()
        pos = 0
        while pos < len(buf):
            word, count = struct.unpack_from("<II", buf, pos)
            if word >> 16:
                kind, count = word & 65535, word >> 16
                raw = buf[pos + 4:pos + 4 + count]
                pos += 8
            else:
                kind = word
                raw = buf[pos + 8:pos + 8 + count]
                pos += 8 + count + (0 if kind == 15 else (-count) % 8)
            if kind == 14:
                raw = elements(raw)
            elif kind == 15:
                raw = zlib.compress(elements(zlib.decompress(raw)))
            else:
                width = widths[kind]
                assert len(raw) % width == 0
                # Vectorized unit swapping avoids millions of temporary Python objects.
                if width > 1:
                    raw = np.frombuffer(raw, dtype=f"u{width}").byteswap().tobytes()
            result += struct.pack(">II", kind, len(raw)) + raw
            if kind != 15:
                result += b"\0" * ((-len(raw)) % 8)
        assert pos == len(buf)
        return bytes(result)
    header = bytearray(data[:128])
    header[124:128] = b"\x01\x00MI"
    return bytes(header) + elements(data[128:])


def assert_tree_equal(actual, expected):
    if issparse(expected):
        assert issparse(actual) and actual.shape == expected.shape
        a, b = actual.tocsc(), expected.tocsc()
        np.testing.assert_array_equal(a.indptr, b.indptr)
        np.testing.assert_array_equal(a.indices, b.indices)
        assert_tree_equal(a.data, b.data)
        return
    assert actual.shape == expected.shape, (actual.shape, expected.shape)
    assert getattr(actual, "classname", None) == getattr(expected, "classname", None)
    if expected.dtype.names:
        assert actual.dtype.names == expected.dtype.names
        for index in np.ndindex(expected.shape):
            for field in expected.dtype.names:
                assert_tree_equal(actual[index][field], expected[index][field])
    elif expected.dtype.kind == "O":
        assert actual.dtype.kind == "O"
        for index in np.ndindex(expected.shape):
            # SciPy represents a fieldless struct as an object array containing None.
            if expected[index] is None:
                assert actual[index] is None
            else:
                assert_tree_equal(actual[index], expected[index])
    elif expected.dtype.kind == "U":
        np.testing.assert_array_equal(actual, expected)
    else:
        assert actual.dtype.kind == expected.dtype.kind and actual.dtype.itemsize == expected.dtype.itemsize
        dtype = expected.dtype.newbyteorder("<")
        assert actual.astype(dtype).tobytes(order="F") == expected.astype(dtype).tobytes(order="F")


def assert_file_equal(actual, expected):
    a = loadmat(actual, chars_as_strings=False, spmatrix=False)
    b = loadmat(expected, chars_as_strings=False, spmatrix=False)
    names = [k for k in b if not k.startswith("__")]
    assert [k for k in a if not k.startswith("__")] == names
    assert a["__globals__"] == b["__globals__"]
    for name in names:
        assert_tree_equal(a[name], b[name])


def generate(destination):
    destination = Path(destination)
    destination.mkdir(parents=True, exist_ok=True)
    plain = deterministic_mat(mixed_values())
    files = {
        "research-mixed.mat": plain,
        "research-mixed-compressed.mat": deterministic_mat(mixed_values(), True),
        "research-mixed-big-endian.mat": big_endian(plain),
    }
    for name, data in files.items():
        (destination / name).write_bytes(data)
    manifest = {
        "producer": f"SciPy {scipy.__version__} / NumPy {np.__version__}",
        "scope": "Documented Level 5 base classes; actual MATLAB/Octave execution not performed",
        "variables": list(mixed_values()),
        "cases": ["nested cell with char/struct/sparse/uint64", "2x2 struct array field order", "UTF8 Chinese and nonBMP",
                  "legacy mxOBJECT class and fields", "logical/complex/3D/empty containers", "LE/BE/compressed"],
        "files": [{"file": name, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()} for name, data in files.items()],
    }
    (destination / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    generate(Path(__file__).resolve().parents[1] / "mixed")
