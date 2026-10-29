"""Update current-version declarations without rewriting historical evidence."""
import json
import re
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
version = sys.argv[1]
assert re.fullmatch(r"\d+\.\d+\.\d+(?:-rc\.\d+)?", version)
old = json.loads((root / "package.json").read_text())["version"]
for name in ["package.json", "moon.mod", "src/version.mbt", "examples/registry_consumer/consumer_wbtest.mbt", "README.md", "docs/API.md"]:
    path = root / name
    text = path.read_text(encoding="utf-8")
    if name == "README.md":
        text = text.replace(f"# MoonMatBridge v{old}", f"# MoonMatBridge v{version}")
        text = text.replace(f"当前源码版本为 v{old}", f"当前源码版本为 v{version}")
        text = text.replace(f"| 能力 | v{old} |", f"| 能力 | v{version} |")
        text = text.replace(f"@{old}", f"@{version}")
    elif name == "docs/API.md":
        text = re.sub(r"^# MoonBit API v[0-9.]+(?:-rc\.\d+)?", f"# MoonBit API v{version}", text)
        text = re.sub(r"WeiR-h/moonmatbridge@[0-9.]+(?:-rc\.\d+)?", f"WeiR-h/moonmatbridge@{version}", text)
    else:
        text = text.replace(old, version)
    path.write_text(text, encoding="utf-8", newline="\n")
print(f"Current version: {old} -> {version}")
