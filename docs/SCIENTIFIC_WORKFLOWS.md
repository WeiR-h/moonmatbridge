# 科研流程复现

三个科研流程都提供输入、命令、预期结果和独立核对方法。Windows 便携演示使用包内程序和样例。独立核对使用 Python、NumPy 和 SciPy。

## 从公开发行包运行

从 [v0.1.11 发行页](https://github.com/WeiR-h/moonmatbridge/releases/tag/v0.1.11) 下载 `MoonMatBridge-v0.1.11-windows-x64.zip`，解压到路径较短的目录，然后在含 `moonmat.exe` 的目录执行以下命令。

```powershell
$results = Join-Path $env:TEMP ('moonmat-demo-' + [guid]::NewGuid().ToString('N'))
powershell -NoProfile -ExecutionPolicy Bypass -File .\examples\workflows\demo.ps1 -OutputDirectory $results
```

终端末行显示新建的结果目录。目录中的 `demo-receipt.json` 记录预期及实际退出码、返回值、程序哈希和结果哈希。Windows 上解压位置层级较深时，默认生成的结果路径可能过长。以上命令显式将结果写到临时目录。[公开便携演示回执](../verification/reports/workflows-demo-public-v0.1.11.json)

发行页另附 `MoonMatBridge-v0.1.11-workflows.zip`，包含 native/JS 的实际输出、原始输入、独立核对报告及逐文件哈希。可在该包中运行同一个脚本，加上 `-Executable` 和同版 Windows 包中 `moonmat.exe` 的绝对路径。

## 场景一：混合实验归档

输入 `examples/mixed/research-mixed.mat` 有 13 个根变量，组合实验记录 struct、分组 cell、中文和非 BMP char、legacy 类名与字段、精确 uint64、复数、logical、CSC、空数组与多维数组。执行根目录检查、压缩和写回。

另附 `examples/workflows/all-base-classes.mat`，将全部 15 个公开基本类、数值多维/空多维和交叉嵌套集中到一个可下载文件中。根目录检查确认类集合 1—15，再由两宿主写回并接受独立核对；原件同时作为发行页单独附件提供。

使用 `snapshot-tree`、`restore-tree` 完成完整混合树归档与恢复，再用 `diff-tree` 确认数据与存储元数据一致，预期退出码为 0。SciPy 独立读取原件和 MAT 往返结果，递归核对字段顺序、形状、字符、数值类型和原始数值字节。

## 场景二：大型稀疏仿真交换

输入 `examples/workflows/sparse-system.mat` 将 1,000,000×1,000、3 个存储条目的 CSC 与求解器配置 struct、中文标签放在同一个文件。保存显式负零；选择矩阵后执行快照、恢复和精确 diff。

验收检查 SciPy 所读行索引、列指针、数据字节、3 个容量槽位及大形状。显式 `densify` 因默认元素额度返回 `element-limit`，退出 1 且不留下输出。不能把这次拒绝当作处理十亿个密集元素的性能成绩。正式内存基准使用 100,000 个活动条目的独立固定场景，见 [性能方法](PERFORMANCE.md)。

## 场景三：NumPy 转换与差异门禁

输入是 4×6×2、列优先 float64 NPY，原始位包含 `0x7ff8000000000042` NaN 和负零。转换为 MAT 后按固定 JSON 计划整形为 8×6、置换轴、切片，再按轴取样；结果导出为 3×4 NPY。

NumPy 独立计算预期结果，用原始字节核对类型、维度和数据。相同结果比较退出 0。预制参考文件将 `[0,0]` 增加 0.25，精确比较退出 2，报告定位该坐标。`diff-tree-close` 使用 `atol=0.25`、`rtol=0` 和 `equal_nan=true` 时退出 0，报告记录 `within_tolerance: true`、`exact_equal: false`。遗漏变量导出退出 1，目标文件保持不存在。

## 开发者的独立验证

按 [版本交付说明](RELEASING.md) 配置工具链及 `requirements-dev.txt` 中的依赖，再运行 `npm run verify`。

- `examples/python/workflow_inputs.py` 独立生成固定输入，验证器检查其与公开样例逐字节一致。
- `scripts/scientific-workflows.py` 在 native、JS 分别执行三个场景。报告记录实际执行次数、断言和输出哈希。[v0.1.11 源码验证](../verification/reports/workflows-v0.1.11.json)
- 全部基本类、全局标记、字符存储、CSC 容量、损坏输入和三目标测试由其他分组继续执行，不被演示替代。
- 公开复验使用下载的 EXE、预编译 JS 和样例，独立核对结果及输出哈希。[v0.1.11 公开复验](../verification/reports/workflows-public-v0.1.11.json)
