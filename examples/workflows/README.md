# 三个可直接复现的科研流程

Windows 便携包解压后，在包的根目录运行：

```powershell
powershell -ExecutionPolicy Bypass -File examples/workflows/demo.ps1
```

每次新建结果目录，不覆盖文件。脚本实际执行命令，验证正常结果、差异坐标和预期错误，最后保存 `demo-receipt.json` 及结果哈希。只有 EXE 和 Windows PowerShell 即可运行。

1. 混合实验归档：检查 13 个根变量，将 cell、struct、char、legacy object、精确 uint64、复数和 CSC 一起压缩再写回。
2. 稀疏仿真交换：同一个 MAT 中放置 1,000,000×1,000、3 个存储条目的 CSC、配置 struct 和中文标签。选择矩阵、快照、恢复、精确比较；显式展开超限时无输出。
3. NumPy 互通：NPY → MAT → 整形、轴置换、切片、按轴取样 → NPY。对相同结果返回 0，对 `[0,0]` 的一次改变返回 2，遗漏变量返回 1。

输入由 `examples/python/workflow_inputs.py` 用 NumPy/SciPy 独立生成；固定 NaN 原始位、负零、CSC 行索引和列指针。`manifest.json` 给出输入哈希。混合归档输入见相邻的 `examples/mixed`。

`all-base-classes.mat` 另将全部 15 个公开基本类集中到一个文件，包含各数值类型的多维、空多维和交叉嵌套。演示检查类集合并写回，独立验证递归核对其数据。

开发者运行 `npm run verify`，其中 `scripts/scientific-workflows.py` 在 native 和 JS 上执行这三个流程，并由 NumPy/SciPy 逐项核对原始字节、维度、字段、CSC 容量和指针。此独立核对需要 Python 开发依赖，便携演示运行不需要。

完整混合树的快照和 diff 尚未实现，归档流程由独立 SciPy 深比较验收；快照/diff 的演示使用数值或 CSC 文件。这里的案例是可复现示例，不代表外部采用或主办方验收通过。
