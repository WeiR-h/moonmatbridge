"""Run after: moonmat sample sample.mat; moonmat npy sample.mat temperature temperature.npy."""
from pathlib import Path
import numpy as np
from scipy.io import loadmat, savemat

sample = Path("sample.mat")
data = loadmat(sample)
assert int(data["sample_id"][0, 0]) == 9007199254740993
assert int(data["sample_id"][0, 1]) == 18446744073709551615
assert data["temperature"].shape == (2, 3)
assert data["spectrum"][0, 0] == 1 - 2j
np.testing.assert_array_equal(np.load("temperature.npy", allow_pickle=False), data["temperature"])

output = Path("python-data.mat")
if output.exists():
    raise FileExistsError("Choose a new output path before running the example again")
savemat(output, {"signal": np.arange(12, dtype=np.float64).reshape((3, 4)),
                 "id": np.array([[9007199254740993]], dtype=np.uint64)}, do_compression=True)
print("SciPy loaded exact MoonMatBridge data; wrote python-data.mat for moonmat info/roundtrip.")
