"""Create local source/native/JS archives and verify actual clean consumers. Uses Python stdlib only."""
from __future__ import annotations
import hashlib
import json
import os
import re
import platform
import subprocess
import uuid
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DIST = ROOT / "dist"
REPORTS = ROOT / "verification" / "reports"
LOCAL = ROOT / "verification" / "local"
VERSION = json.loads((ROOT / "package.json").read_text(encoding="utf-8"))["version"]
report = json.loads((REPORTS / f"v{VERSION}.json").read_text(encoding="utf-8"))
source_hash = report["source"]["sha256"]
assert report["status"] == "passed" and platform.system() == "Windows"
DIST.mkdir(exist_ok=True)


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def add(z: zipfile.ZipFile, path: Path, prefix: str, relative: str | None = None) -> None:
    name = relative or path.relative_to(ROOT).as_posix()
    z.write(path, f"{prefix}/{name}")


def run(command: list[str], cwd: Path, env: dict | None = None) -> subprocess.CompletedProcess:
    result = subprocess.run(command, cwd=cwd, env=env, capture_output=True, encoding="utf-8", timeout=120)
    assert result.returncode == 0, (command, result.returncode, result.stdout, result.stderr)
    return result


def extract(archive: Path, destination: Path) -> Path:
    assert destination.resolve().is_relative_to(LOCAL.resolve())
    destination.mkdir(parents=True, exist_ok=False)
    with zipfile.ZipFile(archive) as z:
        assert z.testzip() is None
        for info in z.infolist():
            target = (destination / info.filename).resolve()
            assert target.is_relative_to(destination.resolve())
        z.extractall(destination)
    children = list(destination.iterdir())
    assert len(children) == 1 and children[0].is_dir()
    return children[0]


