# MoonMatBridge v0.0.19

新增完整混合树浮点容差比较 compare_trees_close，以及 diff-tree-close 命令和 JS 导出。采用对称绝对/相对阈值，复数实虚部分别判断；整数、字符和结构、CSC 存储元数据继续精确比较。

独立 tree-close/1 报告同时记录原始位相同与容差内相同，保留结构化路径、全局样本限额与完整比较。正负零、无穷、NaN、极大值及次正规值的行为有明确规则和独立案例。

用法：moonmat diff-tree-close LEFT.mat RIGHT.mat REPORT.json [OPTIONS.json]。阈值文件示例与报告说明见 TREE_CLOSE.md；退出码为相同 0、变化 2、错误 1。旧精确比较保持兼容。

三个 MoonBit 目标与 SciPy/NumPy、真实 Octave 流程持续验证。原生和 Node 命令行由独立 Decimal 标量计算及混合科研文件核对，公开发行包再次复现。
