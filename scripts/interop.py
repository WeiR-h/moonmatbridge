"""Independent SciPy/NumPy compatibility checks; neither library is a product dependency."""
from __future__ import annotations

import hashlib
import json
import platform
import struct
import subprocess
import sys
import zlib
from pathlib import Path

import numpy as np
import scipy
from scipy.io import loadmat, savemat

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "verification" / "local" / "interop"
OUT.mkdir(parents=True, exist_ok=True)
checks: list[dict] = []


def record(name: str, detail: str = "") -> None:
    checks.append({"name": name, "status": "passed", "detail": detail})
    print(name + ": passed", flush=True)


def invoke(host: str, *args: str | Path, ok: bool = True) -> dict:
    command = [str(ROOT / "dist" / ("moonmat.exe" if platform.system() == "Windows" else "moonmat"))] if host == "native" else ["node", str(ROOT / "scripts" / "cli.mjs")]
    result = subprocess.run(command + [str(a) for a in args], cwd=ROOT, capture_output=True,
                            encoding="utf-8", errors="strict", timeout=30)
    text = (result.stdout if result.stdout.strip() else result.stderr).strip()
    try:
        response = json.loads(text)
    except json.JSONDecodeError:
        raise AssertionError(f"{host} {' '.join(str(a) for a in args)}: {result.returncode}\n{text}\n{result.stderr}")
    assert (result.returncode == 0) == ok, (host, args, result.returncode, response)
    assert response.get("status", "ok") == ("ok" if ok else "error"), response
    return response


def fresh(path: Path) -> Path:
    # Remove only this verifier's own files inside its fixed output directory.
    assert path.resolve().is_relative_to(OUT.resolve())
    path.unlink(missing_ok=True)
    return path


def assert_same(actual: np.ndarray, expected: np.ndarray) -> None:
    assert actual.shape == expected.shape, (actual.shape, expected.shape)
    if expected.dtype == np.dtype(bool):
        assert actual.dtype in (np.dtype(bool), np.dtype("uint8")), actual.dtype
        np.testing.assert_array_equal(actual.astype(bool), expected)
    else:
        assert actual.dtype.kind == expected.dtype.kind and actual.dtype.itemsize == expected.dtype.itemsize, (actual.dtype, expected.dtype)
        # Compare every canonical byte, including NaN payloads and negative zero.
        target = expected.dtype.newbyteorder("<")
        assert actual.astype(target).tobytes(order="F") == expected.astype(target).tobytes(order="F"), expected.dtype


def decode_json(entry: dict) -> np.ndarray:
    dtype = "bool" if entry["dtype"] == "logical" else entry["dtype"]
    values = entry["real"]
    if dtype.startswith("float"):
        values = [float(v) if v != "-0" else -0.0 for v in values]
    data = np.asarray(values, dtype=dtype)
    if entry["imag"] is not None:
        imaginary = np.asarray([float(v) if v != "-0" else -0.0 for v in entry["imag"]], dtype=dtype)
        complex_dtype = np.dtype("complex64" if dtype == "float32" else "complex128")
        combined = np.empty(data.shape, dtype=complex_dtype)
        combined.real = data
        combined.imag = imaginary
        data = combined
    return data.reshape(entry["shape"], order="F")


