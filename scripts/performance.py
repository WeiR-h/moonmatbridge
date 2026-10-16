"""Reproducible same-machine native/JS codec measurements against v0.0.5."""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import json
import os
import platform
import shutil
import statistics
import subprocess
import time
import zipfile
from pathlib import Path
import numpy as np
from scipy.sparse import csc_matrix

ROOT = Path(__file__).resolve().parents[1]
LOCAL = ROOT / "verification/local/performance"
BASELINE = ROOT / ".local-tools/benchmark-v0.0.5"
BASE_SHA = "b9df1eddaacdefebc2e32eee468fada8cc9e6020"
spec = importlib.util.spec_from_file_location("mixed", ROOT / "examples/python/mixed_types.py")
mixed = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mixed)


def command(args, cwd=ROOT, timeout=600):
    r = subprocess.run([str(a) for a in args], cwd=cwd, capture_output=True, encoding="utf-8", timeout=timeout)
    assert r.returncode == 0, (args, r.stdout, r.stderr)
    return r.stdout.strip()


def fixtures():
    LOCAL.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(20261017)
    dense = rng.standard_normal(2 * 1024 * 1024).reshape((1024, 2048), order="F")
    complex_data = (dense[:512, :] + 1j * dense[512:, :]).astype(np.complex128)
    nested = rng.standard_normal(512 * 1024).reshape((512, 1024), order="F")
    for i in range(8):
        cell = np.empty((1, 1), dtype=object)
        cell[0, 0] = {"signal": nested, "label": "trial"} if i % 2 else nested
        nested = cell
    rows = np.arange(100000, dtype=np.int32) * 7 % 1000000
    cols = np.arange(100000, dtype=np.int32) % 1000
    sparse = csc_matrix((np.arange(100000, dtype=np.float64), (rows, cols)), shape=(1000000, 1000))
    selection = {f"v{i:02}": dense.reshape(-1, order="F")[i * 131072:(i + 1) * 131072].reshape((256, 512), order="F") for i in range(16)}
    inputs = [
        ("dense-16m", {"signal": dense}, False, False, ["read", "write"]),
        ("dense-be-16m", {"signal": dense}, False, True, ["read"]),
        ("complex-16m", {"wave": complex_data}, False, False, ["read", "write"]),
        ("nested-4m", {"experiment": nested}, False, False, ["read", "write"]),
        ("sparse-100k", {"system": sparse}, False, False, ["read", "write"]),
        ("compressed-random-16m", {"signal": dense}, True, False, ["read"]),
        ("zeros-16m", {"signal": np.zeros_like(dense)}, False, False, ["compress"]),
        ("select-1-of-16", selection, False, False, ["select"]),
    ]
    manifest = []
    for name, values, compressed, big, operations in inputs:
        data = mixed.deterministic_mat(values, compressed)
        if big: data = mixed.big_endian(data)
        path = LOCAL / (name + ".mat")
        path.write_bytes(data)
        manifest.append({"name": name, "path": str(path), "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(),
                         "payload_bytes": sum(v.nbytes if isinstance(v, np.ndarray) and v.dtype.kind != "O" else 0 for v in values.values()),
                         "operations": operations})
        if name == "nested-4m": manifest[-1]["payload_bytes"] = 4 * 1024 * 1024
        if name == "sparse-100k": manifest[-1]["payload_bytes"] = sparse.data.nbytes + sparse.indices.nbytes + sparse.indptr.nbytes
    (LOCAL / "manifest.json").write_text(json.dumps({"seed": 20261017, "cases": manifest}, indent=2) + "\n")
    return manifest


def build_baseline():
    if not BASELINE.exists():
        BASELINE.mkdir(parents=True)
        archive = LOCAL / "baseline-source.zip"
        command(["git", "archive", "--format=zip", f"--output={archive}", BASE_SHA])
        with zipfile.ZipFile(archive) as z:
            for info in z.infolist(): assert (BASELINE / info.filename).resolve().is_relative_to(BASELINE.resolve())
            z.extractall(BASELINE)
        shutil.copy2(ROOT / ".local-toolchain.json", BASELINE / ".local-toolchain.json")
        for name in ("src/bench_bridge", "src/cmd/bench"):
            shutil.copytree(ROOT / name, BASELINE / name)
    command(["node", ROOT / "scripts/build-bench.mjs", BASELINE])
    binary = BASELINE / "dist" / ("moonmat.exe" if platform.system() == "Windows" else "moonmat")
    if not binary.exists():
        command(["node", BASELINE / "scripts/build-native.mjs"], cwd=BASELINE)
        command(["node", BASELINE / "scripts/moon.mjs", "build", "src/bridge", "--target", "js", "--release", "--jobs", "1"], cwd=BASELINE)


