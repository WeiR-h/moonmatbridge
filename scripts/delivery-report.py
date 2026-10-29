"""Assemble final evidence only after immutable packages and public consumers pass."""
from pathlib import Path
import hashlib
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1]
REPORTS = ROOT / "verification/reports"
VERSION = json.loads((ROOT / "package.json").read_text(encoding="utf-8"))["version"]


def read(name, status="passed"):
    value = json.loads((REPORTS / name).read_text(encoding="utf-8"))
    assert value["status"] == status, (name, value.get("status"))
    assert value["version"] == VERSION, name
    return value


def main():
    version = read(f"v{VERSION}.json")
    compatibility = read(f"compatibility-v{VERSION}.json")
    gaps = read(f"compatibility-gaps-v{VERSION}.json", "characterized")
    octave = read(f"octave-v{VERSION}.json")
    selected = read(f"selection-v{VERSION}.json")
    workflows = read(f"workflows-v{VERSION}.json")
    licenses = read(f"licenses-v{VERSION}.json")
    snapshot = read(f"source-snapshot-v{VERSION}.json")
    ci = read(f"ci-v{VERSION}.json")
    assert not snapshot["changed_files"]
    assert snapshot["before"] == snapshot["after"] == version["source"]
    assert ci["checked_source_sha256"] == version["source"]["sha256"]
    registry = read(f"registry-v{VERSION}.json")
    audit = read(f"mooncake-audit-v{VERSION}.json")
    mooncakes = read(f"mooncakes-v{VERSION}.json")
    release = read(f"release-v{VERSION}.json")
    public = read(f"public-downloads-v{VERSION}.json")
    public_workflows = read(f"workflows-public-v{VERSION}.json")
    performance = read(f"performance-summary-v{VERSION}.json", "summarized")
    assert compatibility["base_classes"] == list(range(1, 16))
    assert {(c['host'], c['format'], c['operation']) for c in octave['checks']} == {(h,f,o) for h in ('native','js') for f in ('v6','v7') for o in ('roundtrip','compress')}
    assert workflows['passed'] == len(workflows['checks']) > 0
    assert public_workflows['passed'] == len(public_workflows['checks']) == workflows['passed']
    assert {(c['host'],c['workflow']) for c in workflows['checks']} == {(c['host'],c['workflow']) for c in public_workflows['checks']}
    assert public_workflows["released_output_hashes_match"]
    fingerprint = version["source"]["sha256"]
    assert fingerprint == registry["source"]["sha256"] == mooncakes["source_sha256"] == release["source_sha256"]
    assert audit["archive_sha256"] == mooncakes["archive_sha256"]
    downloaded = {row["file"]: row["sha256"] for row in public["assets"]}
    for archive in release["archives"]:
        assert downloaded[archive["file"]] == archive["sha256"]
    for kind in ("source", "js", "windows-x64"):
        assert public_workflows["public_archives_sha256"][kind] == downloaded[f"MoonMatBridge-v{VERSION}-{kind}.zip"]
    final_measurement = performance["measurements"][-1]
    missed = [target for target in final_measurement["targets"] if not target["passed"]]
    publications = []
    revisions = sorted((p.name.removeprefix('public-downloads-v').removesuffix('.json') for p in REPORTS.glob('public-downloads-v*.json')), key=lambda v: tuple(map(int,v.split('-')[0].split('.'))) + (int('-' not in v), int(v.rsplit('.',1)[1]) if '-rc.' in v else 0))
    for revision in revisions:
        registry_receipt = json.loads((REPORTS / f"mooncakes-v{revision}.json").read_text(encoding="utf-8"))
        download_receipt = json.loads((REPORTS / f"public-downloads-v{revision}.json").read_text(encoding="utf-8"))
        assert registry_receipt["status"] == download_receipt["status"] == "passed"
        tag_commit = subprocess.check_output(["git", "rev-parse", f"v{revision}^{{commit}}"], cwd=ROOT, text=True).strip()
        publications.append({"version": revision, "commit": tag_commit,
                             "github": download_receipt["github"], "mooncakes": registry_receipt["url"],
                             "verified_public_assets": len(download_receipt["assets"]),
                             "mooncakes_archive_sha256": registry_receipt["archive_sha256"]})
    evidence = [f"{prefix}-v{VERSION}.json" for prefix in ("compatibility", "octave", "selection", "workflows", "registry", "mooncake-audit", "mooncakes", "release", "public-downloads", "workflows-public", "performance-summary")]
    evidence.extend([f"v{VERSION}.json", f"compatibility-gaps-v{VERSION}.json", f"licenses-v{VERSION}.json", f"source-snapshot-v{VERSION}.json", f"ci-v{VERSION}.json"])
    report = {"status": "public_delivery_verified", "version": VERSION, "source": version["source"],
              "publication_history": publications,
              "verification": {"local_groups": len(version["checks"]), "mixed_class_host_cases": len(compatibility["checks"]),
                               "selected_host_cases": selected["passed"], "actual_octave_workflows": len(octave["checks"]),
                               "scientific_host_workflows": workflows["passed"], "public_scientific_host_workflows": public_workflows["passed"]},
              "performance": {"measured_versions": performance["measured_versions"], "runtime_source_sha256": performance["runtime_source_sha256"],
                              "unmet_engineering_targets": missed, "regressions_over_10_percent": final_measurement["regressions_over_10_percent"],
                              "scope": "Historical measurements are identified; delivery runtime equivalence is checked. No new delivery-version timing is claimed."},
              "open_compatibility": compatibility["remaining"] + [c['file'] for c in gaps['cases'] if c['compatibility_state'].startswith('unresolved')] + ["All public standard variants must pass before v1.0.0"],
              "organizer_state": {"registration": "initial_review_passed_user_notification_2026-10-28", "acceptance": "awaiting_formal_receipt", "award": "not_claimed"},
              "evidence": [{"file": name, "sha256": hashlib.sha256((REPORTS / name).read_bytes()).hexdigest()} for name in evidence],
              "scope": "Listed versions published and downloaded, exact public packages installed, and final scientific workflows reproduced. Publication is separate from full compatibility, engineering targets and organizer decisions."}
    path = REPORTS / f"delivery-v{VERSION}.json"
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps({"status": report["status"], "versions": len(publications), "unmet_engineering_targets": len(missed), "file": str(path)}))


if __name__ == "__main__":
    main()