def fixtures() -> dict[str, np.ndarray]:
    arrays: dict[str, np.ndarray] = {}
    ranges = {
        "int8": [-128, -1, 0, 127], "uint8": [0, 1, 128, 255],
        "int16": [-32768, -1, 0, 32767], "uint16": [0, 1, 32768, 65535],
        "int32": [-2147483648, -1, 0, 2147483647], "uint32": [0, 1, 2147483648, 4294967295],
        "int64": [-9223372036854775808, -9007199254740993, 9007199254740993, 9223372036854775807],
        "uint64": [0, 1, 9007199254740993, 18446744073709551615],
    }
    for dtype, values in ranges.items():
        arrays[dtype] = np.array(values, dtype=dtype).reshape((2, 2), order="F")
    arrays["float32"] = np.array([-1.5, -0.0, np.inf, np.nan, 1.0e-30, -np.inf], dtype="float32").reshape((2, 3), order="F")
    arrays["float64"] = np.array([1.25, -0.0, np.inf, np.nan, 1.0e-300, -np.inf], dtype="float64").reshape((2, 3), order="F")
    arrays["nan_bits"] = np.array([0x7ff8000000000042, 0xfff800000000007f, 0x8000000000000000], dtype="uint64").view("float64").reshape((1, 3))
    for dtype in ("complex64", "complex128"):
        data = np.empty((2, 3), dtype=dtype, order="F")
        data.real = [[1.5, -0.0, 2.25], [3.5, 4.25, 5.5]]
        data.imag = [[-0.0, 7.5, -8.5], [9.25, 10.5, -11.25]]
        arrays[dtype] = data
    arrays["logical"] = np.array([[True, False, True], [False, True, False]])
    arrays["tensor"] = np.arange(24, dtype="float64").reshape((2, 3, 4), order="F")
    arrays["row"] = np.arange(5, dtype="int16").reshape((1, 5))
    arrays["column"] = np.arange(5, dtype="int16").reshape((5, 1))
    arrays["scalar"] = np.array([[42]], dtype="int8")
    arrays["empty"] = np.empty((0, 3), dtype="float32")
    arrays["empty_nd"] = np.empty((2, 0, 4), dtype="uint32")
    arrays["random_signal"] = np.random.default_rng(20261007).normal(size=(40, 60))
    return arrays


def element(kind: int, data: bytes, endian: str, small: bool = False) -> bytes:
    if small and 0 < len(data) <= 4:
        return struct.pack(endian + "I", (len(data) << 16) | kind) + data.ljust(4, b"\0")
    return struct.pack(endian + "II", kind, len(data)) + data + b"\0" * (-len(data) % 8)


def manual_big_endian() -> tuple[bytes, dict[str, np.ndarray]]:
    header = b"MATLAB 5.0 MAT-file, independent Python big-endian fixture".ljust(116, b" ") + b"\0" * 8 + struct.pack(">H", 256) + b"MI"
    definitions = [
        ("be", 6, 9, np.array([[1.25, -0.0], [np.inf, -2.5]], dtype="float64")),
        ("i64", 14, 12, np.array([[-9223372036854775808, 9007199254740993]], dtype="int64")),
        ("u64", 15, 13, np.array([[18446744073709551615, 0]], dtype="uint64")),
        ("tiny", 8, 1, np.array([[-5]], dtype="int8")),
        # MAT class differs from compact storage; reader must recover the declared floating class.
        ("compact", 6, 3, np.array([[-12, 0, 32767]], dtype="int16")),
    ]
    expected = {}
    parts = []
    for name, cls, storage, data in definitions:
        body = element(6, struct.pack(">II", cls, 0), ">")
        body += element(5, struct.pack(">" + "i" * data.ndim, *data.shape), ">")
        body += element(1, name.encode(), ">", small=True)
        body += element(storage, data.astype(data.dtype.newbyteorder(">")).tobytes(order="F"), ">", small=True)
        parts.append(element(14, body, ">"))
        expected[name] = data.astype("float64") if name == "compact" else data
    return header + b"".join(parts), expected


def cross_file(path: Path, expected: dict[str, np.ndarray], host: str, label: str) -> None:
    info = invoke(host, "info", path)
    assert {item["name"] for item in info["arrays"]} == set(expected)
    dump = fresh(OUT / f"{label}-{host}.json")
    invoke(host, "dump", path, dump)
    document = json.loads(dump.read_text(encoding="utf-8"))
    assert document["order"] == "column-major"
    for entry in document["arrays"]:
        value = decode_json(entry)
        # JSON intentionally normalizes NaN payloads; MAT->MAT retains their exact bits.
        target = expected[entry["name"]]
        assert value.shape == target.shape
        np.testing.assert_array_equal(value, target)
        if value.dtype.kind in "fc":
            mask = ~np.isnan(target.real)
            np.testing.assert_array_equal(np.signbit(value.real)[mask], np.signbit(target.real)[mask])
            if value.dtype.kind == "c":
                mask = ~np.isnan(target.imag)
                np.testing.assert_array_equal(np.signbit(value.imag)[mask], np.signbit(target.imag)[mask])
    roundtrip = fresh(OUT / f"{label}-{host}-roundtrip.mat")
    invoke(host, "roundtrip", path, roundtrip)
    loaded = loadmat(roundtrip)
    for name, value in expected.items():
        assert_same(loaded[name], value)
    record(f"{host}: {label} MAT read/write", f"{len(expected)} arrays; shape, dtype, exact canonical bytes")
    packed = fresh(OUT / f"{label}-{host}-from-json.mat")
    invoke(host, "pack", dump, packed)
    reloaded = loadmat(packed)
    for name, value in expected.items():
        np.testing.assert_array_equal(reloaded[name], value)
        assert reloaded[name].shape == value.shape
    record(f"{host}: {label} JSON to SciPy", "64-bit decimal strings, complex components, nonfinite markers")


