"""Independently check an already published release without signing in."""
import argparse
import hashlib
import json
import os
import re
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = "WeiR-h/moonmatbridge"
GITHUB = f"https://api.github.com/repos/{REPOSITORY}"


def fetch(url):
    request = urllib.request.Request(url, headers={
        "User-Agent": "MoonMatBridge-public-check", "Cache-Control": "no-cache",
    })
    for attempt in range(3):
        try:
            with urllib.request.urlopen(request, timeout=35) as response:
                return response.read()
        except (OSError, urllib.error.URLError):
            if attempt == 2:
                raise
            time.sleep(2 ** attempt)


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def receipt(kind, version):
    path = ROOT / "verification/reports" / f"{kind}-v{version}.json"
    result = json.loads(path.read_bytes())
    require(result["version"] == version and result["status"] == "passed", f"Invalid receipt: {path.name}")
    return result


def asset_hashes(rows):
    return {row["file"]: row["sha256"] for row in rows}


def unpack(archive, directory):
    with zipfile.ZipFile(archive) as bundle:
        for member in bundle.infolist():
            require((directory / member.filename).resolve().is_relative_to(directory.resolve()),
                    "Invalid path in release archive")
        bundle.extractall(directory)


def run_windows_demo(directory, archive, version):
    native = directory / "native"
    unpack(archive, native)
    executable = native / archive.stem / "moonmat.exe"
    expected = receipt("workflows-demo-public", version)
    require(sha256(executable.read_bytes()) == expected["executable_sha256"], "Windows executable checksum differs")
    output = directory / "demo"
    subprocess.run([
        "powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
        executable.parent / "examples/workflows/demo.ps1", "-OutputDirectory", output,
    ], cwd=executable.parent, check=True, timeout=120)
    result = json.loads((output / "demo-receipt.json").read_text(encoding="utf-8-sig"))
    require(result["status"] == "passed" and len(result["commands"]) == expected["commands"]
            and all(row["expected_exit"] == row["actual_exit"] for row in result["commands"])
            and asset_hashes(result["files"]) == asset_hashes(expected["files"]), "Windows demo differs from public receipt")
    return len(result["commands"])


def verify(args):
    version = args.version
    tag = "v" + version
    distribution = receipt("distribution", version)
    downloads = receipt("public-downloads", version)
    registry = receipt("mooncakes", version)
    ref = json.loads(fetch(f"{GITHUB}/git/ref/tags/{tag}"))
    release = json.loads(fetch(f"{GITHUB}/releases/tags/{tag}"))
    manifest = json.loads(fetch(f"https://mooncakes.io/api/v0/manifest/{REPOSITORY}@{version}"))

    require(ref["object"]["sha"] == distribution["tag_commit"], "GitHub tag differs from public receipt")
    require(release["tag_name"] == tag and release["published_at"] and not release["draft"] and not release["prerelease"],
            "GitHub release is not public and stable")
    require(manifest["version"] == version and manifest["build_status"] == "success" and not manifest["yanked"]
            and manifest["metadata"]["checksum"] == registry["archive_sha256"], "Mooncakes manifest differs from public receipt")
    expected = asset_hashes(downloads["assets"])
    assets = {row["name"]: row for row in release["assets"]}
    require(len(assets) == distribution["public_assets"] and set(assets) == set(expected), "GitHub asset list differs")
    for name, row in assets.items():
        require(row["digest"] == "sha256:" + expected[name], f"GitHub asset digest differs: {name}")

    archives = {kind: f"MoonMatBridge-{tag}-{kind}.zip" for kind in ("source", "js", "windows-x64", "workflows")}
    sample = "all-base-classes.mat"
    with tempfile.TemporaryDirectory(prefix="mmb-public-") as temporary:
        directory = Path(temporary).resolve()
        require(directory.parent == Path(tempfile.gettempdir()).resolve(), "Unexpected temporary directory")
        for name in [*archives.values(), sample]:
            data = fetch(f"https://github.com/{REPOSITORY}/releases/download/{tag}/{name}")
            require(len(data) == assets[name]["size"] and sha256(data) == expected[name], f"Download checksum differs: {name}")
            (directory / name).write_bytes(data)
            print(f"Download verified: {name}", flush=True)
        result = {"status": "passed", "version": version, "tag_commit": ref["object"]["sha"],
                  "assets_checked_against_receipt": len(assets), "downloads_hashed": len(archives) + 1,
                  "mooncakes_manifest_sha256": registry["archive_sha256"]}
        if args.node_demo:
            target = directory / "js"
            unpack(directory / archives["js"], target)
            subprocess.run([
                "node", ROOT / "scripts/verify-mixed-sample.mjs",
                target / Path(archives["js"]).stem / "bridge.mjs", directory / sample,
            ], check=True, timeout=45)
            result["node_demo"] = "passed"
        if args.windows_demo:
            result["windows_demo_commands"] = run_windows_demo(directory, directory / archives["windows-x64"], version)
        print(json.dumps(result, ensure_ascii=False))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", default="0.1.10", help="Published version with checked-in public receipts")
    parser.add_argument("--node-demo", action="store_true", help="Inspect the published mixed sample using the public JS module")
    parser.add_argument("--windows-demo", action="store_true", help="Run the three workflows from the Windows release")
    args = parser.parse_args()
    if not re.fullmatch(r"\d+\.\d+\.\d+", args.version):
        parser.error("--version requires three numeric components")
    if args.windows_demo and os.name != "nt":
        parser.error("--windows-demo requires Windows")
    try:
        verify(args)
    except (OSError, RuntimeError, ValueError, KeyError, zipfile.BadZipFile, subprocess.SubprocessError) as error:
        parser.exit(1, f"Public verification failed: {error}\n")


if __name__ == "__main__":
    main()
