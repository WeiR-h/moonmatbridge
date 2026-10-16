"""Execute real GNU Octave production/consumption; missing tool is an error."""
from __future__ import annotations
import hashlib
import json
import platform
import shutil
import subprocess
from pathlib import Path
from scipy.io import loadmat

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "verification/local/octave"
VERSION = json.loads((ROOT / "package.json").read_text())["version"]


def literal(path):
    return "'" + str(path).replace("\\", "/").replace("'", "''") + "'"


def main():
    tool = shutil.which("octave-cli") or shutil.which("octave")
    if not tool:
        raise RuntimeError("GNU Octave is required; no execution receipt can be generated without it")
    OUT.mkdir(parents=True, exist_ok=True)
    report = {"status": "running", "version": VERSION, "platform": platform.platform(), "checks": [], "files": [], "producer_variants": [],
              "scope": "Actual GNU Octave v6/v7 producer and consumer; not a MATLAB execution claim. Legacy objects and global flags are verified separately."}
    prefix = f"addpath({literal(ROOT / 'examples/octave')}); "
    def octave(code):
        result = subprocess.run([tool, "--no-gui", "--quiet", "--eval", prefix + code], cwd=ROOT, text=True, encoding="utf-8", capture_output=True, timeout=120)
        assert result.returncode == 0, result.stdout + result.stderr
        return result.stdout.strip()
    report["tool"] = octave("disp(version());")
    report["production"] = octave(f"produce({literal(OUT)});")
    for mode in ("v6", "v7"):
        source = OUT / f"octave-{mode}.mat"
        report["files"].append({"file": source.name, "bytes": source.stat().st_size, "sha256": hashlib.sha256(source.read_bytes()).hexdigest()})
        for host in ("native", "js"):
            command = [str(ROOT / "dist" / ("moonmat.exe" if platform.system() == "Windows" else "moonmat"))] if host == "native" else ["node", str(ROOT / "scripts/cli.mjs")]
            for operation in ("roundtrip", "compress"):
                output = OUT / f"{host}-{mode}-{operation}.mat"
                output.unlink(missing_ok=True)
                result = subprocess.run(command + [operation, str(source), str(output)], cwd=ROOT, text=True, capture_output=True, timeout=60)
                assert result.returncode == 0, result.stdout + result.stderr
                receipt = octave(f"verify_roundtrip({literal(source)}, {literal(output)});")
                report["checks"].append({"host": host, "format": mode, "operation": operation, "status": "passed", "receipt": receipt,
                                         "output_sha256": hashlib.sha256(output.read_bytes()).hexdigest()})
                print(receipt, flush=True)
    # Never silently remove known problematic producer cases from the evidence.
    # They are tested separately so their failures do not masquerade as valid MAT coverage.
    for source in sorted(OUT.glob("producer-*.mat")):
        row = {"file": source.name, "sha256": hashlib.sha256(source.read_bytes()).hexdigest(), "hosts": []}
        try:
            loadmat(source, chars_as_strings=False)
            row["scipy"] = "passed"
        except Exception as error:
            row["scipy"] = type(error).__name__ + ": " + str(error)
        try:
            row["octave_self_load"] = octave(f"verify_roundtrip({literal(source)}, {literal(source)});")
        except AssertionError as error:
            row["octave_self_load"] = "failed: " + str(error)
        for host in ("native", "js"):
            command = [str(ROOT / "dist" / ("moonmat.exe" if platform.system() == "Windows" else "moonmat"))] if host == "native" else ["node", str(ROOT / "scripts/cli.mjs")]
            output = OUT / f"edge-{host}-{source.name}"
            output.unlink(missing_ok=True)
            result = subprocess.run(command + ["roundtrip", str(source), str(output)], cwd=ROOT, text=True, capture_output=True, timeout=60)
            item = {"host": host, "returncode": result.returncode, "diagnostic": (result.stdout + result.stderr).strip()}
            if result.returncode == 0:
                try: item["consumer"] = octave(f"verify_roundtrip({literal(source)}, {literal(output)});")
                except AssertionError as error: item["consumer"] = "failed: " + str(error)
            else:
                assert not output.exists(), "Rejected input must not leave partial output"
            row["hosts"].append(item)
        row["status"] = "passed" if all(x["returncode"] == 0 and not x.get("consumer", "failed").startswith("failed") for x in row["hosts"]) else "unresolved_producer_variant"
        report["producer_variants"].append(row)
        print(source.name + ": " + row["status"], flush=True)
    report["status"] = "passed"
    (ROOT / f"verification/reports/octave-v{VERSION}.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
