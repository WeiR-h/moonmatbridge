# 递归混合数据的精确比较

`compare_trees(left, right, max_samples?, limits?, tree_limits?)` 比较完整 MatTree。cell、struct、legacy object、char、数值和 CSC 均参与比较；名称、形状、全局标记、类型、字段顺序、字符编码及原始存储载荷都会检查。

根变量按名称匹配，根顺序单列在 `variable_order_changed`，顺序独自变化不影响 `content_equal`。struct 同名字段匹配后递归比较，字段顺序变化也是存储元数据变化。

```text
moonmat diff-tree LEFT.mat RIGHT.mat REPORT.json
```

返回码：相同为 0，变化为 2，输入或输出错误为 1。报告使用 `moonmatbridge/tree-diff/1`。已有数值 `diff` 命令和报告格式保持兼容。

路径是对象数组，例如根 `root` 下结构元素 0 的字段 `a.b[0]` 中 cell 元素 0：

```json
[{"kind":"root","name":"root"},{"kind":"struct_element","index":0},{"kind":"field","name":"a.b[0]"},{"kind":"cell","index":0}]
```

路径索引、数值坐标均为零基，数组使用列优先坐标。CSC 和字符的 `index` 指原始存储槽位或编码单位；`coordinates` 为空，不将 UTF8 字节位置误称为字符坐标。原始字节用十六进制记录。

样本额度在整个报告共享，默认 16，范围 0—256。样本满后继续比较，`differences` 统计变化事件，`truncated` 标记样本未覆盖所有事件。类型或载荷长度不一致等元数据事件按一次计数。两侧数据都执行完整资源检查，样本额度为零也不会跳过验证。MAT 头部描述、压缩方式和源大小端不参与内容比较。

JS 导出：`compare_mat_trees(leftBytes, rightBytes, maxSamples)`，返回报告 JSON 字符串。
