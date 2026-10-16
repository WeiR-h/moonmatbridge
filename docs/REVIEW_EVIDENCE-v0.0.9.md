# MoonMatBridge v0.0.9 技术补充与验收索引

仓库：[WeiR-h/moonmatbridge](https://github.com/WeiR-h/moonmatbridge)。公开包：[`WeiR-h/moonmatbridge@0.0.9`](https://mooncakes.io/docs/WeiR-h/moonmatbridge@0.0.9)。[发行页与下载](https://github.com/WeiR-h/moonmatbridge/releases/tag/v0.0.9)。本文件是依据代码与运行证据整理的技术附件，不替代参赛者本人提交的一页项目说明或正式报名回执。

## 对初审意见的回应

v0.0.2 旧申报书将 cell、struct、char、sparse 排除在范围外，该边界已被纠正。项目承诺的最终终点为 **MAT Level 5 全部公开基本类 1—15 均能读取、构造与写回**，包括 cell、struct、legacy object、char、CSC 及全部数值类，支持受资源限制的递归混合、大小端和压缩。以 [最终范围及完成条件](COMPATIBILITY.md) 为准，不通过后续性能版缩小终点。

这些基本类当前已有实现及独立混合文件证据；完整标准变体终点仍有未关闭项，因此公开版本保持 0.x，未发布 v1.0.0。MATLAB 私有运行时对象和 v7.3/HDF5 属于另一个格式/运行时范围，不混同公开基本类。

## 代码、证据与运行入口

| 要核对的内容 | 证据及复现入口 |
| --- | --- |
| MoonBit 为主要实现语言 | `src` 下的标签解析、数值与递归树、CSC、zlib、NPY、变换、快照和 diff；宿主只做文件/进程接口 |
| 公开基本类 1—15 | `scripts/compatibility.py`，大小端×压缩×global 开关×native/JS 的 16 组混合往返；报告 `compatibility-v0.0.9.json` |
| 可下载混合类型文件 | `examples/mixed` 的 3 份 MAT，包含 13 个根变量和交叉嵌套；另附 `examples/workflows/all-base-classes.mat`，同一文件覆盖全部公开基本类 1—15；均有生成器与 SHA-256 |
| 字符、IEEE 原始位、uint64、CSC 容量、异常输入 | `scripts/interop.py`、MoonBit 核心测试及版本/互操作报告 |
| 真实工具双向运行 | `examples/octave` 与 `scripts/octave-interop.py`；GNU Octave 生产 v6/v7，native/JS 未压缩/压缩写回，Octave 递归核对，共 8 组；日志和哈希在 `octave-v0.0.9.json` |
| 按需读取的可靠性 | `read_selected` / `inspect_roots` / `roots`；未选数据仍校验，独立 SciPy 与损坏输入回执在 `selection-v0.0.9.json` |
| 科研实际可用性 | [三个完整流程](SCIENTIFIC_WORKFLOWS.md)，便携包一键演示；独立工具在两宿主运行 6 组，`workflows-v0.0.9.json` |
| 可复现性能 | 固定 v0.0.5 提交、同机同工具链、全部原始样本、p95、吞吐与独立进程峰值；[方法与结果](PERFORMANCE.md)及 `performance-*.json` |
| 公开安装与交付 | `registry-v0.0.9.json`、`mooncakes-v0.0.9.json`、`release-v0.0.9.json`，以及发布后的公开下载与流程复验回执 |
| 开源合规 | Apache-2.0 `LICENSE`、`NOTICE`、`THIRD_PARTY.md` 及独立参考来源 |

报告状态必须实际通过才算该项完成；生成工具或文档本身不算成功证据。版本、源码指纹、工具链及文件哈希分别记录，历史失败保留在开发记录中。当前 v0.0.9 仅冻结交付，不扩大公开 API。

## 独特工作与性能边界

本项目将 MAT 混合容器、密集/CSC、精确数值位、有界原生压缩和 NumPy 科研互通放在同一 MoonBit 实现中。v0.0.7 根据预检尺寸直接写入私有固定缓冲；v0.0.8 在保留完整验证的同时省去未选数据对象；v0.0.9 提供完整复现链。不是仅把扩展名或版本号作修改。已有 NPY 库与本项目存在功能交集，不宣称全网唯一或不存在其他实现。

30%/25% 的写入目标和 2 倍/40% 的选择读取目标是本项目自定标准，分别按宿主报告，未达项也保留。它们不属于官方评分权重，也不代表通过主办方验收。

## 尚未关闭的兼容项与 v1.0 门槛

- UTF16/non-BMP 的生产者维度差异仍需真实文件回执；legacy object 现有 SciPy 数据级验证不代表 MATLAB 类运行时恢复。
- 非规范 CSC 的乱序/重复行索引及非 UTF-8 旧名称仍拒绝，不把拒绝合法标准变体计为兼容完成。
- Octave 8.4 的短字符矩阵长度与 sparse logical 类标记变体单独保留，逐项记录 SciPy、Octave 自加载及 MoonBit 实际结果，不计入成功矩阵。
- 只有全部公开范围及合法变体完成、三目标与独立工具消费通过后，才发布 v1.0.0。未达时保持 0.x 并公开缺口。

## 报名与验收状态

本文件对应[十月赛官网](https://moonbitlang.github.io/Hackathon2026/)要求的主要语言、公开记录、可运行示例、必要测试和许可证。官网于 2026-10-17 核对，报名与验收截止为 2026-10-31。初审补正仍需在原表修改并保留正式回执；包发布、自动测试和本附件均不证明已重新提交或复审通过。
