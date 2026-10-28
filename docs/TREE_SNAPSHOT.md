# 完整混合树快照

`to_tree_snapshot(variables, limits?, tree_limits?)` 和 `from_tree_snapshot(text, limits?, tree_limits?)` 使用独立的 `moonmatbridge/tree-snapshot/1` 格式。原有数值/CSC 快照继续使用原格式。

```text
moonmat snapshot-tree INPUT.mat OUTPUT.json
moonmat restore-tree OUTPUT.json RESTORED.mat
moonmat diff-tree INPUT.mat RESTORED.mat REPORT.json
```

保留根和子节点名称、形状、全局标记、字段顺序、legacy 类名、字符编码与原始单位，以及数值位模式、复数分量、CSC 行索引、列指针和容量。原始载荷用小写十六进制字节表示，避免浮点文本转换丢失 NaN、负零或精确整数。

节点共有 `storage`、`name`、`shape` 和 `global` 字段。数值和 CSC 保存 `dtype`、`real_hex`、`imag_hex`；字符保存 `encoding`、`data_hex`；cell 保存 `values`；struct/object 保存 `fields`、`class_name`、`values`。结构子值为列优先元素顺序，每个元素内按字段顺序排列。CSC 另存 `row_indices`、`col_ptrs`、`nzmax`。

编码先验证完整树并预检 JSON 字节额度。解码检查输入字节与 JSON 深度，累计约束原始数据和名称字节、元素、节点及字段数量；`max_fields` 在本格式中为整棵树累计字段额度。还会拒绝未知字段、无效十六进制、重复名称和无效字符单位。失败时不会创建 MAT 输出文件。

恢复保留数据及存储元数据；MAT 文件使用规范化小端编码，头部说明和原压缩布局不属于快照内容。JS 导出为 `mat_to_tree_snapshot(bytes)` 和 `tree_snapshot_to_mat(text)`。