source_name = f"MoonMatBridge-v{VERSION}-source"
source_zip = DIST / f"{source_name}.zip"
excluded = {".git", "_build", ".moon", ".venv", ".local-tools", "dist", "node_modules", "__pycache__", ".pytest_cache"}
with zipfile.ZipFile(source_zip, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for directory, directories, files in os.walk(ROOT):
        directory = Path(directory)
        directories[:] = [name for name in directories if name not in excluded and (directory / name) != LOCAL]
        for name in sorted(files):
            if name in {".git", ".local-toolchain.json", "SOURCE_SHA256.txt"} or name.endswith(".pyc"):
                continue
            add(z, directory / name, source_name)
    z.writestr(f"{source_name}/SOURCE_SHA256.txt", source_hash + "\n")

assert digest(DIST / "moonmat.exe") == report["native_sha256"]
native_name = f"MoonMatBridge-v{VERSION}-windows-x64"
native_zip = DIST / f"{native_name}.zip"
portable_readme = r"""MoonMatBridge v0.0.1 — Windows x64 portable CLI

Open PowerShell in this folder:
  .\moonmat.exe version
  .\moonmat.exe sample sample.mat
  .\moonmat.exe info sample.mat
  .\moonmat.exe roots sample.mat
  .\moonmat.exe dump sample.mat sample.json
  .\moonmat.exe pack sample.json from-json.mat
  .\moonmat.exe npy sample.mat temperature temperature.npy
  .\moonmat.exe from-npy temperature.npy temperature from-numpy.mat
  .\moonmat.exe select sample.mat subset.mat temperature
  .\moonmat.exe roundtrip sample.mat copy.mat
  .\moonmat.exe transform sample.mat examples\transform-plan.json transformed.mat
  .\moonmat.exe compress transformed.mat compressed.mat
  .\moonmat.exe snapshot compressed.mat archive.json
  .\moonmat.exe restore archive.json restored.mat
  .\moonmat.exe diff compressed.mat restored.mat equality-report.json
  .\moonmat.exe sparsify sample.mat temperature sparse.mat
  .\moonmat.exe densify sparse.mat temperature dense.mat
  powershell -ExecutionPolicy Bypass -File examples\workflows\demo.ps1

The executable requires no MoonBit, C compiler, Python or Node installation.
Only Windows system KERNEL32.dll and msvcrt.dll are imported in this build.
Output paths must be NEW; existing files are never overwritten.
Core: MAT Level 5 recursive cell/struct/char/legacy object, dense numeric/logical arrays, complex float32/64,
CSC double/logical/complex double, little/big endian, deterministic compressed/uncompressed writing,
primitive NPY, raw-byte slice/gather/concat/reshape/permutation, exact snapshot/restore and diff.
Unsupported: private MCOS/opaque/function workspace, MAT v4/v7.3, noncanonical or non-double numerical CSC,
structured/object/string NPY, NPZ, floating tolerance and file streaming.

Use examples/sample.json as a fresh pack input, or examples/sample.mat for info.
JSON values are column-major; int64/uint64 use decimal strings.
NaN payload bits survive binary and snapshot conversions but are normalized in readable dump/pack JSON.
diff exits: 0 equal, 2 changed, 1 format/usage/IO error. Sparse arrays never expand implicitly.
See docs, LICENSE, NOTICE, THIRD_PARTY.md and verification for details.
MATLAB execution and organizer acceptance remain unverified. Actual GNU Octave receipts, when available,
are included under verification/octave-v0.0.1.json. Public downloads are verified separately.
"""
with zipfile.ZipFile(native_zip, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    add(z, DIST / "moonmat.exe", native_name, "moonmat.exe")
    for name in ["LICENSE", "NOTICE", "THIRD_PARTY.md", "CHANGELOG.md", "docs/API.md", "docs/COMPATIBILITY.md", "docs/JSON.md", "docs/FORMAT.md", "docs/RECIPES.md", "docs/DIFFERENTIATION.md", "docs/ITERATIONS-v0.0.3.md", "examples/transform-plan.json", "examples/sample.json", "examples/sample.mat", "examples/python/interop_example.py", "examples/matlab/interop_example.m"]:
        add(z, ROOT / name, native_name)
    for path in sorted((ROOT / "examples/mixed").glob("*")):
        add(z, path, native_name)
    for path in sorted((ROOT / "examples/workflows").glob("*")):
        add(z, path, native_name)
    for name in ["docs/SCIENTIFIC_WORKFLOWS.md", "docs/REVIEW_EVIDENCE-v0.0.9.md", "docs/ACCEPTANCE.md"]:
        add(z, ROOT / name, native_name)
    for name in ["docs/COMPATIBILITY_MATRIX.md", "docs/PERFORMANCE.md", "benchmarks/manifest.json"]:
        add(z, ROOT / name, native_name)
    for path in sorted((ROOT / "examples/octave").rglob("*")):
        if path.is_file(): add(z, path, native_name)
    for path in sorted(REPORTS.glob("*.json")):
        add(z, path, native_name, "verification/" + path.name)
    z.writestr(f"{native_name}/README.txt", portable_readme.replace("v0.0.1", f"v{VERSION}"))
    z.writestr(f"{native_name}/SOURCE_SHA256.txt", source_hash + "\n")

js_name = f"MoonMatBridge-v{VERSION}-js"
js_zip = DIST / f"{js_name}.zip"
with zipfile.ZipFile(js_zip, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    add(z, ROOT / "_build/js/release/build/bridge/bridge.js", js_name, "bridge.mjs")
    for name in ["LICENSE", "NOTICE", "THIRD_PARTY.md", "docs/API.md", "docs/COMPATIBILITY.md", "docs/JSON.md", "docs/FORMAT.md", "docs/RECIPES.md", "examples/transform-plan.json", "examples/sample.json"]:
        add(z, ROOT / name, js_name)
    for path in sorted((ROOT / "examples/mixed").glob("*")):
        add(z, path, js_name)
    for path in sorted((ROOT / "examples/workflows").glob("*")):
        add(z, path, js_name)
    add(z, ROOT / "docs/SCIENTIFIC_WORKFLOWS.md", js_name)
    add(z, ROOT / "docs/ACCEPTANCE.md", js_name)
    z.writestr(f"{js_name}/README.txt", f"MoonMatBridge v{VERSION} JS exports. Import bridge.mjs; see docs/API.md. Host-neutral MoonBit build, no Python/zlib dependency. Browser UI is not shipped/tested.\n")
    z.writestr(f"{js_name}/SOURCE_SHA256.txt", source_hash + "\n")

# Verify unpacked consumers in fresh directories, with no development runtime on PATH for the native CLI.
fresh_root = LOCAL / ("release-consumer-" + uuid.uuid4().hex)
native = extract(native_zip, fresh_root / "native")
clean_env = dict(os.environ)
for name in list(clean_env):
    if name.startswith("MOON") or name in {"NODE_PATH", "PYTHONPATH", "VIRTUAL_ENV"}:
        clean_env.pop(name, None)
clean_env["PATH"] = str(Path(os.environ["SystemRoot"]) / "System32")
exe = str(native / "moonmat.exe")
assert run([exe, "version"], native, clean_env).stdout.strip() == f"MoonMatBridge v{VERSION}"
consumer = native / "中文测试 data"
consumer.mkdir()
commands = [
    ["sample", str(consumer / "sample.mat")],
    ["info", str(consumer / "sample.mat")],
    ["roots", str(consumer / "sample.mat")],
    ["dump", str(consumer / "sample.mat"), str(consumer / "sample.json")],
    ["pack", str(consumer / "sample.json"), str(consumer / "packed.mat")],
    ["roundtrip", str(consumer / "sample.mat"), str(consumer / "roundtrip.mat")],
    ["npy", str(consumer / "sample.mat"), "temperature", str(consumer / "temperature.npy")],
    ["select", str(consumer / "sample.mat"), str(consumer / "subset.mat"), "temperature"],
    ["from-npy", str(consumer / "temperature.npy"), "temperature", str(consumer / "from-numpy.mat")],
    ["dump", str(consumer / "from-numpy.mat"), str(consumer / "from-numpy.json")],
    ["transform", str(consumer / "sample.mat"), str(native / "examples/transform-plan.json"), str(consumer / "transformed.mat")],
    ["compress", str(consumer / "transformed.mat"), str(consumer / "compressed.mat")],
    ["snapshot", str(consumer / "compressed.mat"), str(consumer / "snapshot.json")],
    ["restore", str(consumer / "snapshot.json"), str(consumer / "restored.mat")],
    ["diff", str(consumer / "compressed.mat"), str(consumer / "restored.mat"), str(consumer / "equal-report.json")],
    ["sparsify", str(consumer / "sample.mat"), "temperature", str(consumer / "sparse.mat")],
    ["densify", str(consumer / "sparse.mat"), "temperature", str(consumer / "dense.mat")],
    ["diff", str(consumer / "sample.mat"), str(consumer / "dense.mat")],
]
commands.extend([
    ["info", str(native / "examples/mixed/research-mixed.mat")],
    ["roots", str(native / "examples/mixed/research-mixed.mat")],
    ["roundtrip", str(native / "examples/mixed/research-mixed-big-endian.mat"), str(consumer / "mixed.mat")],
    ["compress", str(consumer / "mixed.mat"), str(consumer / "mixed-compressed.mat")],
    ["select", str(consumer / "mixed-compressed.mat"), str(consumer / "mixed-selected.mat"), "measurements", "experiments", "title"],
])
for args in commands:
    response = json.loads(run([exe] + args, native, clean_env).stdout)
    assert response.get("status", "ok") == "ok", response
assert (consumer / "sample.mat").read_bytes() == (consumer / "packed.mat").read_bytes() == (consumer / "roundtrip.mat").read_bytes()
expected_temperature = next(a for a in json.loads((consumer / "sample.json").read_text(encoding="utf-8"))["arrays"] if a["name"] == "temperature")
assert json.loads((consumer / "from-numpy.json").read_text(encoding="utf-8"))["arrays"] == [expected_temperature]
assert json.loads((consumer / "equal-report.json").read_text(encoding="utf-8"))["content_equal"]
different = subprocess.run([exe, "diff", str(consumer / "sample.mat"), str(consumer / "transformed.mat")], cwd=native, env=clean_env, capture_output=True, encoding="utf-8", timeout=10)
assert different.returncode == 2 and not json.loads(different.stdout)["content_equal"]
original = digest(consumer / "sample.mat")
repeated = subprocess.run([exe, "sample", str(consumer / "sample.mat")], cwd=native, env=clean_env, capture_output=True, encoding="utf-8", timeout=10)
assert repeated.returncode == 1 and json.loads(repeated.stderr)["code"] == "output-exists"
assert digest(consumer / "sample.mat") == original

demo_output = native / "portable-workflows"
demo = run([str(Path(os.environ["SystemRoot"]) / "System32/WindowsPowerShell/v1.0/powershell.exe"), "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(native / "examples/workflows/demo.ps1"), "-OutputDirectory", str(demo_output)], native, clean_env)
assert json.loads((demo_output / "demo-receipt.json").read_text(encoding="utf-8-sig"))["status"] == "passed"
(LOCAL / f"portable-demo-v{VERSION}.log").write_text(demo.stdout + demo.stderr, encoding="utf-8")

source = extract(source_zip, fresh_root / "source")
config = json.loads((ROOT / ".local-toolchain.json").read_text(encoding="utf-8-sig")) if (ROOT / ".local-toolchain.json").exists() else {}
source_env = dict(os.environ)
if config.get("moonHome"):
    source_env["MOON_HOME"] = config["moonHome"]
assert not (source / ".local-toolchain.json").exists() and not (source / "_build").exists()
run(["node", "scripts/moon.mjs", "check", "--target", "js", "--deny-warn"], source, source_env)
clean_tests = run(["node", "scripts/moon.mjs", "test", "--target", "js", "--deny-warn"], source, source_env)
test_match = re.search(r"Total tests: (\d+), passed: (\d+), failed: 0", clean_tests.stdout)
assert test_match and test_match.group(1) == test_match.group(2)
fingerprint_probe = run(["node", "--input-type=module", "-e", "import {sourceFingerprint} from './scripts/verify.mjs'; console.log(sourceFingerprint().sha256);"], source, source_env)
assert fingerprint_probe.stdout.strip() == source_hash

js = extract(js_zip, fresh_root / "js")
probe = js / "consumer.mjs"
probe.write_text("""import assert from 'node:assert/strict';
import * as api from './bridge.mjs';
import {readFileSync} from 'node:fs';
const result=api.sample_mat();
assert.equal(JSON.parse(api.result_status(result)).status,'ok');
const bytes=api.result_bytes(result);
assert.equal(JSON.parse(api.inspect_mat(bytes)).arrays.length,4);
assert.equal(JSON.parse(api.inspect_roots(bytes)).roots.length,4);
const rebuilt=api.json_to_mat(api.mat_to_json(bytes));
assert.equal(JSON.parse(api.result_status(rebuilt)).status,'ok');
assert.deepEqual(api.result_bytes(rebuilt),bytes);
const compressed=api.compress_mat(bytes);
assert.equal(JSON.parse(api.result_status(compressed)).status,'ok');
const compressedBytes=api.result_bytes(compressed);
const snapshot=api.mat_to_snapshot(compressedBytes);
const restored=api.snapshot_to_mat(snapshot);
assert.equal(JSON.parse(api.result_status(restored)).status,'ok');
assert.equal(JSON.parse(api.compare_mat(bytes,api.result_bytes(restored))).content_equal,true);
const sparse=api.convert_storage(bytes,'temperature',true);
assert.equal(JSON.parse(api.result_status(sparse)).status,'ok');
assert.equal(JSON.parse(api.inspect_mat(api.result_bytes(sparse))).arrays[0].storage,'csc');
const plan=JSON.stringify({schema:'moonmatbridge/transform/1',operations:[{op:'gather',name:'temperature',axis:1,indices:[2,0]}]});
const transformed=api.transform_mat(api.result_bytes(sparse),JSON.stringify({schema:'moonmatbridge/transform/1',operations:[]}));
assert.equal(JSON.parse(api.result_status(transformed)).status,'ok');
const selected=api.transform_mat(bytes,plan);
assert.equal(JSON.parse(api.result_status(selected)).status,'ok');
assert.equal(JSON.parse(api.compare_mat(bytes,api.result_bytes(selected))).content_equal,false);
const mixed=readFileSync('./examples/mixed/research-mixed-compressed.mat');
assert.equal(JSON.parse(api.inspect_mat(mixed)).arrays.length,13);
const mixedCopy=api.roundtrip_mat(mixed);
assert.equal(JSON.parse(api.result_status(mixedCopy)).status,'ok');
const tree=JSON.parse(api.inspect_mat(api.result_bytes(mixedCopy)));
assert.deepEqual(new Set(tree.arrays.map(x=>x.storage)),new Set(['dense','csc','char','cell','struct','object']));
console.log('Fresh JS consumer: passed');
""", encoding="utf-8")
run(["node", str(probe)], js)

workflow_report = json.loads((REPORTS / f"workflows-v{VERSION}.json").read_text(encoding="utf-8"))
assert workflow_report["status"] == "passed" and workflow_report["version"] == VERSION and workflow_report["passed"] == 6
workflow_directory = LOCAL / "workflows"
for check in workflow_report["checks"]:
    for output in check["outputs"]:
        assert digest(workflow_directory / output["file"]) == output["sha256"]
workflow_name = f"MoonMatBridge-v{VERSION}-workflows"
workflow_zip = DIST / f"{workflow_name}.zip"
members = []
with zipfile.ZipFile(workflow_zip, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    paths = [(path, "outputs/" + path.name) for path in sorted(workflow_directory.iterdir()) if path.is_file()]
    for directory in ("examples/workflows", "examples/mixed"):
        paths.extend((path, path.relative_to(ROOT).as_posix()) for path in sorted((ROOT / directory).iterdir()) if path.is_file())
    paths.extend((ROOT / name, name) for name in ("LICENSE", "NOTICE", "THIRD_PARTY.md"))
    paths.append((REPORTS / f"workflows-v{VERSION}.json", f"verification/workflows-v{VERSION}.json"))
    for path, name in paths:
        add(z, path, workflow_name, name)
        members.append({"file": name, "bytes": path.stat().st_size, "sha256": digest(path)})
    z.writestr(f"{workflow_name}/manifest.json", json.dumps({"version": VERSION, "status": "verified_outputs", "files": members}, indent=2) + "\n")
    z.writestr(f"{workflow_name}/README.txt", f"MoonMatBridge v{VERSION}: actual independently checked native/JS scientific outputs, inputs and receipts. Download the matching Windows CLI, then run examples/workflows/demo.ps1 -Executable ABSOLUTE_PATH_TO_MOONMAT_EXE to reproduce in a new directory. Full independent Python oracles are in the source archive.\n")
with zipfile.ZipFile(workflow_zip) as z:
    assert z.testzip() is None
    for member in members:
        assert hashlib.sha256(z.read(f'{workflow_name}/{member["file"]}')).hexdigest() == member["sha256"]

archives = [{"file": path.name, "bytes": path.stat().st_size, "sha256": digest(path)} for path in [source_zip, native_zip, js_zip, workflow_zip]]
result = {
    "status": "passed", "version": VERSION, "source_sha256": source_hash,
    "native_sha256": digest(DIST / "moonmat.exe"), "archives": archives,
    "fresh_consumers": {"native": f"version + {len(commands)} commands + sparse/transform/compress/snapshot/diff + Unicode/spaces + no overwrite; PATH limited to System32; diff-change exit 2 verified; complete three-workflow PowerShell demo passed",
                        "source": f"unpacked source check and {test_match.group(2)} JS tests; no local settings/build cache bundled",
                        "js": "unpacked exports: recursive mixed cell/struct/char/object fixture, JSON, compression, sparse, mixed transform, snapshot restore and exact diff",
                        "workflow_evidence": "actual six-workflow outputs matched their independent report hashes, then every bundled file was checked after ZIP creation"},
    "scope": "Local archives and fresh consumers; no public publishing or organizer acceptance",
}
(DIST / f"release-v{VERSION}.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
(DIST / "SHA256SUMS.txt").write_text("".join(f'{entry["sha256"]}  {entry["file"]}\n' for entry in archives), encoding="utf-8")
print(json.dumps({"status": "passed", "archives": archives, "fresh_consumers": 3}, ensure_ascii=False))
