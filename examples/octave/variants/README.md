# 未关闭的真实工具变体

这里永久保留 GNU Octave 8.4.0 在 v6/v7 模式实际生产的四份小文件，避免仅依赖有保存期限的 CI 附件。来源、提交、SHA-256、各工具结果见 `evidence.json`；这是一份历史回执，不是当前版本的新测试结果。各版会由 `scripts/octave-interop.py` 重新生产并记录实际行为。

- `producer-small_char_matrix-*`：声明的矩阵字节长度比实际多 4。本库拒绝，SciPy 可读入孤立的单变量文件，Octave 也可自加载。
- `producer-sparse_logical-*`：dense class/logical 标记与 CSC 负载存在工具间解释差异。Octave 可自加载，SciPy 和本库拒绝。

这些案例在报告中标为 `unresolved_producer_variant`，不计入成功矩阵。不能用当前拒绝结果证明完整兼容，也不能称所有独立工具都无法读取。规范字符与 logical CSC 的成功证据在独立基本类矩阵和互操作报告中另列。
