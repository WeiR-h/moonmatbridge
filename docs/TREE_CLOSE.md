# 混合树浮点容差比较

`compare_trees_close(left, right, atol?=0, rtol?=0, equal_nan?=false, max_samples?=16, limits?, tree_limits?)` 接收完整混合树，递归比较 cell、struct、legacy object、字符、数值及 CSC。

浮点使用对称规则 `abs(a-b) <= atol + rtol * max(abs(a),abs(b))`；复数的实部和虚部分别判断。阈值必须有限且非负。实现对相反符号的极大值缩放，再比较相对余量，避免形成溢出的差值或阈值。整数、logical、字符单位、类型、形状、字段顺序、global、CSC 索引及容量继续精确比较。

正负零相等；同号无穷相等；NaN 默认不相等，可用 equal_nan 显式视作相等。相同 NaN 原始位在默认模式下会得到 exact_equal=true、within_tolerance=false。

结果同时提供 exact_equal 与 within_tolerance；前者按原始位比较载荷，后者按容差规则判断浮点。根变量按名称匹配，根顺序变化单独记录 variable_order_changed，并计作精确元数据变化，样本使用空路径和 root_order 类型。结构字段按名称匹配，并将字段顺序变化计作精确元数据变化。既有精确比较的内容相等定义保持兼容。

differences 统计超出容差的载荷及元数据变化；samples 受全局 max_samples 限额约束，达到上限后仍完成比较并标明 truncated。容差内的位变化可由 exact_equal=false 识别，需要原始位差异路径时使用既有精确 diff-tree。路径为结构化数组，所有坐标零基，CSC 坐标表示存储槽位。

```text
moonmat diff-tree-close LEFT.mat RIGHT.mat REPORT.json [OPTIONS.json]
node scripts/cli.mjs diff-tree-close LEFT.mat RIGHT.mat REPORT.json [OPTIONS.json]
```

可选参数文件示例：

```json
{"atol":0.000001,"rtol":0.0001,"equal_nan":false,"max_samples":16}
```

省略参数文件时全部采用默认值；不识别的字段、非布尔 equal_nan、非整数样本限额以及无效阈值均报错。报告格式独立为 `moonmatbridge/tree-close/1`，包含 exact_equal、within_tolerance、阈值、结构化样本及截断标记。退出码：容差内相同 0，超差或元数据变化 2，输入错误 1。全部输入与选项校验成功后才创建新报告文件。

JS 导出 `compare_mat_trees_close(leftBytes, rightBytes, optionsJson)` 返回同一格式的 JSON 文本。原 compare_trees、diff-tree 和 tree-diff/1 格式保持兼容。

验证覆盖二进制精确阈值边界、对称性、极大值、次正规值、NaN、无穷、负零、单精度、复数、uint64、混合结构及报告截断。独立脚本用 SciPy 生产文件，使用 NumPy 原始存储和高精度 Decimal 核对标量结果，两个命令行宿主分别执行。
