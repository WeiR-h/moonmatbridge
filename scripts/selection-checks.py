"""Independent metadata/subset checks and failure atomicity for both CLI hosts."""
from __future__ import annotations
import hashlib
import importlib.util
import json
import platform
import struct
import subprocess
from pathlib import Path
import numpy as np
from scipy.io import loadmat
from scipy.sparse import csc_matrix

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "verification/local/selection"
OUT.mkdir(parents=True, exist_ok=True)
VERSION = json.loads((ROOT / "package.json").read_text())["version"]
spec = importlib.util.spec_from_file_location("mixed", ROOT / "examples/python/mixed_types.py")
mixed = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mixed)
checks = []


def invoke(host, *args, ok=True):
    prefix = [str(ROOT / "dist" / ("moonmat.exe" if platform.system() == "Windows" else "moonmat"))] if host == "native" else ["node", str(ROOT / "scripts/cli.mjs")]
    r = subprocess.run(prefix + [str(a) for a in args], cwd=ROOT, capture_output=True, text=True, encoding="utf-8", timeout=60)
    response = json.loads(r.stdout.strip() or r.stderr.strip())
    assert (r.returncode == 0) == ok, (host, args, response)
    return response


def fresh(name):
    path = OUT / name
    assert path.resolve().is_relative_to(OUT.resolve())
    path.unlink(missing_ok=True)
    return path


def tag(data, offset):
    kind, count = struct.unpack_from("<II", data, offset)
    if kind >> 16: return kind & 65535, offset + 4, kind >> 16, offset + 8
    return kind, offset + 8, count, offset + 8 + count + (-count) % 8


def main():
    for source in sorted((ROOT / "verification/local/compatibility").glob("all-classes-*.mat")):
        expected = loadmat(source, chars_as_strings=False, spmatrix=False)
        names = [name for name in expected if not name.startswith("__")]
        selected = ["cross_nested", "legacy_record", "uint64_ids", "title"]
        for host in ("native", "js"):
            roots = invoke(host, "roots", source)["roots"]
            assert [r["name"] for r in roots] == names
            assert {r["class_id"] for r in roots} == set(range(1, 16))
            assert all(r["compressed"] == ("compressed" in source.name) for r in roots)
            assert next(r for r in roots if r["name"] == "wave")["complex"]
            assert next(r for r in roots if r["name"] == "logical_mask")["logical"]
            assert [r["name"] for r in roots if r["global"]] == expected["__globals__"]
            output = fresh(f"{host}-{source.name}")
            invoke(host, "select", source, output, *selected)
            actual = loadmat(output, chars_as_strings=False, spmatrix=False)
            assert [name for name in actual if not name.startswith("__")] == selected
            assert actual["__globals__"] == [name for name in selected if name in expected["__globals__"]]
            for name in selected: mixed.assert_tree_equal(actual[name], expected[name])
            checks.append({"host": host, "case": source.name, "status": "passed", "sha256": hashlib.sha256(source.read_bytes()).hexdigest()})
    data = bytearray(mixed.deterministic_mat({"good": np.array([[1.0]]), "bad": np.array([[18446744073709551615]], dtype="uint64")}))
    second = tag(data, 128)[3]
    _, position, _, _ = tag(data, second)
    for _ in range(3): position = tag(data, position)[3]
    struct.pack_into("<I", data, position, 12)  # stored signed -1 under declared uint64
    bad = OUT / "unselected-invalid-conversion.mat"
    bad.write_bytes(data)
    source = ROOT / "verification/local/compatibility/all-classes-little-compressed.mat"
    corrupt = bytearray(source.read_bytes()); corrupt[-1] ^= 1
    checksum = OUT / "unselected-bad-checksum.mat"; checksum.write_bytes(corrupt)
    for host in ("native", "js"):
        for path, chosen, error in [(bad, "good", "value-range"), (checksum, "uint64_ids", "invalid-zlib")]:
            output = fresh(f"rejected-{host}-{path.name}")
            assert invoke(host, "info", path, ok=False)["code"] == error
            assert invoke(host, "roots", path, ok=False)["code"] == error
            assert invoke(host, "select", path, output, chosen, ok=False)["code"] == error
            assert not output.exists()
            checks.append({"host": host, "case": path.name, "status": "passed", "expected_error": error, "no_partial_output": True})
    sparse = csc_matrix(([1.0], ([999999], [999])), shape=(1000000, 1000))
    source = OUT / "large-sparse.mat"
    logical = csc_matrix(([True], ([999999], [999])), shape=(1000000, 1000))
    complex_data = csc_matrix(([1.0 + 2.0j], ([999999], [999])), shape=(1000000, 1000))
    source.write_bytes(mixed.deterministic_mat({"good": np.array([[1.0]]), "system": sparse, "logical_system": logical, "complex_system": complex_data}))
    for host in ("native", "js"):
        roots = invoke(host, "roots", source)["roots"]
        assert roots[1]["class_id"] == 5 and roots[1]["shape"] == [1000000, 1000]
        assert roots[2]["class_id"] == 5 and roots[2]["logical"]
        assert roots[3]["class_id"] == 5 and roots[3]["complex"]
        invoke(host, "select", source, fresh(f"sparse-selected-{host}.mat"), "good")
        checks.append({"host": host, "case": "large sparse shape without densification", "status": "passed"})
    report = {"status": "passed", "version": VERSION, "checks": checks, "passed": len(checks),
              "scope": "Independent SciPy subset oracle, metadata classes, malformed unselected data, checksum validation and atomic CLI errors; both hosts"}
    (ROOT / f"verification/reports/selection-v{VERSION}.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"Strict selected reads and roots: {len(checks)} independent host scenarios passed")


if __name__ == "__main__": main()
