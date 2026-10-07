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


def invoke(host: str, *args: str | Path, ok: bool = True) -> dict:
    command = [str(ROOT / "dist" / "moonmat.exe")] if host == "native" else ["node", str(ROOT / "scripts" / "cli.mjs")]
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

unsupported = {
    "cell": {"x": np.array([[1, "text"]], dtype=object)},
    "struct": {"x": {"field": np.array([[1]])}},
    "char": {"x": "hello"},
}
from scipy.sparse import csc_matrix
unsupported["sparse"] = {"x": csc_matrix(np.eye(3))}
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
