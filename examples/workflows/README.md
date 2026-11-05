# 三个可直接复现的科研流程

将 Windows 便携包解压到路径较短的目录，在包的根目录执行以下命令。

```powershell
$results = Join-Path $env:TEMP ('moonmat-demo-' + [guid]::NewGuid().ToString('N'))
powershell -NoProfile -ExecutionPolicy Bypass -File .\examples\workflows\demo.ps1 -OutputDirectory $results
```

每次新建结果目录，不覆盖文件。脚本实际执行命令，验证正常结果、差异坐标和预期错误，最后保存 `demo-receipt.json` 及结果哈希。只有 EXE 和 Windows PowerShell 即可运行。

1. 混合实验归档检查 13 个根变量，将 cell、struct、char、legacy object、精确 uint64、复数和 CSC 一起压缩再写回。通过 `snapshot-tree`、`restore-tree` 完成整树归档，再用 `diff-tree` 确认精确相等。
2. 稀疏仿真交换在同一个 MAT 中保存 1,000,000×1,000、3 个存储条目的 CSC、配置 struct 和中文标签。演示选择矩阵、快照、恢复和精确比较。显式展开超限时无输出。
3. NumPy 互通依次执行 NPY → MAT → 整形、轴置换、切片、按轴取样 → NPY。对相同结果返回 0，对 `[0,0]` 的一次改变返回 2，遗漏变量返回 1。使用 `atol=0.25`、`rtol=0`、`equal_nan=true` 进行容差比较时，这次改变返回 0。

输入由 `examples/python/workflow_inputs.py` 用 NumPy/SciPy 独立生成；固定 NaN 原始位、负零、CSC 行索引和列指针。`manifest.json` 给出输入哈希。混合归档输入见相邻的 `examples/mixed`。

`all-base-classes.mat` 另将全部 15 个公开基本类集中到一个文件，包含各数值类型的多维、空多维和交叉嵌套。演示检查类集合并写回，独立验证递归核对其数据。

开发者运行 `npm run verify`，其中 `scripts/scientific-workflows.py` 在 native 和 JS 上执行这三个流程，并由 NumPy/SciPy 逐项核对原始字节、维度、字段、CSC 容量和指针。此独立核对需要 Python 开发依赖，便携演示运行不需要。

源码目录中的完整说明见 [科研流程复现](../../docs/SCIENTIFIC_WORKFLOWS.md)。
