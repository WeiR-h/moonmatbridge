"""Update current-version declarations without rewriting historical evidence."""
import json
import re
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
version = sys.argv[1]
assert re.fullmatch(r"\d+\.\d+\.\d+", version)
old = json.loads((root / "package.json").read_text())["version"]
for name in ["package.json", "moon.mod", "src/version.mbt", "examples/registry_consumer/consumer_wbtest.mbt", "README.md", "docs/API.md"]:
    path = root / name
    path.write_text(path.read_text(encoding="utf-8").replace(old, version), encoding="utf-8", newline="\n")
print(f"Current version: {old} -> {version}")
