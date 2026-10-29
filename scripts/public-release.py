"""Publish a verified immutable version and check actual public consumers/downloads."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
import platform
import subprocess
import time
import urllib.request
import uuid
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VERSION = json.loads((ROOT / "package.json").read_text())["version"]
REPO = "WeiR-h/moonmatbridge"
REPORTS = ROOT / "verification/reports"
MANIFEST = "https://mooncakes.io/api/v0/manifest/WeiR-h/moonmatbridge"


def run(args, timeout=600, ok=True):
    r = subprocess.run([str(x) for x in args], cwd=ROOT, capture_output=True, encoding="utf-8", timeout=timeout,
                       env={**os.environ, "PYTHONUTF8": "1"})
    if ok: assert r.returncode == 0, (args, r.stdout, r.stderr)
    return r


def manifest():
    with urllib.request.urlopen(MANIFEST, timeout=30) as response:
        return json.load(response)


def write_report(name, value):
    (REPORTS / f"{name}-v{VERSION}.json").write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def mooncakes():
    fingerprint = run(["node", "--input-type=module", "-e", "import {sourceFingerprint} from './scripts/verify.mjs'; console.log(sourceFingerprint().sha256);"]).stdout.strip()
    verified = json.loads((REPORTS / f"v{VERSION}.json").read_text())
    assert verified["status"] == "passed" and fingerprint == verified["source"]["sha256"], "Source changed after verification"
    current = manifest()
    already_registered = any(v["version"] == VERSION for v in current["versions"])
    dry = run(["node", "scripts/moon.mjs", "publish", "--dry-run"], ok=False)
    dry_text = dry.stdout + dry.stderr
    # This SDK treats the registry's successful 202 response as exit 1.
    # Require the explicit server success text, then independently audit bytes.
    assert dry.returncode == 0 or "Dry run completed successfully. No changes were made." in dry_text or (already_registered and "409 Conflict" in dry_text and "duplicated" in dry_text), dry_text
    print(dry_text.strip(), flush=True)
    python = os.environ.get("MOONMAT_PYTHON") or str(ROOT / ".venv/Scripts/python.exe")
    print(run([python, "scripts/audit-mooncake.py"]).stdout.strip(), flush=True)
    current = manifest()
    if already_registered:
        audit_now=json.loads((REPORTS / f"mooncake-audit-v{VERSION}.json").read_bytes())
        assert current["version"] == VERSION and current["metadata"]["checksum"] == audit_now["archive_sha256"], "Existing registry archive differs"
    if not any(v["version"] == VERSION for v in current["versions"]):
        published = run(["node", "scripts/moon.mjs", "publish"], ok=False)
        publish_text = published.stdout + published.stderr
        assert published.returncode == 0 or "202 Accepted" in publish_text, publish_text
        print(publish_text.strip(), flush=True)
    for _ in range(18):
        current = manifest()
        if current["version"] == VERSION and current["build_status"] == "success" and not current["yanked"]: break
        if current["version"] == VERSION and current["build_status"] == "failed": raise RuntimeError("Mooncakes build failed")
        print(f"Waiting for public Mooncakes v{VERSION} build", flush=True)
        time.sleep(10)
    else: raise RuntimeError("Public build is not confirmed; do not mark publication complete")
    print(run(["node", "scripts/registry-verify.mjs"]).stdout.strip(), flush=True)
    installed = json.loads((REPORTS / f"registry-v{VERSION}.json").read_text())
    audit = json.loads((REPORTS / f"mooncake-audit-v{VERSION}.json").read_text())
    assert installed["status"] == "passed"
    assert current["metadata"]["checksum"] == audit["archive_sha256"], "Registry archive differs from audited archive"
    write_report("mooncakes", {"status": "passed", "version": VERSION, "module": REPO,
        "url": f"https://mooncakes.io/docs/{REPO}@{VERSION}", "public_manifest_url": MANIFEST,
        "build_status": current["build_status"], "archive_sha256": audit["archive_sha256"],
        "source_sha256": fingerprint, "installed_source_files": installed["installed_files"],
        "targets": ["js", "wasm-gc", "native"], "scope": "Actual public package, audited checksum and fresh consumers; source hashes are checked."})


def public_workflows(directory, exe):
    extracted = {}
    for kind in ("source", "js"):
        archive = directory / f"MoonMatBridge-v{VERSION}-{kind}.zip"
        target = directory / kind
        with zipfile.ZipFile(archive) as package:
            for item in package.infolist():
                assert (target / item.filename).resolve().is_relative_to(target.resolve())
            package.extractall(target)
        extracted[kind] = next(target.iterdir())
    source, js = extracted["source"], extracted["js"]
    # Use the downloaded filesystem adapter with the downloaded precompiled module.
    # Only its two development-location declarations change; no format logic is added.
    adapter = (source / "scripts/cli.mjs").read_text(encoding="utf-8")
    import_line = "import {root, version} from './moon.mjs';"
    api_line = "const api = await import(pathToFileURL(join(root, '_build/js/release/build/bridge/bridge.js')));"
    assert adapter.count(import_line) == adapter.count(api_line) == 1
    adapter = adapter.replace(import_line, f"const version = {json.dumps(VERSION)};")
    adapter = adapter.replace(api_line, f"const api = await import({json.dumps((js / 'bridge.mjs').as_uri())});")
    cli = directory / "downloaded-cli.mjs"
    cli.write_text(adapter, encoding="utf-8")
    python = os.environ.get("MOONMAT_PYTHON") or str(ROOT / ".venv/Scripts/python.exe")
    result = run([python, source / "scripts/scientific-workflows.py", "--native-executable", exe, "--js-cli", cli])
    print(result.stdout.strip(), flush=True)
    workflow_report = source / f"verification/reports/workflows-v{VERSION}.json"
    receipt = json.loads(workflow_report.read_text(encoding="utf-8"))
    original = json.loads((directory / f"workflows-v{VERSION}.json").read_text(encoding="utf-8"))
    expected = {(row["host"], row["workflow"]): row["outputs"] for row in original["checks"]}
    for row in receipt["checks"]:
        assert row["outputs"] == expected[row["host"], row["workflow"]], "Public reproduction differs from released workflow outputs"
    tree_script = source / "scripts/tree-checks.py"
    if tree_script.exists():
        print(run([python, tree_script, "--native-executable", exe, "--js-cli", cli]).stdout.strip(), flush=True)
        tree_receipt = json.loads((source / f"verification/reports/tree-operations-v{VERSION}.json").read_text(encoding="utf-8"))
        write_report("tree-operations-public", tree_receipt)
    receipt["released_output_hashes_match"] = True
    source_script = source / "scripts/source-checks.py"
    if source_script.exists():
        print(run([python,source_script,"--native-executable",exe,"--js-cli",cli,"--fixture-manifest",ROOT/"verification/local/file-performance/manifest.json"]).stdout.strip(),flush=True)
        source_receipt=json.loads((source/f"verification/reports/source-operations-v{VERSION}.json").read_bytes())
        write_report("source-operations-public",source_receipt)
    close_script=source/"scripts/tree-close-checks.py"
    if close_script.exists():
        print(run([python,close_script,"--native-executable",exe,"--js-cli",cli]).stdout.strip(),flush=True)
        write_report("tree-close-public",json.loads((source/f"verification/reports/tree-close-v{VERSION}.json").read_bytes()))
    receipt["public_archives_sha256"] = {kind: hashlib.sha256((directory / f"MoonMatBridge-v{VERSION}-{kind}.zip").read_bytes()).hexdigest() for kind in ("source", "js", "windows-x64")}
    receipt["scope"] = "All scientific workflows executed using publicly downloaded inputs, native executable and precompiled JS module, checked by independent NumPy/SciPy and exact released output hashes. Adapter only points to the downloaded module."
    (directory / f"workflows-public-v{VERSION}.json").write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    write_report("workflows-public", receipt)
    return receipt["passed"]


def github():
    local = json.loads((REPORTS / f"v{VERSION}.json").read_text())
    release = json.loads((ROOT / f"dist/release-v{VERSION}.json").read_text())
    assert local["source"]["sha256"] == release["source_sha256"]
    tag = f"v{VERSION}"
    assets = [ROOT / "dist" / row["file"] for row in release["archives"]]
    assets += [ROOT / "dist/SHA256SUMS.txt", ROOT / f"dist/release-v{VERSION}.json"]
    assets += sorted((ROOT / "examples/mixed").glob("*.mat"))
    assets += [ROOT / "examples/mixed/manifest.json"]
    all_classes = ROOT / "examples/workflows/all-base-classes.mat"
    if all_classes.exists(): assets.append(all_classes)
    assets += [p for p in REPORTS.glob(f"*-v{VERSION}.json") if "-public-" not in p.name and p.name.startswith(("octave-", "compatibility-", "performance-", "file-performance-", "mooncakes-", "selection-", "workflows-", "licenses-", "source-snapshot-", "source-operations-", "ci-", "tree-operations-", "tree-close-", "name-encoding-", "api-contract-", "producer-variants-", "stable-gate-"))]
    assets.extend(ROOT / "docs" / name for name in ("TREE_DIFF.md", "TREE_SNAPSHOT.md", "TREE_CLOSE.md") if (ROOT / "docs" / name).exists())
    review = ROOT / f"docs/REVIEW_EVIDENCE-v{VERSION}.md"
    if review.exists(): assets.append(review)
    from github_release import ensure_release, download_release
    notes = ROOT / 'docs' / f'RELEASE-v{VERSION}.md'
    published = ensure_release(tag, assets, notes)
    directory = ROOT / "verification/local" / f"public-v{VERSION}-{uuid.uuid4().hex}"
    directory.mkdir(parents=True)
    download_release(published, directory, assets)
    hashes = []
    for path in assets:
        public = directory / path.name
        expected = hashlib.sha256(path.read_bytes()).hexdigest()
        assert public.exists() and hashlib.sha256(public.read_bytes()).hexdigest() == expected, path.name
        hashes.append({"file": path.name, "sha256": expected})
    archive = directory / f"MoonMatBridge-v{VERSION}-windows-x64.zip"
    native = directory / "native"
    with zipfile.ZipFile(archive) as z:
        for info in z.infolist(): assert (native / info.filename).resolve().is_relative_to(native.resolve())
        z.extractall(native)
    exe = next(native.rglob("moonmat.exe"))
    result = run([exe, "version"])
    assert VERSION in result.stdout
    info = json.loads(run([exe, "info", directory / "research-mixed.mat"]).stdout)
    assert len(info["arrays"]) == 13
    receipt = {"status": "passed", "version": VERSION, "assets": hashes, "downloaded_native_mixed_roots": 13,
               "github": f"https://github.com/{REPO}/releases/tag/{tag}",
               "scope": "Public assets downloaded and compared byte-for-byte; downloaded executable consumes mixed file. Local archive consumers are in release receipt."}
    if (ROOT / "scripts/scientific-workflows.py").exists():
        receipt["public_scientific_workflows_passed"] = public_workflows(directory, exe)
    write_report("public-downloads", receipt)
    (directory / "public-downloads.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(json.dumps({"status": "passed", "public_assets": len(hashes), "receipt": str(directory / "public-downloads.json")}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("phase", choices=["mooncakes", "github"])
    args = parser.parse_args()
    {"mooncakes": mooncakes, "github": github}[args.phase]()