def measure(root, host, path, operation, kind):
    if host == "native":
        binary = root / "_build/native/release/build/cmd/bench/bench.exe"
        args = [binary, path, operation, kind]
    else:
        module = root / "_build/js/release/build/bench_bridge/bench_bridge.js"
        args = ["node", "--expose-gc", ROOT / "scripts/bench-js.mjs", module, path, operation, kind]
    result = json.loads(command(args))
    assert result["checksum"] > 0 and result["peak_bytes"] > 0, result
    return result


def timing_batches(root, host, path, operation):
    batches = [measure(root, host, path, operation, "timing") for _ in range(3)]
    return {"samples_ms": [v for batch in batches for v in batch["samples_ms"]], "batches": batches}


def source_hash():
    digest = hashlib.sha256()
    for path in sorted((ROOT / "src").rglob("*")):
        if path.is_file():
            digest.update(path.relative_to(ROOT).as_posix().encode() + b"\0" + path.read_bytes() + b"\0")
    return digest.hexdigest()


def cli_measure(root, host, fixture, operation):
    executable = root / "dist" / ("moonmat.exe" if platform.system() == "Windows" else "moonmat")
    prefix = [executable] if host == "native" else ["node", root / "scripts/cli.mjs"]
    output = LOCAL / f"cli-{root.name}-{host}-{fixture['name']}-{operation}.mat"
    assert output.resolve().is_relative_to(LOCAL.resolve())
    samples = []
    last = None
    for i in range(35):
        output.unlink(missing_ok=True)
        action = {"read": "info", "write": "roundtrip", "compress": "compress", "select": "select"}[operation]
        args = prefix + [action, fixture["path"]]
        if action != "info": args.append(output)
        if action == "select": args.append("v00")
        start = time.perf_counter()
        last = json.loads(command(args, cwd=root))
        elapsed = (time.perf_counter() - start) * 1000
        if i >= 5: samples.append(elapsed)
    if operation in ("write", "compress"):
        mixed.assert_file_equal(output, fixture["path"])
    if operation == "select":
        from scipy.io import loadmat
        actual = loadmat(output, chars_as_strings=False)
        source = loadmat(fixture["path"], chars_as_strings=False)
        assert [k for k in actual if not k.startswith("__")] == ["v00"]
        mixed.assert_tree_equal(actual["v00"], source["v00"])
    return {"samples_ms": samples, "median_ms": statistics.median(samples), "p95_ms": sorted(samples)[28], "output_bytes": output.stat().st_size if output.exists() else None,
            "scope": "end to end: process startup, disk I/O, codec and response; includes five warmups"}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline-only", action="store_true")
    parser.add_argument("--case", action="append")
    args = parser.parse_args()
    manifest = fixtures()
    build_baseline()
    if not args.baseline_only: command(["node", ROOT / "scripts/build-bench.mjs", ROOT])
    version = json.loads((ROOT / "package.json").read_text())["version"]
    config = json.loads((ROOT / ".local-toolchain.json").read_text())
    baseline_file = LOCAL / "baseline-v0.0.5.json"
    baseline = json.loads(baseline_file.read_text()) if baseline_file.exists() else {"version": "0.0.5", "commit": BASE_SHA, "measurements": {}}
    report = {"version": version, "status": "running", "baseline_commit": BASE_SHA,
              "codec_source_sha256": source_hash(),
              "environment": {"platform": platform.platform(), "processor": platform.processor(), "node": command(["node", "--version"]),
                              "moon": command(["node", ROOT / "scripts/moon.mjs", "version"]), "architecture": platform.machine(),
                              "compiler": command([config.get("gcc", "cc"), "--version"]).splitlines()[0], "build": "MoonBit --release; fixed SDK and compiler for both revisions"},
              "protocol": {"warmup": 5, "samples": 30, "batches": 3, "batch_samples": 10,
                           "timing": "codec only; preloaded input/prepared write tree; JS GC outside samples",
                           "memory": "fresh child, no warmup, one operation; peak process working set/RSS includes input and write preparation"},
              "fixtures": [{k: v for k, v in x.items() if k != "path"} for x in manifest], "results": []}
    baseline["environment"] = report["environment"]
    baseline["protocol"] = report["protocol"]
    baseline["fixtures"] = report["fixtures"]
    for fixture in manifest:
        if args.case and fixture["name"] not in args.case: continue
        for operation in fixture["operations"]:
            for host in ("native", "js"):
                key = f"{fixture['name']}:{operation}:{host}"
                if key not in baseline["measurements"]:
                    timing = timing_batches(BASELINE, host, fixture["path"], operation)
                    memory = [measure(BASELINE, host, fixture["path"], operation, "memory")["peak_bytes"] for _ in range(3)]
                    baseline["measurements"][key] = {"fixture_sha256": fixture["sha256"], "timing": timing, "peak_bytes": memory}
                    baseline_file.write_text(json.dumps(baseline, indent=2) + "\n")
                    print("baseline " + key, flush=True)
                base = baseline["measurements"][key]
                assert base["fixture_sha256"] == fixture["sha256"]
                if "cli" not in base:
                    base["cli"] = cli_measure(BASELINE, host, fixture, operation)
                    baseline_file.write_text(json.dumps(baseline, indent=2) + "\n")
                    print("baseline CLI " + key, flush=True)
                if args.baseline_only: continue
                baseline_batches = []
                candidate_batches = []
                for _ in range(3):
                    baseline_batches.append(measure(BASELINE, host, fixture["path"], operation, "timing"))
                    candidate_batches.append(measure(ROOT, host, fixture["path"], operation, "timing"))
                base_timing = [v for batch in baseline_batches for v in batch["samples_ms"]]
                timing = {"samples_ms": [v for batch in candidate_batches for v in batch["samples_ms"]]}
                base_memory = [measure(BASELINE, host, fixture["path"], operation, "memory")["peak_bytes"] for _ in range(3)]
                memory = [measure(ROOT, host, fixture["path"], operation, "memory")["peak_bytes"] for _ in range(3)]
                samples = timing["samples_ms"]
                baseline_ms = statistics.median(base_timing)
                peak = statistics.median(memory)
                baseline_peak = statistics.median(base_memory)
                row = {"case": fixture["name"], "operation": operation, "host": host, "samples_ms": samples,
                       "median_ms": statistics.median(samples), "p95_ms": sorted(samples)[28], "baseline_median_ms": baseline_ms,
                       "baseline_samples_ms": base_timing, "baseline_peak_bytes_samples": base_memory,
                       "speedup": baseline_ms / statistics.median(samples), "peak_bytes_samples": memory,
                       "peak_bytes": peak, "baseline_peak_bytes": baseline_peak, "memory_reduction": 1 - peak / baseline_peak}
                row["payload_MiB_per_second"] = fixture["payload_bytes"] / 1048576 / (row["median_ms"] / 1000)
                report["results"].append(row)
                row["cli"] = cli_measure(ROOT, host, fixture, operation)
                row["baseline_cli"] = base["cli"]
                row["cli_speedup"] = base["cli"]["median_ms"] / row["cli"]["median_ms"]
                print(f"{key}: {row['speedup']:.3f}x, peak reduction {row['memory_reduction']:.1%}", flush=True)
                (LOCAL / f"candidate-v{version}.json").write_text(json.dumps(report, indent=2) + "\n")
    if args.baseline_only:
        shutil.copy2(baseline_file, ROOT / "verification/reports/performance-baseline-v0.0.5.json")
    else:
        report["status"] = "measured"
        report["targets"] = []
        for row in report["results"]:
            if row["case"] in ("dense-16m", "nested-4m") and row["operation"] == "write":
                report["targets"].append({"case": row["case"], "host": row["host"], "goal": "write time -30%, peak memory -25%",
                    "passed": row["speedup"] >= 1 / 0.7 and row["memory_reduction"] >= 0.25})
            if row["operation"] == "select":
                report["targets"].append({"case": row["case"], "host": row["host"], "goal": "select speed 2x, peak memory -40%",
                    "passed": row["speedup"] >= 2 and row["memory_reduction"] >= 0.40})
        report["regressions_over_10_percent"] = [{"case": row["case"], "operation": row["operation"], "host": row["host"],
            "speedup": row["speedup"], "memory_reduction": row["memory_reduction"]} for row in report["results"] if row["speedup"] < 1 / 1.1 or row["memory_reduction"] < -0.1]
        report["scope"] = "Same-machine codec measurement; targets must be evaluated per case/host. No organizer or award claim."
        target = LOCAL / f"partial-v{version}.json" if args.case else ROOT / f"verification/reports/performance-v{version}.json"
        target.write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
