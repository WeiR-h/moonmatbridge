# MoonMatBridge v0.0.13

新增完整递归混合树无损快照和恢复。cell、struct、legacy object、char、数值与 CSC 共同保留在 `moonmatbridge/tree-snapshot/1` 中，包括字段顺序、字符原始单位、NaN 位模式、负零、精确整数、复数和稀疏容量。

新增 `snapshot-tree`、`restore-tree`，以及对应库接口和 JS 导出。原有数值快照与 diff 保持兼容。编解码累计检查资源额度，恢复后由混合树精确比较及独立 SciPy/NumPy 共同核对。

使用与格式见 docs/TREE_SNAPSHOT.md，实际执行结果见 verification/reports。
