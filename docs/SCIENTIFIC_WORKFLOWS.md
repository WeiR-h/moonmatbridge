# 科研流程的复现与验收

本轮提供三个从输入到独立核对的完整场景。输入、生成器、命令和结果报告均在仓库中；原生程序无需 Python 或 MATLAB 运行时。独立核对工具属于开发依赖。

## 从公开发行包运行

下载 [v0.0.9 Windows 便携包](https://github.com/WeiR-h/moonmatbridge/releases/tag/v0.0.9)，解压后执行：

```powershell
powershell -ExecutionPolicy Bypass -File examples/workflows/demo.ps1
```

脚本新建唯一目录，记录命令的预期/实际退出码、返回值、程序哈希和结果哈希。相同输入结果可由 `diff` 检查；输出路径始终要求新文件。实际执行回执位于结果目录 `demo-receipt.json`，便携包验证的日志由打包脚本保存。

发行页另附 `MoonMatBridge-v0.0.9-workflows.zip`，包含本版 native/JS 的实际输出、原始输入、独立核对报告及逐文件哈希。解压后可用 `examples/workflows/demo.ps1 -Executable 原生程序绝对路径` 在新目录复现。该证据包没有自带 EXE，使用同版 Windows 包中的程序。

## 场景一：混合实验归档

输入 `examples/mixed/research-mixed.mat` 有 13 个根变量，组合实验记录 struct、分组 cell、中文和非 BMP char、legacy 类名与字段、精确 uint64、复数、logical、CSC、空数组与多维数组。执行根目录检查、压缩和写回。

另附 `examples/workflows/all-base-classes.mat`，将全部 15 个公开基本类、数值多维/空多维和交叉嵌套集中到一个可下载文件中。根目录检查确认类集合 1—15，再由两宿主写回并接受独立核对；原件同时作为发行页单独附件提供。

SciPy 独立读入原件与两份输出，递归比较字段顺序、形状、字符、数值类型和小端原始数值字节。MAT 头部说明和压缩布局可以变化。完整混合树 diff/快照不属于本轮，归档验收采用独立深比较。

## 场景二：大型稀疏仿真交换

输入 `examples/workflows/sparse-system.mat` 将 1,000,000×1,000、3 个存储条目的 CSC 与求解器配置 struct、中文标签放在同一个文件。保存显式负零；选择矩阵后执行快照、恢复和精确 diff。

验收检查 SciPy 所读行索引、列指针、数据字节、3 个容量槽位及大形状。显式 `densify` 因默认元素额度返回 `element-limit`，退出 1 且不留下输出。不能把这次拒绝当作处理十亿个密集元素的性能成绩。正式内存基准使用 100,000 个活动条目的独立固定场景，见 [性能方法](PERFORMANCE.md)。

## 场景三：NumPy 转换与差异门禁

输入是 4×6×2、列优先 float64 NPY，原始位包含 `0x7ff8000000000042` NaN 和负零。转换为 MAT 后按固定 JSON 计划整形为 8×6、置换轴、切片，再按轴取样；结果导出为 3×4 NPY。

NumPy 独立计算预期结果，用原始字节核对类型、维度和数据。相同结果比较退出 0；预制参考文件只将 `[0,0]` 增加 0.25，比较退出 2，报告定位该坐标和一个差异；遗漏变量导出退出 1，不留下文件。

## 开发者的独立验证

安装 `requirements-dev.txt` 中的 NumPy/SciPy 后运行 `npm run verify`。其中：

- `examples/python/workflow_inputs.py` 独立生成固定输入，验证器检查其与公开样例逐字节一致。
- `scripts/scientific-workflows.py` 在 native、JS 分别执行三个场景，共 6 组。报告为 `verification/reports/workflows-v0.0.9.json`，附输出哈希。
- 全部基本类、全局标记、字符存储、CSC 容量、损坏输入和三目标测试由其他分组继续执行，不被演示替代。
- GitHub 发布后重新下载全部资产，并使用下载的 EXE、预编译 JS 和输入重跑这 6 组；回执单列为 `workflows-public-v0.0.9.json`。本地成功不自动记为公开复验成功。

这些是可复现科研流程，不代表已有真实用户采用、MATLAB 执行、主办方复审或获奖。
