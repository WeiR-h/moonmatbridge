# Changelog

## v0.0.2 — 2026-10-07

- 新增 MoonBit 原生 NPY 1/2/3 读取与 `from-npy` 命令，支持大小端、C/Fortran、复数和精确整数；拒绝 object/pickle 和截断输入。
- 新增无损 reshape、任意轴置换与核心/CLI 变量子集提取。
- 修复公开数组的标量访问校验，以及 Windows 子进程 PATH 中丢失 Node 的问题。
- 验证与打包使用当前版本，保留 v0.0.1 标签、下载和历史报告；提供完整 Linux SciPy/NumPy 验证工作流。
- 36 项测试分别在 JS/wasm-gc/native 通过；35 项独立科研互通验证分组，包括两宿主各 72 个 NPY 导入文件。

## v0.0.1 — 2026-10-07

首个可运行版本：MoonBit 实现 MAT Level 5 dense numeric/logical 读写、大小端及小数据标签读取、zlib/DEFLATE 解压、复数与 N 维形状保留、精确 64 位整数、结构化错误和资源限制。

提供严格 JSON 互通格式、NPY 导出、Windows x64 原生命令行、JS 适配器、跨目标示例和独立 SciPy/NumPy 验证。

已公开发布至 GitHub；尚未发布至 Mooncakes，尚未提交黑客松。暂无 MATLAB/Octave 运行验证。cell/struct/char/sparse、MAT v7.3、压缩写入和 NPY 读取待后续版本。