data = fixtures()
for compressed in (False, True):
    label = "scipy-compressed" if compressed else "scipy-uncompressed"
    path = OUT / f"{label}.mat"
    savemat(path, data, do_compression=compressed, oned_as="column")
    # Verify fixture generator itself retains empty multidimensional shapes.
    expected = loadmat(path)
    expected = {name: expected[name] if value.dtype != np.dtype(bool) else value for name, value in data.items()}
    for host in ("native", "js"):
        cross_file(path, expected, host, label)

big_bytes, big_expected = manual_big_endian()
big = OUT / "big-endian.mat"
big.write_bytes(big_bytes)
# SciPy defaults to storage dtype for compact arrays; mat_dtype=True restores declared dtype.
be_reference = loadmat(big, mat_dtype=True)
for name, expected in big_expected.items():
    assert_same(be_reference[name], expected)
record("independent big-endian fixture validated by SciPy", "small tags, 64-bit extremes, compact numeric storage")
for host in ("native", "js"):
    cross_file(big, big_expected, host, "big-endian")

compressed_be = OUT / "big-endian-compressed.mat"
# Each compressed element is independently encoded and intentionally has no alignment padding.
position = 128
compressed_parts = []
while position < len(big_bytes):
    size = struct.unpack(">I", big_bytes[position + 4:position + 8])[0]
    part = big_bytes[position:position + 8 + size]
    packed = zlib.compress(part)
    compressed_parts.append(struct.pack(">II", 15, len(packed)) + packed)
    position += 8 + size
compressed_be.write_bytes(big_bytes[:128] + b"".join(compressed_parts))
for host in ("native", "js"):
    cross_file(compressed_be, big_expected, host, "big-endian-compressed")

for host in ("native", "js"):
    sample = fresh(OUT / f"{host}-科研样例 with spaces.mat")
    invoke(host, "sample", sample)
    loaded = loadmat(sample)
    assert loaded["sample_id"][0, 0] == np.uint64(9007199254740993)
    assert loaded["sample_id"][0, 1] == np.uint64(18446744073709551615)
    assert_same(loaded["temperature"], np.array([[21.5, 20.25, 18.0], [22.0, 19.75, 17.5]]))
    assert loadmat(sample, mat_dtype=True, variable_names=["valid"])["valid"].dtype == np.dtype(bool)
    record(f"{host}: generated sample and Unicode paths", "SciPy consumer; boolean MAT class; exact uint64 values")
    original_hash = hashlib.sha256(sample.read_bytes()).hexdigest()
    response = invoke(host, "sample", sample, ok=False)
    assert response["code"] == "output-exists"
    assert hashlib.sha256(sample.read_bytes()).hexdigest() == original_hash
    record(f"{host}: existing output rejected", "Exclusive create; original sample still loads correctly")
    for name, expected in data.items():
        npy = fresh(OUT / f"{host}-{name}.npy")
        invoke(host, "npy", OUT / "scipy-compressed.mat", name, npy)
        actual = np.load(npy, allow_pickle=False)
        assert_same(actual, expected)
        assert actual.flags.f_contiguous
    record(f"{host}: NumPy NPY export", f"{len(data)} dtype/shape fixtures, complex interleaving, exact IEEE bytes")

