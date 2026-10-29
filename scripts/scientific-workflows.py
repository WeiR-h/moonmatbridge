"""Execute three complete workflows on both real CLI hosts, with independent oracles."""
from __future__ import annotations
import hashlib
import argparse
import json
import os
import platform
import subprocess
import sys
from pathlib import Path
import numpy as np
import scipy
from scipy.io import loadmat

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "examples/python"))
from mixed_types import assert_file_equal, assert_tree_equal, deterministic_mat
from workflow_inputs import generate

VERSION = json.loads((ROOT / "package.json").read_text(encoding="utf-8"))["version"]
OUT = ROOT / "verification/local/workflows"
OUT.mkdir(parents=True, exist_ok=True)
INPUTS = ROOT / "examples/workflows"
checks = []
NATIVE_EXECUTABLE = ROOT / "dist" / ("moonmat.exe" if platform.system() == "Windows" else "moonmat")
JS_CLI = ROOT / "scripts/cli.mjs"


def fresh(name):
    path = OUT / name
    assert path.resolve().is_relative_to(OUT.resolve())
    path.unlink(missing_ok=True)
    return path


def invoke(host, *args, exit_code=0):
    prefix = [str(NATIVE_EXECUTABLE)] if host == "native" else ["node", str(JS_CLI)]
    environment = {key: value for key, value in os.environ.items()
                   if not key.startswith("MOON") and key not in {"NODE_PATH", "NODE_OPTIONS", "PYTHONPATH", "VIRTUAL_ENV"}}
    if host == "native":
        environment["PATH"] = str(Path(os.environ["SystemRoot"]) / "System32") if platform.system() == "Windows" else "/usr/bin:/bin"
    result = subprocess.run(prefix + [str(arg) for arg in args], cwd=ROOT, capture_output=True,
                            encoding="utf-8", timeout=60, env=environment)
    assert result.returncode == exit_code, (host, args, result.returncode, result.stdout, result.stderr)
    if args[0] == "diff" and len(args) == 4:
        return json.loads(Path(args[3]).read_text(encoding="utf-8"))
    return json.loads(result.stdout or result.stderr)


def record(host, workflow, assertions, outputs):
    checks.append({"host": host, "workflow": workflow, "status": "passed", "assertions": assertions,
                   "outputs": [{"file": p.name, "bytes": p.stat().st_size,
                                "sha256": hashlib.sha256(p.read_bytes()).hexdigest()} for p in outputs]})


