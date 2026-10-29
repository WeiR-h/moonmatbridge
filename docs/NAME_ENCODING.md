# MAT 名称编码

变量名、结构字段名及 legacy 类名使用同一个显式 `NameEncoding`。默认 `Utf8` 严格验证 UTF-8；`Latin1` 将每个 8 位字节映射到同值 Unicode 字符，不检测或猜测原始语言编码。字符数组的存储编码仍由 `CharEncoding` 控制。

```moonbit
let tree = @mat.read_tree(bytes, name_encoding=@mat.NameEncoding::Latin1)
let restored = @mat.write_tree(tree.variables, name_encoding=@mat.NameEncoding::Latin1)
```

`read_mat`、`read_document`、`read_tree`、`read_selected`、`inspect_roots` 及三个 `_from` 接口均接受可选 `name_encoding`；三个 MAT 写入接口与 `validate_document`、`validate_tree` 接受相同参数。名称长度按指定编码的字节计算，NUL、重复名称、重复字段及无法用 Latin1 表示的字符明确失败。

```powershell
.\moonmat.exe --name-encoding=latin1 roots old.mat
.\moonmat.exe --name-encoding=latin1 select old.mat selected.mat café
.\moonmat.exe --name-encoding=latin1 snapshot-tree old.mat archive.json
.\moonmat.exe --name-encoding=latin1 restore-tree archive.json restored.mat
node scripts/cli.mjs --name-encoding=latin1 info old.mat
```

前置参数同时控制该命令的 MAT 读取与写出。JSON 与快照继续使用 Unicode 名称；不自动记录原 MAT 名称编码。需要恢复旧字节时显式使用同一写出策略；省略参数则规范化为 UTF-8。已有命令参数位置、报告格式和退出码保持兼容。

JS 保留已有导出，新增对应的 `*_with_options` 版本，末尾参数为 `{"name_encoding":"latin1"}` JSON 字符串。`compare_mat_trees_close_with_options` 的名称选项位于原有容差选项之后。名称选项只接受 `name_encoding`，拒绝未知键和无效值。

`python scripts/name-checks.py` 保存两种宿主、压缩/未压缩、快照、选择顺序和失败原子性的独立回执。SciPy 可直接产生 Latin1 根名称，但其结构字段读取要求 UTF-8；测试因此单独检查原始 Latin1 元数据，并使用等长 ASCII 元数据投影核对数值，不将投影结果描述为 SciPy 直接消费原文件。
