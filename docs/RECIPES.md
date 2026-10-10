# 可复现的科研数据工作流

以下命令在 Windows 下载包目录执行，所有输出文件必须是新文件。核心和原生程序无需 Python、MATLAB 或 Node。独立 SciPy/NumPy 验证只需要在源码验证环境中安装。

## 实验数据整理、压缩与精确存档

```powershell
.\moonmat.exe sample run.mat
.\moonmat.exe info run.mat
.\moonmat.exe transform run.mat examples\transform-plan.json transformed.mat
.\moonmat.exe compress transformed.mat compressed.mat
.\moonmat.exe snapshot compressed.mat archive.json
.\moonmat.exe restore archive.json restored.mat
.\moonmat.exe diff compressed.mat restored.mat equality-report.json
```

输入含温度矩阵、复数频谱、有效标记与大于 2^53 的 uint64 编号。计划对温度取隔列窗口并转置，对编号按指定顺序重复取样，再拼接频谱。输出保留原始数值字节；快照恢复后的比较返回 0。压缩形式和 MAT 头部描述不参与内容比较。

## 混合密集/稀疏科研矩阵交换

```powershell
.\moonmat.exe sparsify run.mat temperature sparse.mat
.\moonmat.exe info sparse.mat
.\moonmat.exe select sparse.mat subset.mat temperature sample_id
.\moonmat.exe compress subset.mat sparse-compressed.mat
.\moonmat.exe densify sparse.mat temperature expanded.mat
.\moonmat.exe diff run.mat expanded.mat
```

`info` 明确显示 `storage=csc`、使用条目、存储槽位、nzmax 和完整形状。`sparsify` 只转换指定变量，其他变量不变；负零和 NaN 会保留为显式条目。`densify` 先检查完整形状和字节预算，不能保证所有稀疏文件都能展开。NPY 导出稀疏变量必须先显式展开。

源码验证会独立生成 1,000,000 × 1,000、仅一个使用条目的 CSC，完成压缩读写、快照和差异检查，并确认展开被额度拒绝。此例说明存储处理能力，不代表真实用户或特定科研设备的验证。

## 科研回归与数据变化定位

```powershell
.\moonmat.exe diff baseline.mat candidate.mat changes.json
```

退出码为 0 表示按变量名匹配后的类型、形状、原始位、标记及 CSC 存储元数据相同；2 表示有效比较发现变化；1 表示格式、参数或 I/O 错误。JSON 报告分别列出元数据变化、实/虚部变化数量及少量坐标样本。变量顺序变化单独报告。相同的数值但不同 NaN 编码或正负零仍报告变化；此检查没有浮点容差。

密集样本的坐标为零基、列优先；CSC 样本索引是存储槽位，使用条目有行/列坐标，未使用槽位坐标为空。形状、dtype 或稀疏索引映射变化时，只报告对应元数据变化，不虚构逐元素对应。

完整独立验证：`npm run verify`。复现报告位于 `verification/reports/interop-v0.0.3.json` 和 `js-v0.0.3.json`，同时保留源码指纹、运行版本、验证分组及具体环境。
