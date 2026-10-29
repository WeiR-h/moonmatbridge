"""Execute real GNU Octave production/consumption; missing tool is an error."""
from __future__ import annotations
import hashlib
import importlib.util
import json
import platform
import shutil
import subprocess
import struct
from pathlib import Path
from scipy.io import loadmat

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "verification/local/octave"
VERSION = json.loads((ROOT / "package.json").read_text(encoding="utf-8"))["version"]

def verify_unicode_storage(source):
    """Independent raw-unit check of the actual Octave UTF16 producer."""
    spec=importlib.util.spec_from_file_location('variants',ROOT/'scripts/variant-analysis.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    data=source.read_bytes();pos=128
    while pos<len(data):
        kind,n,start,end=module.element(data,pos)
        if kind!=14: raise AssertionError('Expected uncompressed Octave v6 matrix')
        body=data[pos:end];_,_,_,next_pos=module.element(body,8)
        _,size,dims,next_pos=module.element(body,next_pos)
        shape=list(struct.unpack_from('<'+'i'*(size//4),body,dims))
        _,size,name,next_pos=module.element(body,next_pos)
        label=body[name:name+size].decode('utf-8')
        if label=='unicode_title':
            tag,size,start,_=module.element(body,next_pos)
            assert tag==17 and shape==[1,4],(tag,shape)
            assert body[start:start+size]=='科研🌙'.encode('utf-16le')
            return {'status':'passed','shape':shape,'storage_tag':tag,'utf16_units':4,'unicode_scalars':3,'source_sha256':hashlib.sha256(data).hexdigest(),'scope':'Actual Octave producer uses four UTF16 units for three scalars; both hosts and Octave consumer verify the complete file.'}
        pos=end
    raise AssertionError('Missing actual non-BMP producer case')


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
    report['unicode_storage']=verify_unicode_storage(OUT/'octave-v6.mat')
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
                source_input=source if operation=="roundtrip" else output
                roots_result=subprocess.run(command+["roots",str(source_input)],cwd=ROOT,text=True,encoding="utf-8",capture_output=True,timeout=60)
                assert roots_result.returncode==0,roots_result.stdout+roots_result.stderr
                roots=json.loads(roots_result.stdout)["roots"]
                selected=OUT/f"{host}-{mode}-{operation}-source-selected.mat"
                selected.unlink(missing_ok=True)
                selected_result=subprocess.run(command+["select",str(source_input),str(selected),*[row["name"] for row in roots]],cwd=ROOT,text=True,encoding="utf-8",capture_output=True,timeout=60)
                assert selected_result.returncode==0,selected_result.stdout+selected_result.stderr
                source_receipt=octave(f"verify_roundtrip({literal(source)}, {literal(selected)});")
                report["checks"].append({"host": host, "format": mode, "operation": operation, "status": "passed", "receipt": receipt,
                                         "output_sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
                                         "source_backend_receipt":source_receipt,"source_selection_sha256":hashlib.sha256(selected.read_bytes()).hexdigest(),"source_roots":roots})
                print(receipt, flush=True)
    # Never silently remove known problematic producer cases from the evidence.
    # They are tested separately so their failures do not masquerade as valid MAT coverage.
    for source in sorted(OUT.glob("producer-*.mat")):
        row = {"file": source.name, "sha256": hashlib.sha256(source.read_bytes()).hexdigest(), "hosts": []}
        spec=importlib.util.spec_from_file_location('variants',ROOT/'scripts/variant-analysis.py')
        analysis=importlib.util.module_from_spec(spec);spec.loader.exec_module(analysis)
        row['format_analysis']=analysis.analyze(source)
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
