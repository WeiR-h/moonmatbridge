# Changelog

## v0.0.6 — 2026-10-17

- 增加全部 15 个公开基本类的独立混合文件矩阵，覆盖大小端、压缩、多维/空数组和交叉嵌套。
- 接入真实 GNU Octave v6/v7 生产、MoonBit 原生/JS 往返和 Octave 递归消费验证；运行日志与哈希单独记录。
- 修复 Octave 使用空格填充未使用 subsystem 字段时被误拒绝的问题；实际 subsystem 偏移仍明确拒绝。
- 增加固定输入、原生/JS 核心计时和独立进程峰值内存基准，固定 v0.0.5 对照提交；性能目标由后续实测逐项判断。
- 开发验证默认串行编译/测试，减少内存压力；原有接口与数值科研工作流继续保留。

## v0.0.5 — 2026-10-16

- 新增递归 `MatNode` / `read_tree` / `write_tree`：cell、struct 数组、char 与 legacy object，保留字段顺序、嵌套关系、全局标记及匿名子矩阵。
- 字符支持 miINT8/UINT8/UINT16/UTF8/UTF16/UTF32，原始多字节单位规范化为小端；UTF8 校验 Unicode scalar 数，UTF32 拒绝非法 scalar。
- `info` / `roundtrip` / `compress` / `select` 及对应 JS 接口可处理完整混合树；旧数值/CSC 互操作接口保持原输入域，避免隐式丢失容器。
- 提供 13 根变量的大小端/压缩混合案例、独立 SciPy 生成器和递归比较；增加深度、节点、字段数与累计元素预算及畸形输入用例。
- 明确公开 Level 5 基本类 1–15 的最终读写范围与 v1.0 验收条件，纠正 v0.0.2 申报范围；实际 MATLAB/Octave 回执仍未完成。

## v0.0.4 — 2026-10-13

- 将本地模块名 `local/moonmatbridge` 迁移为可发布的 `WeiR-h/moonmatbridge`，同步导入路径、公开接口、安装文档与仓库元数据。
- 增加 `.moonignore` 的明确发布文件范围，排除开发工具、构建结果、报名清单与本地验证目录；发布前核对实际归档文件。
- 增加独立 Mooncakes 消费者：固定版本安装、禁止本地覆盖、逐文件核对源码，并在 JS/wasm-gc/native 验证密集/复数/uint64、稀疏、压缩、快照、原始字节操作与精确差异。
- 保留 v0.0.3 的全部核心行为和历史标签；本版是包发布适配，不新增格式支持范围。

## v0.0.3 — 2026-10-10

- 第一轮：新增保留原始字节的跨维度切片、按轴取样与数组拼接；严格 JSON 转换流程支持组合 reshape/permute，并保留混合文件中的稀疏变量。
- 第二轮：MoonBit 原生确定性 LZ77/固定 Huffman zlib 编码与 stored 回退；新增压缩 MAT 写入与 `compress`，独立解码验证 44 个输出流。
- 第三轮：新增二维 double/logical/complex double CSC 稀疏 MAT 读写、混合文档 API、容量保留与显式 `sparsify` / `densify`；大型稀疏形状不默认展开。
- 第四轮：新增密集/CSC 无损快照与 `snapshot` / `restore`，保存 NaN 编码、负零、精确整数、复数分量、全局标记及稀疏存储元数据。
- 第五轮：新增按变量名匹配的精确差异检查、变化坐标、实/虚部计数和全局样本上限；`diff` 为 CI 提供 0 相同 / 2 变化 / 1 错误的退出码。
- 验证覆盖 52 项三目标测试、54 组 SciPy/NumPy 科研互通、两宿主各 72 个 NPY 输入、704 个解压对照流和 2,072 个截断输入；发布前检查源码指纹及解压后的独立消费者。
- 保持旧密集/JSON API；混合文件使用 `read_document`。仍不支持 cell/struct/char、MAT v4/v7.3、流式处理、非标准 CSC 与浮点容差比较。

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
