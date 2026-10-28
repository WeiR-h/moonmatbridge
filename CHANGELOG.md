# Changelog

## v0.0.15

- Preserve CSC row order, duplicate slots, capacity and raw numerical planes.
- Separate structural validation from is_canonical checks.
- Densification sums duplicate float/complex values in storage order and ORs logical values.
- Independent SciPy checks cover both original compatibility fixtures.


## v0.0.14

- Buffered DEFLATE bits and 9-bit Huffman lookup with a reliable long-code path.
- Bounded compressed input windows, MAT-sized owned buffers and chunked Adler-32.
- Fixed-revision paired benchmarks with raw timing batches and process memory samples.
- Regression coverage for final prefixes, long codes, input windows and unselected compressed roots.


## v0.0.13 — 2026-10-28

- 新增完整混合树快照与恢复，保留字符编码、字段顺序、legacy 类名和精确原始载荷。
- 新增 snapshot-tree、restore-tree 命令以及 JS 和库接口，原有快照格式保持兼容。
- 编解码累计检查字节、元素、字段、节点和深度；独立工具核对恢复结果，错误输入不产生输出文件。

## v0.0.12 — 2026-10-28

- 新增完整混合树精确比较、结构化零基路径和全局样本额度。
- 提供 diff-tree 命令、compare_mat_trees JS 导出及独立双宿主文件验证。
- 根变量和 struct 字段按名称匹配，单列根顺序并检测字段顺序、字符单位及 CSC 容量变化。
- 发行采用可恢复草稿上传和逐附件 SHA-256 核对，公开后保持附件不可变。

## v0.0.11 — 2026-10-28

- 冻结验收运行时与 API，提供简明验收索引、公开安装及三个科研场景复验。
- 为四类发行 ZIP 核对 LICENSE、NOTICE、THIRD_PARTY.md 的原始字节，补齐流程附件许可材料。
- 增加验证前后完整文件指纹和变化检查，避免生成器或工具链静默改变被验证源码。
- 固定 CI 官方编译器，与本地验收工具链保持一致，避免自动生成接口随浮动版本改变。
- 初审通过与最终验收分别记录；混合树 diff、快照和性能增强留在验收材料提交后推进。


## v0.0.10 — 2026-10-28

- 固化 Unicode、CSC、旧名称和 legacy object 的最小兼容案例，未完成项不计为兼容通过。
- 根目录、完整及空选择读取共享预算回归，保持严格校验。
- 交付记录按实际报告发现版本与检查分组；性能继承核对完整生产文件集合，防止新增文件漏检。
- 更新 README 测试数量和真实 Octave 验证说明；初审通过按用户通知记录。

## v0.0.9 — 2026-10-17

- 冻结 API，交付混合归档、百万行 CSC 与配置交换、NPY→MAT→变换→NPY 和精确 diff 三个完整科研流程。
- 提供固定输入及独立生成器、Windows 便携演示、正常/变化/错误退出码与输出哈希；两宿主由 NumPy/SciPy 独立核对。
- 将 global 标记纳入全部 15 个基本类的大小端/压缩矩阵；元数据和选择结果继续核对全局标记。
- 公开下载的原生程序与预编译 JS 重新运行 6 组流程；打包验证在仅系统 PATH 下运行完整便携演示。
- 汇总固定基线性能与本轮交付证据，补充复审技术附件；完整标准变体终点未全通过，保持 0.x。

## v0.0.8 — 2026-10-17

- 新增完整校验的 `read_selected` / `inspect_roots` / `MatRootInfo`，未选变量不构造数据树；保持选择顺序、空选择和错误行为。
- `select` 原生命令及 JS ABI 改用严格选择读取，新增 `roots` 元数据命令；旧 `info` 输出结构保持兼容。
- 数值转换、CSC 指针/索引、递归预算、字符编码和压缩校验仍执行；UTF8 采用无解码字符串分配的 scalar 扫描，并与标准解码器差分验证。
- 增加未选负载损坏、未知类型、NUL 名称、全局配额、压缩校验和错误原子性验证；独立 SciPy 核对大小端、压缩和混合类型选择。
- 本版不是流式磁盘 I/O；压缩选择仍需解码与完整校验。性能目标与实际结果逐项记录。

## v0.0.7 — 2026-10-17

- 统一密集、CSC、递归混合树的底层写入，按完整预检尺寸分配固定缓冲并直接写入子节点。
- 字节负载采用块复制；缓冲仅在内部持有，结束后转移为不可变输出，避免最后一次整文件复制及可变别名。
- 压缩输入直接构造单个根矩阵，收集有界压缩块后一次写出；保持校验、额度和确定性编码。
- 继续执行三目标、独立 SciPy/NumPy、真实 Octave 和公开消费者验证；性能目标以本版报告逐项判断。

## v0.0.6 — 2026-10-17

- 增加全部 15 个公开基本类的独立混合文件矩阵，覆盖大小端、压缩、多维/空数组和交叉嵌套。
- 接入真实 GNU Octave v6/v7 生产、MoonBit 原生/JS 往返和 Octave 递归消费验证；运行日志与哈希单独记录。
- 修复 Octave 使用空格填充未使用 subsystem 字段时被误拒绝的问题；实际 subsystem 偏移仍明确拒绝。
- 接受 Octave 的 nonsparse 保留字 1，并将 struct 字段宽度写为跨工具一致的小数据标签，修复 Octave 消费输出时的字段表错误。
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