# Selection must preserve only the requested variables and their exact values.
for host in ("native", "js"):
    names = [list(data)[-1], list(data)[0]]
    selected = fresh(OUT / f"{host}-selected.mat")
    invoke(host, "select", OUT / "scipy-compressed.mat", selected, *names)
    actual = loadmat(selected)
    assert [k for k in actual if not k.startswith("__")] == names
    for name in names:
        assert_same(actual[name], data[name])
    bad_out = fresh(OUT / f"{host}-invalid-selection.mat")
    assert invoke(host, "select", selected, bad_out, names[0], names[0], ok=False)["code"] == "duplicate-name"
    assert not bad_out.exists()
    assert invoke(host, "select", selected, bad_out, "absent", ok=False)["code"] == "missing-variable"
    assert not bad_out.exists()
    record(f"{host}: variable subset selection", "Order, raw values, missing/duplicate errors and no partial output")

# NumPy supplies independent NPY files, including endian/order/version variants.
imports = dict(data)
imports.update({
    "scalar": np.asarray(9007199254740993, dtype="uint64"),
    "vector": np.asarray([-9223372036854775808, 9007199254740993, 9223372036854775807], dtype="int64"),
    "empty_vector": np.empty((0,), dtype="float32"),
})
npy_cases = []
for name, expected in imports.items():
    for version, order, endian in [((1, 0), "C", "<"), ((2, 0), "F", ">"), ((3, 0), "C", ">")]:
        incoming = np.array(expected, dtype=expected.dtype.newbyteorder(endian), order=order, copy=True)
        path = OUT / f"npy-import-{name}-v{version[0]}-{order}.npy"
        with path.open("wb") as handle:
            np.lib.format.write_array(handle, incoming, version=version, allow_pickle=False)
        shape = expected.shape if expected.ndim >= 2 else ((1, 1) if expected.ndim == 0 else (expected.size, 1))
        npy_cases.append((name, path, expected.reshape(shape, order="F")))
for host in ("native", "js"):
    for i, (name, path, expected) in enumerate(npy_cases):
        converted = fresh(OUT / f"{host}-npy-import-{i}.mat")
        invoke(host, "from-npy", path, name, converted)
        actual = loadmat(converted)[name]
        assert_same(actual, expected)
    record(f"{host}: NumPy NPY import", f"{len(npy_cases)} NumPy-generated files: versions 1/2/3, C/Fortran, endian, complex, 64-bit, scalar/vector/empty")

object_npy = OUT / "npy-object.npy"
np.save(object_npy, np.array([{"payload": "pickle-must-not-be-read"}], dtype=object), allow_pickle=True)
truncated_npy = OUT / "npy-truncated.npy"
truncated_npy.write_bytes(npy_cases[0][1].read_bytes()[:-1])
for host in ("native", "js"):
    for path, expected_code in [(object_npy, "unsupported-npy-dtype"), (truncated_npy, "payload-size")]:
        output = fresh(OUT / f"{host}-invalid-npy.mat")
        response = invoke(host, "from-npy", path, "x", output, ok=False)
        assert response["code"] == expected_code
        assert not output.exists()
    record(f"{host}: NPY unsafe/truncated input rejected", "No pickle evaluation, no partial output")

from scipy.sparse import csc_matrix, issparse

sparse_cases = {
    "sparse_double": csc_matrix(np.array([[1.25, 0, 0], [0, -2.5, 0]])),
    "sparse_complex": csc_matrix(np.array([[1 + 2j, 0, 0], [0, -2 - 3j, 0]])),
    "sparse_logical": csc_matrix(np.array([[True, False, False], [False, True, False]])),
    "sparse_empty": csc_matrix((0, 3)),
    "sparse_zero_columns": csc_matrix((3, 0)),
    "sparse_explicit_bits": csc_matrix((np.array([0x7ff8000000000042, 0x8000000000000000], dtype="uint64").view("float64"), np.array([0, 2]), np.array([0, 1, 2])), shape=(3, 2)),
    "sparse_huge": csc_matrix((np.array([1.25]), np.array([999999]), np.array([0, 1] + [1] * 999)), shape=(1000000, 1000)),
}

