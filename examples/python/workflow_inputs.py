"""Deterministic, independent inputs for the three scientific workflow examples."""
from io import BytesIO
from pathlib import Path
import hashlib
import json
import numpy as np
from scipy.sparse import csc_matrix
from mixed_types import deterministic_mat, all_base_values


def inputs():
    # Construct CSC directly: an explicit negative zero must remain a stored entry.
    system = csc_matrix((np.array([1.25, -0.0, 9.0], dtype="<f8"),
                         np.array([0, 2, 999999], dtype="int32"),
                         np.array([0, 2] + [2] * 998 + [3], dtype="int32")),
                        shape=(1000000, 1000))
    sparse = deterministic_mat({"system": system,
                                "configuration": {"solver": "CG", "tolerance": np.array([[1e-8]])},
                                "label": "稀疏仿真交换"})
    signal = np.arange(48, dtype="<f8").reshape((4, 6, 2), order="F") / 16.0
    signal = np.asfortranarray(signal)
    bits = signal.ravel(order="F").view("<u8")
    bits[0], bits[1] = 0x7ff8000000000042, 0x8000000000000000
    stream = BytesIO()
    np.save(stream, signal, allow_pickle=False)
    plan = {"schema": "moonmatbridge/transform/1", "operations": [
        {"op": "reshape", "name": "signal", "shape": [8, 6]},
        {"op": "permute", "name": "signal", "axes": [1, 0]},
        {"op": "slice", "name": "signal", "starts": [0, 0], "counts": [3, 4]},
        {"op": "gather", "name": "signal", "axis": 0, "indices": [2, 0, 2]},
    ]}
    expected = signal.reshape((8, 6), order="F").transpose()[0:3, 0:4][[2, 0, 2], :].copy(order="F")
    expected[0, 0] += 0.25
    changed = BytesIO()
    np.save(changed, expected, allow_pickle=False)
    return {"all-base-classes.mat": deterministic_mat(all_base_values()),
            "sparse-system.mat": sparse, "signal.npy": stream.getvalue(), "changed-signal.npy": changed.getvalue(),
            "transform-plan.json": (json.dumps(plan, indent=2) + "\n").encode()}


def generate(directory):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    files = inputs()
    for name, payload in files.items():
        (directory / name).write_bytes(payload)
    manifest = {"producer": "NumPy/SciPy; deterministic header and exact binary input bits",
                "files": [{"file": name, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
                          for name, data in files.items()]}
    (directory / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")


if __name__ == "__main__":
    generate(Path(__file__).resolve().parents[1] / "workflows")
