# MoonMatBridge v0.0.12

新增完整递归混合树精确比较，覆盖 cell、struct、legacy object、char、数值和 CSC。结构化路径保留字段原名，所有索引为零基；差异样本全局有界，达到上限后继续统计变化。

新增 `compare_trees`、`diff-tree LEFT.mat RIGHT.mat REPORT.json` 和 JS `compare_mat_trees`。原有数值 diff 接口及退出码保持兼容。详见 docs/TREE_DIFF.md。

三目标回归、SciPy/NumPy 文件核对及真实 Octave 双向结果保存在 verification/reports。发行包附许可证、来源说明和校验值。