for compressed in (False, True):
    path = OUT / f"scipy-sparse-{compressed}.mat"
    savemat(path, {**sparse_cases, "dense_id": np.array([[9007199254740993]], dtype="uint64")}, do_compression=compressed)
    for host in ("native", "js"):
        metadata = invoke(host, "info", path)
        assert sum(item["storage"] == "csc" for item in metadata["arrays"]) == len(sparse_cases)
        for operation in ("roundtrip", "compress"):
            converted = fresh(OUT / f"{host}-sparse-{compressed}-{operation}.mat")
            invoke(host, operation, path, converted)
            actual = loadmat(converted)
            assert_same(actual["dense_id"], np.array([[9007199254740993]], dtype="uint64"))
            for name, expected in sparse_cases.items():
                value = actual[name]
                assert issparse(value) and value.shape == expected.shape
                value = value.tocsc()
                np.testing.assert_array_equal(value.indices, expected.indices)
                np.testing.assert_array_equal(value.indptr, expected.indptr)
                assert_same(value.data.reshape(1, -1), expected.data.reshape(1, -1))
        record(f"{host}: mixed dense/CSC sparse file compressed={compressed}", "SciPy reads exact sparse shapes, pointers, values, explicit NaN/signed zero and uint64; no densification of billion-element shape")
        denied = fresh(OUT / f"{host}-huge-dense.mat")
        assert invoke(host, "densify", path, "sparse_huge", denied, ok=False)["code"] == "element-limit"
        assert not denied.exists()
        npy_denied = fresh(OUT / f"{host}-sparse-denied.npy")
        assert invoke(host, "npy", path, "sparse_double", npy_denied, ok=False)["code"] == "explicit-densification-required"
        assert not npy_denied.exists()

for host in ("native", "js"):
    dense_source = OUT / "sparse-expansion-source.mat"
    negative_zero = np.array([0, 0x8000000000000000, 0x7ff8000000000042, 0], dtype="uint64").view("float64").reshape(2, 2, order="F")
    savemat(dense_source, {"bits": negative_zero, "keep": np.array([[7]], dtype="int8")})
    sparse_file = fresh(OUT / f"{host}-sparsify.mat")
    dense_file = fresh(OUT / f"{host}-densify.mat")
    invoke(host, "sparsify", dense_source, "bits", sparse_file)
    assert loadmat(sparse_file)["bits"].nnz == 2
    invoke(host, "densify", sparse_file, "bits", dense_file)
    assert_same(loadmat(dense_file)["bits"], negative_zero)
    assert_same(loadmat(dense_file)["keep"], np.array([[7]], dtype="int8"))
    record(f"{host}: explicit sparse/dense conversion", "Signed zero and NaN payloads are retained as explicit entries; other variables survive")

def independent_sparse(rows: list[int], cols: list[int], values: np.ndarray, shape: tuple[int, int], *, endian: str = ">", nzmax: int | None = None) -> bytes:
    header = b"MATLAB 5.0 MAT-file, independent CSC fixture".ljust(116, b" ") + b"\0" * 8 + struct.pack(endian + "H", 256) + (b"MI" if endian == ">" else b"IM")
    capacity = max(1, len(rows)) if nzmax is None else nzmax
    payload = element(6, struct.pack(endian + "II", 5, capacity), endian)
    payload += element(5, struct.pack(endian + "ii", *shape), endian)
    payload += element(1, b"s", endian, small=True)
    payload += element(5, np.asarray(rows, dtype=endian + "i4").tobytes(), endian)
    payload += element(5, np.asarray(cols, dtype=endian + "i4").tobytes(), endian)
    payload += element(9, values.astype(endian + "f8").tobytes(), endian)
    return header + element(14, payload, endian)

be_sparse = OUT / "independent-sparse-big-endian.mat"
be_sparse.write_bytes(independent_sparse([0, 2, 123], [0, 1, 2], np.array([1.25, -0., 9.]), (3, 2), nzmax=5))
for host in ("native", "js"):
    metadata = invoke(host, "info", be_sparse)
    assert metadata["source_endian"] == "big" and metadata["arrays"][0]["nzmax"] == 5 and metadata["arrays"][0]["stored_slots"] == 3
    converted = fresh(OUT / f"{host}-sparse-big-endian.mat")
    invoke(host, "roundtrip", be_sparse, converted)
    expected = csc_matrix((np.array([1.25, -0.]), np.array([0, 2]), np.array([0, 1, 2])), shape=(3, 2))
    actual = loadmat(converted)["s"].tocsc()
    assert_same(actual.data.reshape(1, -1), expected.data.reshape(1, -1))
    np.testing.assert_array_equal(actual.indices, expected.indices)
    np.testing.assert_array_equal(actual.indptr, expected.indptr)
    record(f"{host}: independent big-endian sparse/capacity fixture", "Python struct-built fixture; small name tag, nzmax and inactive slots retained")
    for label, rows, cols, expected_code in [("pointers", [0], [0, 2, 1], "invalid-sparse"), ("row-range", [3], [0, 1, 1], "invalid-sparse"), ("row-order", [1, 0], [0, 2, 2], "noncanonical-sparse")]:
        invalid_file = OUT / f"invalid-sparse-{label}.mat"
        invalid_file.write_bytes(independent_sparse(rows, cols, np.zeros(len(rows)), (3, 2)))
        assert invoke(host, "info", invalid_file, ok=False)["code"] == expected_code
    record(f"{host}: invalid CSC pointers rows and ordering rejected")

