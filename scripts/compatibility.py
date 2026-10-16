"""Independent public Level 5 base-class matrix, including mixed recursive files."""
from __future__ import annotations
import hashlib
import importlib.util
import json
import platform
import subprocess
import sys
from pathlib import Path
import numpy as np
import scipy

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("mixed_types", ROOT / "examples/python/mixed_types.py")
mixed = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mixed)
OUT = ROOT / "verification/local/compatibility"
OUT.mkdir(parents=True, exist_ok=True)
VERSION = json.loads((ROOT / "package.json").read_text())["version"]


def values():
    result = mixed.mixed_values()
    for dtype in ("float64", "float32", "int8", "uint8", "int16", "uint16", "int32", "uint32", "int64", "uint64"):
        result["nd_" + dtype] = np.arange(8, dtype=dtype).reshape((2, 2, 2), order="F")
        result["empty_" + dtype] = np.empty((0, 2, 3), dtype=dtype)
    nested = np.empty((1, 2), dtype=object)
    nested[0, 0] = {"samples": result["measurements"], "records": result["experiments"]}
    nested[0, 1] = result["sparse_signal"]
    result["cross_nested"] = nested
    result["empty_nd_cell"] = np.empty((0, 2, 3), dtype=object)
    result["empty_nd_struct"] = np.empty((0, 2, 3), dtype=[("signal", object), ("label", object)])
    return result


def main():
    checks = []
    fixtures = []
    for compressed in (False, True):
        plain = mixed.deterministic_mat(values(), compressed)
        for endian in ("little", "big"):
            data = plain if endian == "little" else mixed.big_endian(plain)
            name = f"all-classes-{endian}-{'compressed' if compressed else 'plain'}.mat"
            source = OUT / name
            source.write_bytes(data)
            fixtures.append({"file": name, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()})
            for host in ("native", "js"):
                dest = OUT / f"{host}-{name}"
                dest.unlink(missing_ok=True)
                command = [str(ROOT / "dist" / ("moonmat.exe" if platform.system() == "Windows" else "moonmat"))] if host == "native" else ["node", str(ROOT / "scripts/cli.mjs")]
                subprocess.run(command + ["roundtrip", str(source), str(dest)], cwd=ROOT, check=True, capture_output=True, timeout=60)
                mixed.assert_file_equal(dest, source)
                checks.append({"case": name, "host": host, "status": "passed"})
    report = {"status": "passed", "version": VERSION, "producer": f"SciPy {scipy.__version__} / NumPy {np.__version__}",
              "base_classes": list(range(1, 16)), "checks": checks, "fixtures": fixtures,
              "coverage": ["all public base classes in mixed files", "little/big endian", "plain/compressed", "numeric N-D and empty N-D",
                           "cell to struct to cell", "struct to cell to sparse", "legacy class name and fields", "UTF8 Chinese/nonBMP"],
              "remaining": ["MATLAB runtime execution not claimed", "noncanonical CSC remains rejected", "non-UTF8 legacy names remain rejected",
                            "producer-specific UTF16/nonBMP dimensions require separate receipts"]}
    (ROOT / f"verification/reports/compatibility-v{VERSION}.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"All 15 base classes: {len(checks)} independent mixed-file host checks passed")


if __name__ == "__main__":
    main()
