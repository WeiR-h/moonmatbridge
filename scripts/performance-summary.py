"""Summarize measured revisions; verify the delivery revision has identical runtime code."""
from pathlib import Path
import hashlib
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1]
VERSION = json.loads((ROOT / "package.json").read_text(encoding="utf-8"))["version"]
REPORTS = ROOT / "verification/reports"
REFERENCE = "v0.0.8"


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT)


def main():
    files = git("ls-tree", "-r", "--name-only", REFERENCE, "--", "src").decode().splitlines()
    files = [name for name in files if name != "src/version.mbt" and
             (name.endswith((".mbt", ".c")) or Path(name).name == "moon.pkg")]
    old, new = hashlib.sha256(), hashlib.sha256()
    for name in files:
        for digest, data in ((old, git("show", f"{REFERENCE}:{name}")), (new, (ROOT / name).read_bytes())):
            digest.update(name.encode() + b"\0" + data.replace(b"\r\n", b"\n") + b"\0")
    assert old.hexdigest() == new.hexdigest(), "Runtime changed: inherited measurements would be misleading"
    reports = [json.loads((REPORTS / f"performance-v{v}.json").read_text(encoding="utf-8")) for v in ("0.0.7", "0.0.8")]
    for report in reports:
        assert report["status"] == "measured" and len(report["results"]) == 24
    summary = {"status": "summarized", "version": VERSION, "measured_versions": [r["version"] for r in reports],
               "inherited_from": REFERENCE, "runtime_source_sha256": new.hexdigest(), "runtime_files": len(files),
               "hash_policy": "All src .mbt/.c and moon.pkg, excluding version.mbt; CRLF normalized to LF. This includes test and benchmark code.",
               "baseline_commit": reports[0]["baseline_commit"],
               "measurements": [{"version": r["version"], "environment": r["environment"], "protocol": r["protocol"],
                                 "targets": r["targets"], "regressions_over_10_percent": r["regressions_over_10_percent"],
                                 "report_sha256": hashlib.sha256((REPORTS / f'performance-v{r["version"]}.json').read_bytes()).hexdigest(),
                                 "results": [{k: row[k] for k in ("case", "operation", "host", "median_ms", "p95_ms", "speedup", "memory_reduction", "payload_MiB_per_second", "cli_speedup")} for row in r["results"]]}
                                for r in reports],
               "scope": "Historical measured versions remain identified. Delivery runtime matches v0.0.8 except version text; no fresh v0.0.9 timing claimed. Targets are project engineering goals, not official award criteria."}
    (REPORTS / f"performance-summary-v{VERSION}.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"status": "summarized", "version": VERSION, "runtime_source_sha256": new.hexdigest()}))


if __name__ == "__main__":
    main()