transform_source = OUT / "scientific-transform-source.mat"
transform_inputs = {
    "tensor": np.arange(24, dtype="float64").reshape((2, 3, 4), order="F"),
    "ids": np.array([0, 18446744073709551615, 9007199254740993, 3, 4, 5], dtype="uint64").reshape((2, 3), order="F"),
    "bits": np.array([0x7fc00042, 0x80000000, 0xffc0007f], dtype="uint32").view("float32").reshape(1, 3),
    "z": np.array([[1 + 2j, -3 + 4j, 5 - 6j], [7 + 8j, -9 - 10j, 11 + 12j]], dtype="complex64"),
    "logical": np.array([[True, False, True], [False, True, False]]),
    "keep_sparse": sparse_cases["sparse_huge"],
}
savemat(transform_source, transform_inputs)
operations = [
    {"op": "slice", "name": "tensor", "starts": [0, 0, 1], "counts": [2, 2, 2], "steps": [1, 2, 1]},
    {"op": "gather", "name": "tensor", "axis": 2, "indices": [1, 0, 1]},
    {"op": "permute", "name": "tensor", "axes": [2, 0, 1]},
    {"op": "reshape", "name": "tensor", "shape": [3, 4]},
    {"op": "gather", "name": "ids", "axis": 0, "indices": [1, 0, 1]},
    {"op": "gather", "name": "bits", "axis": 1, "indices": [2, 0, 2, 1]},
    {"op": "slice", "name": "z", "starts": [0, 1], "counts": [2, 2]},
    {"op": "concat", "name": "paired_z", "inputs": ["z", "z"], "axis": 1},
    {"op": "gather", "name": "logical", "axis": 1, "indices": [2, 0, 2]},
]
plan_path = OUT / "scientific-transform-plan.json"
plan_path.write_text(json.dumps({"schema": "moonmatbridge/transform/1", "operations": operations}), encoding="utf-8")
expected_transforms = {
    "tensor": np.take(transform_inputs["tensor"][:, ::2, 1:3], [1, 0, 1], axis=2).transpose(2, 0, 1).reshape((3, 4), order="F"),
    "ids": np.take(transform_inputs["ids"], [1, 0, 1], axis=0),
    "bits": np.take(transform_inputs["bits"], [2, 0, 2, 1], axis=1),
    "z": transform_inputs["z"][:, 1:3],
    "paired_z": np.concatenate([transform_inputs["z"][:, 1:3]] * 2, axis=1),
    "logical": np.take(transform_inputs["logical"], [2, 0, 2], axis=1),
}
for host in ("native", "js"):
    transformed = fresh(OUT / f"{host}-scientific-transformed.mat")
    invoke(host, "transform", transform_source, plan_path, transformed)
    actual = loadmat(transformed)
    for name, expected in expected_transforms.items():
        assert_same(actual[name], expected)
    assert issparse(actual["keep_sparse"]) and actual["keep_sparse"].shape == sparse_cases["sparse_huge"].shape
    record(f"{host}: NumPy-oracle scientific transform pipeline", "Nine operations: slice/gather/permute/reshape/concat; float32 NaN payloads, uint64, complex, bool and untouched huge CSC")
    for label, invalid_ops, code in [
        ("axis", [{"op": "gather", "name": "ids", "axis": 2, "indices": [0]}], "invalid-axis"),
        ("steps", [{"op": "slice", "name": "ids", "starts": [0, 0], "counts": [1, 1], "steps": [1, 0]}], "invalid-slice"),
        ("target", [{"op": "concat", "name": "keep_sparse", "inputs": ["z", "z"], "axis": 1}], "duplicate-name"),
        ("typo", [{"op": "reshape", "name": "ids", "shape": [6, 1], "shpae": [1, 6]}], "invalid-json"),
    ]:
        bad_plan = OUT / f"bad-transform-{label}.json"
        bad_plan.write_text(json.dumps({"schema": "moonmatbridge/transform/1", "operations": invalid_ops}), encoding="utf-8")
        denied = fresh(OUT / f"{host}-bad-transform-{label}.mat")
        assert invoke(host, "transform", transform_source, bad_plan, denied, ok=False)["code"] == code
        assert not denied.exists()
    record(f"{host}: invalid transform plans reject atomically", "Invalid axes/steps, duplicate sparse target and typos produce no file")

