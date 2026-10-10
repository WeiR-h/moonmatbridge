# MoonMatBridge v0.0.3 的核心价值与范围比较

核对日期：2026-10-10。项目的重点是科研 MAT 文件的可靠交换与可复现检查。NPY 是连接 NumPy 的接口；科研数组整形与格式保真服务于同一条交换流程。

## 已有交集与本项目重点

已阅读 [ShunjunGu/moon-npy](https://github.com/ShunjunGu/moon-npy) 当前 README，源码版本为 v0.4.0、Apache-2.0。它已提供 MoonBit 原生 NPY 读写、复数、未压缩 NPZ 读写、分块解码与 moonNum 适配。无 Python 运行时、NPY 大小端或复数本身不作为 MoonMatBridge 的独有能力。

| 能力 | MoonMatBridge v0.0.3 | moon-npy README 当前描述 |
| --- | --- | --- |
| NPY 数值互通 | 支持，是 MAT 科研流程的桥接接口 | 支持，是核心定位 |
| NPY/NPZ 广度 | NPY primitive/complex；无 NPZ | NPY 及未压缩 NPZ |
| MAT Level 5 混合密集/CSC | 支持，稀疏不自动展开 | 未列出 MAT 接口 |
| MAT 压缩写入与读取 | 原生确定性编码及有界解码 | 未列出 MAT 接口 |
| NaN 编码/负零/CSC 容量快照 | 原始字节 JSON，可恢复到 MAT | 未列出该快照格式 |
| 科研数据差异门禁 | 按名称、存储元数据和原始位比较，坐标报告及退出码 | 未列出该 MAT 工作流 |

此比较依据公开 README，没有运行对方项目；“未列出”不等于证明不存在。有限检索不能保证没有同类项目，也不能保证获奖。

## 可复现的三个具体价值

1. **大型稀疏科研矩阵交换。** 独立验证输入包含 1,000,000 × 1,000、仅一个使用条目的 CSC。读取、写回、压缩、快照和差异检查保持稀疏存储；显式展开时在分配前返回 `element-limit`。用途包括稀疏图、仿真系统矩阵等文件交换，尚未声称真实用户采用。
2. **浮点异常与整数身份保真。** 普通 JSON 保留数值语义但会归一化 NaN；无损快照直接存储 little-endian 十六进制字节，可保留 float32/64 NaN payload、负零、复数分量、uint64 最大值及全局标记。稀疏的活动条目和未使用存储槽位都保留。
3. **科研转换后的可追踪验收。** 转换计划支持切片、按轴取样、拼接、整形和维度置换，并保留其他稀疏变量。`diff` 区分内容变化和 MAT 编码变化；变化样本带零基坐标与原始字节。退出码 0/2/1 可用于 CI，报告说明不能按元素对应的元数据变化。

## 证据与边界

测试和科研文件生产/消费由独立 SciPy、NumPy、Node zlib 交叉验证，报告见 [verification/reports](../verification/reports/)。压缩比例只描述具体测试数据，不推广为所有数据都能达到的收益。MATLAB/Octave 未实际执行；不支持 cell/struct/char、MAT v4/v7.3、流式文件处理、非规范 CSC 或浮点容差比较。

核心为原创 MoonBit 实现，标准/工具来源与许可证见 [THIRD_PARTY.md](../THIRD_PARTY.md)。此说明描述当前源码与验证范围，不是主办方评审结果。