def main():
    reproduced = OUT / "reproduced-inputs"
    generate(reproduced)
    for name in ("all-base-classes.mat", "sparse-system.mat", "signal.npy", "changed-signal.npy", "transform-plan.json", "manifest.json"):
        assert (INPUTS / name).read_bytes() == (reproduced / name).read_bytes(), name
    for host in ("native", "js"):
        archive = ROOT / "examples/mixed/research-mixed.mat"
        all_classes = INPUTS / "all-base-classes.mat"
        classes_copy = fresh(f"{host}-all-base-classes.mat")
        assert {r["class_id"] for r in invoke(host, "roots", all_classes)["roots"]} == set(range(1, 16))
        invoke(host, "roundtrip", all_classes, classes_copy)
        assert_file_equal(classes_copy, all_classes)
        compressed = fresh(f"{host}-archive-compressed.mat")
        restored = fresh(f"{host}-archive-restored.mat")
        roots = invoke(host, "roots", archive)["roots"]
        assert len(roots) == 13 and {r["class_id"] for r in roots}.issuperset({1, 2, 3, 4, 5})
        invoke(host, "compress", archive, compressed)
        invoke(host, "roundtrip", compressed, restored)
        assert_file_equal(compressed, archive)
        assert_file_equal(restored, archive)
        assert all(r["compressed"] for r in invoke(host, "roots", compressed)["roots"])
        tree_snapshot = fresh(f"{host}-archive-tree.json")
        tree_restored = fresh(f"{host}-archive-tree-restored.mat")
        tree_diff = fresh(f"{host}-archive-tree-diff.json")
        invoke(host, "snapshot-tree", archive, tree_snapshot)
        invoke(host, "restore-tree", tree_snapshot, tree_restored)
        invoke(host, "diff-tree", archive, tree_restored, tree_diff)
        assert_file_equal(tree_restored, archive)
        record(host, "mixed experimental archive", ["13 roots and recursive containers", "additional downloadable file covers every base class 1 through 15", "independent SciPy deep type/shape/field and raw numeric byte equality", "UTF8 labels and exact uint64", "compressed roots decoded then rewritten", "mixed tree snapshot restored via bounded output and exact comparison"], [compressed, restored, classes_copy, tree_snapshot, tree_restored, tree_diff])

        source = INPUTS / "sparse-system.mat"
        selected = fresh(f"{host}-system-only.mat")
        snapshot = fresh(f"{host}-system-snapshot.json")
        sparse_restored = fresh(f"{host}-system-restored.mat")
        roots = invoke(host, "roots", source)["roots"]
        assert [r["name"] for r in roots] == ["system", "configuration", "label"]
        assert roots[0]["shape"] == [1000000, 1000] and roots[0]["class_id"] == 5
        invoke(host, "select", source, selected, "system")
        invoke(host, "snapshot", selected, snapshot)
        invoke(host, "restore", snapshot, sparse_restored)
        invoke(host, "diff", selected, sparse_restored)
        before = loadmat(source, spmatrix=False)["system"]
        after = loadmat(sparse_restored, spmatrix=False)["system"]
        assert_tree_equal(after, before)
        assert after.nnz == 3 and np.signbit(after.data[1])
        archived = json.loads(snapshot.read_text(encoding="utf-8"))["variables"][0]
        assert archived["nzmax"] == 3 and archived["row_indices"] == [0, 2, 999999]
        denied = fresh(f"{host}-too-large-dense.mat")
        assert invoke(host, "densify", selected, "system", denied, exit_code=1)["code"] == "element-limit"
        assert not denied.exists()
        record(host, "large sparse simulation exchange", ["1,000,000 by 1,000 with three stored slots", "configuration and Chinese label alongside CSC", "selected CSC snapshot/restore and exact diff", "independent pointers/rows/negative zero and capacity", "explicit densify rejects element limit without partial output"], [selected, snapshot, sparse_restored])

        mat = fresh(f"{host}-signal.mat")
        transformed = fresh(f"{host}-transformed.mat")
        exported = fresh(f"{host}-transformed.npy")
        copied = fresh(f"{host}-transformed-copy.mat")
        changed = fresh(f"{host}-transformed-changed.mat")
        diff_report = fresh(f"{host}-changed-report.json")
        invoke(host, "from-npy", INPUTS / "signal.npy", "signal", mat)
        invoke(host, "transform", mat, INPUTS / "transform-plan.json", transformed)
        invoke(host, "npy", transformed, "signal", exported)
        signal = np.load(INPUTS / "signal.npy", allow_pickle=False)
        expected = signal.reshape((8, 6), order="F").transpose()[0:3, 0:4][[2, 0, 2], :]
        actual = np.load(exported, allow_pickle=False)
        assert_tree_equal(actual, expected)
        # Inspect original input separately: the transform intentionally gathers other rows.
        assert signal.ravel(order="F").view("<u8")[:2].tolist() == [0x7ff8000000000042, 0x8000000000000000]
        assert_tree_equal(loadmat(mat)["signal"], signal)
        invoke(host, "roundtrip", transformed, copied)
        assert invoke(host, "diff", transformed, copied)["content_equal"]
        changed_data = actual.copy(order="F")
        changed_data[0, 0] += 0.25
        changed.write_bytes(deterministic_mat({"signal": changed_data}))
        diff = invoke(host, "diff", transformed, changed, diff_report, exit_code=2)
        assert not diff["content_equal"] and diff["changed_variables"] == 1
        assert diff["variables"][0]["real_differences"] == 1
        assert diff["variables"][0]["samples"][0]["coordinates"] == [0, 0]
        missing = fresh(f"{host}-missing.npy")
        assert invoke(host, "npy", transformed, "missing", missing, exit_code=1)["code"] == "missing-variable"
        assert not missing.exists()
        record(host, "NumPy to MoonBit transform and difference check", ["NPY to MAT to reshape/permute/slice/gather to NPY", "independent NumPy column-major and raw-byte oracle", "input NaN payload and signed zero preserved", "diff exit 0 equal and exit 2 at coordinate [0,0]", "missing export exit 1 with no partial output"], [mat, transformed, exported, diff_report])
    report = {"status": "passed", "version": VERSION, "producer": f"SciPy {scipy.__version__} / NumPy {np.__version__}",
              "passed": len(checks), "checks": checks,
              "consumer_environment": "MoonBit/Python/module injection variables removed; native PATH contains only Windows System32 or Linux system bins",
              "scope": "Actual native and JS commands plus independent Python oracles; examples demonstrate reproducible workflows, not external adoption or organizer acceptance."}
    (ROOT / f"verification/reports/workflows-v{VERSION}.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Three scientific workflows: {len(checks)} host workflows passed")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--native-executable", type=Path)
    parser.add_argument("--js-cli", type=Path)
    args = parser.parse_args()
    if args.native_executable: NATIVE_EXECUTABLE = args.native_executable.resolve()
    if args.js_cli: JS_CLI = args.js_cli.resolve()
    main()