snapshot_sources = [OUT / "scipy-uncompressed.mat", OUT / "scipy-sparse-True.mat", be_sparse]
for host in ("native", "js"):
    for i, source in enumerate(snapshot_sources):
        snapshot = fresh(OUT / f"{host}-snapshot-{i}.json")
        restored = fresh(OUT / f"{host}-snapshot-restored-{i}.mat")
        invoke(host, "snapshot", source, snapshot)
        document = json.loads(snapshot.read_text(encoding="utf-8"))
        assert document["schema"] == "moonmatbridge/snapshot/1" and document["byte_order"] == "little"
        assert all(len(a["real_hex"]) % 2 == 0 for a in document["variables"])
        invoke(host, "restore", snapshot, restored)
        command = [str(ROOT / "dist" / ("moonmat.exe" if platform.system() == "Windows" else "moonmat"))] if host == "native" else ["node", str(ROOT / "scripts" / "cli.mjs")]
        diff = subprocess.run(command + ["diff", str(source), str(restored)], capture_output=True, encoding="utf-8", timeout=30)
        assert diff.returncode == 0 and json.loads(diff.stdout)["content_equal"], (host, diff.stdout, diff.stderr)
        # Check dense and sparse payload bytes in the archive against the independent fixture producer.
        if i == 0:
            for a in document["variables"]:
                expected = data[a["name"]]
                target = expected.real if np.iscomplexobj(expected) else expected
                assert bytes.fromhex(a["real_hex"]) == target.astype(target.dtype.newbyteorder("<")).tobytes(order="F")
                if np.iscomplexobj(expected):
                    target = expected.imag
                    assert bytes.fromhex(a["imag_hex"]) == target.astype(target.dtype.newbyteorder("<")).tobytes(order="F")
        if i == 2:
            a = document["variables"][0]
            assert a["row_indices"] == [0, 2, 123] and a["col_ptrs"] == [0, 1, 2] and a["nzmax"] == 5
            assert bytes.fromhex(a["real_hex"]) == np.array([1.25, -0., 9.], dtype="<f8").tobytes()
    record(f"{host}: exact snapshot restore", "Dense NaN/complex/integer bytes, compressed mixed CSC, big-endian inactive capacity; exact content diff after restore")
    snapshot = OUT / f"{host}-snapshot-0.json"
    bad_snapshot = OUT / "snapshot-invalid-hex.json"
    document = json.loads(snapshot.read_text(encoding="utf-8"))
    document["variables"][0]["real_hex"] = "invalid hex"
    bad_snapshot.write_text(json.dumps(document), encoding="utf-8")
    denied = fresh(OUT / f"{host}-bad-snapshot.mat")
    assert invoke(host, "restore", bad_snapshot, denied, ok=False)["code"] == "invalid-json"
    assert not denied.exists()
    record(f"{host}: malformed snapshot rejects without partial output")

diff_a = OUT / "diff-original.mat"
diff_b = OUT / "diff-changed.mat"
diff_compressed = OUT / "diff-compressed.mat"
diff_values = {
    "bits": np.array([0x7ff8000000000042, 0x8000000000000000], dtype="uint64").view("float64").reshape(2, 1),
    "ids": np.array([[18446744073709551615]], dtype="uint64"),
    "s": sparse_cases["sparse_huge"],
}
savemat(diff_a, diff_values)
changed_values = {**diff_values, "bits": np.array([0x7ff8000000000043, 0], dtype="uint64").view("float64").reshape(2, 1), "ids": np.array([[18446744073709551614]], dtype="uint64")}
savemat(diff_b, changed_values)
savemat(diff_compressed, dict(reversed(list(diff_values.items()))), do_compression=True)
for host in ("native", "js"):
    command = [str(ROOT / "dist" / ("moonmat.exe" if platform.system() == "Windows" else "moonmat"))] if host == "native" else ["node", str(ROOT / "scripts" / "cli.mjs")]
    equal = subprocess.run(command + ["diff", str(diff_a), str(diff_compressed)], capture_output=True, encoding="utf-8", timeout=30)
    value = json.loads(equal.stdout)
    assert equal.returncode == 0 and value["content_equal"] and value["variable_order_changed"]
    different = subprocess.run(command + ["diff", str(diff_a), str(diff_b)], capture_output=True, encoding="utf-8", timeout=30)
    value = json.loads(different.stdout)
    assert different.returncode == 2 and not value["content_equal"] and value["changed_variables"] == 2
    assert value["variables"][0]["real_differences"] == 2 and value["variables"][0]["samples"][1]["coordinates"] == [1, 0]
    assert value["variables"][0]["samples"][0]["before_hex"] == "420000000000f87f"
    assert value["variables"][1]["real_differences"] == 1
    report_path = fresh(OUT / f"{host}-diff-report.json")
    saved = subprocess.run(command + ["diff", str(diff_a), str(diff_b), str(report_path)], capture_output=True, encoding="utf-8", timeout=30)
    assert saved.returncode == 2 and json.loads(report_path.read_text(encoding="utf-8"))["changed_variables"] == 2
    repeated = subprocess.run(command + ["diff", str(diff_a), str(diff_b), str(report_path)], capture_output=True, encoding="utf-8", timeout=30)
    assert repeated.returncode == 1 and json.loads(repeated.stderr)["code"] == "output-exists"
    record(f"{host}: exact diff CI codes and reports", "0 equal across encoding/order, 2 NaN payload/signed zero/uint64 changes, 1 existing output; exact coordinates and bytes")

unsupported = {
    "cell": {"x": np.array([[1, "text"]], dtype=object)},
    "struct": {"x": {"field": np.array([[1]])}},
    "char": {"x": "hello"},
}
for kind, value in unsupported.items():
    path = OUT / f"unsupported-{kind}.mat"
    savemat(path, value)
    for host in ("native", "js"):
        response = invoke(host, "info", path, ok=False)
        assert response["code"] == "unsupported-class", response
    record(f"unsupported {kind} fails explicitly", "Both hosts return structured error, never skip or flatten data")

v73 = OUT / "unsupported-v73.mat"
v73.write_bytes(b"MATLAB 7.3 MAT-file".ljust(128, b"\0"))
for host in ("native", "js"):
    assert invoke(host, "info", v73, ok=False)["code"] == "unsupported-v7.3"
record("MAT v7.3 rejected explicitly")

bad = OUT / "corrupt-checksum.mat"
contents = bytearray((OUT / "scipy-compressed.mat").read_bytes())
first_size = struct.unpack("<I", contents[132:136])[0]
contents[136 + first_size - 1] ^= 1
bad.write_bytes(contents)
for host in ("native", "js"):
    assert invoke(host, "info", bad, ok=False)["code"] == "invalid-zlib"
record("corrupt compressed checksum rejected by both hosts")

report = {
    "status": "passed", "version": json.loads((ROOT / "package.json").read_text(encoding="utf-8"))["version"], "scope": "Local independent SciPy/NumPy verification; MATLAB/Octave not executed",
    "environment": {"python": platform.python_version(), "numpy": np.__version__, "scipy": scipy.__version__, "platform": platform.platform()},
    "checks": checks, "passed": len(checks),
    "fixtures": [{"file": path.name, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()} for path in sorted(OUT.glob("*.mat")) if not "roundtrip" in path.name and not "from-json" in path.name],
}
(ROOT / "verification" / "local" / "interop-report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"status": "passed", "checks": len(checks), "report": "verification/local/interop-report.json"}))
