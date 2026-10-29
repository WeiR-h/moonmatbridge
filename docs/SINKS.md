# 分块写出

`write_tree_to` 完整预检混合树，再将 MAT 标签、元数据和载荷按块送入 `MatSink`。输出与同版 `write_tree` 的未压缩结果逐字节一致。它覆盖数值、复数、CSC、字符、cell、struct 和 legacy object，保留名称编码、字段顺序、原始数值位、字符单位及 CSC 存储槽位。

```moonbit
pub(all) struct MatSink {
  write_from : (Int32, FixedArray[Byte], Int32, Int32) -> Int32
}

write_tree_to(variables, sink, limits?, tree_limits?, name_encoding?)
// -> Int32 raise MatError，成功时返回最终文件长度
```

回调依次接收输出偏移、借用缓冲、缓冲起点和请求长度，返回实际写入量。核心处理合法短写；零、负数或大于请求量均为 `io-error`。回调同步执行，不得修改或保留缓冲；写入期间输入树保持稳定。

## 独立写入额度

| `WriteLimits` 字段 | 默认值 |
| --- | --- |
| `max_output_bytes` | 1 GiB，包含文件头的最终文件长度 |
| `max_uncompressed_bytes` | 1 GiB，规范未压缩 MAT 总长度 |
| `max_metadata_bytes` | 8 MiB，累计维度、编码名称、类名和带填充的字段表 |
| `chunk_bytes` | 1 MiB，支持 1—8 MiB |
| `max_elements` | 134,217,728，累计容器位置和叶数据元素/CSC 槽位 |
| `max_variables / max_dimensions / max_name_bytes` | 4,096 / 32 / 1,024 |

深度、节点和字段额度使用原有 `TreeLimits`。原 `Limits` 和 `SourceLimits` 不变。首次回调前完成全部数据校验和结构预算检查；后部节点无效时也不会发生写入。

输入数据树仍驻留内存。编码工作缓冲按块复用，另有节点尺寸计划及有界名称编码临时数据；额度不等于进程峰值内存。核心 sink 发生 I/O 错误时可能留下部分内容，调用方负责目标的生命周期。

## 命令与文件原子性

native 和 Node 的 `roundtrip`、`select`、`restore-tree` 使用新写出路径，参数、JSON、退出码和原有 64 MiB 结果额度保持兼容。输入读取方式没有因此改变：`select` 使用分块文件源，`roundtrip` 和 `restore-tree` 仍使用内存输入。

两个宿主仅在完成校验、收到首次写回调时创建同目录临时文件。完整写入、尺寸核对和关闭检查通过后，以禁止覆盖的方式生成最终名称；失败时清理本次创建的临时文件。目标已存在时返回 `output-exists`。源选择在完整校验及源句柄关闭后才提交最终文件。

原内存接口和 JS `BinaryResult` 保持可用。JS 新增 `make_sink`、`roundtrip_mat_to`、`select_source_mat_to`、`tree_snapshot_to_sink` 及对应名称编码 `*_with_options`；这些写出函数返回状态 JSON，成功时包含最终字节数。

## 大型驻留树示例

安装项目内工具链并配置 C 编译器后运行：

```powershell
node scripts/moon.mjs run src/examples/write_large --target native -- large.mat
node scripts/cli.mjs roots large.mat
```

示例在内存中创建 256 MiB float64 零值数据树，再以 1 MiB 块写出普通 MAT 文件。可加 `--small` 生成 1 MiB 验证文件。输出必须是新文件。它展示驻留数据树的分块输出，不代表文件到文件的全程流式转换。

短写、奇数块长、额度及无效后部节点由三目标单元测试覆盖。Node 文件故障检查覆盖写入、关闭、提交及临时名称碰撞；原生 C 文件适配器单独注入关闭失败、尺寸不符与目标竞争。格式保真继续由 SciPy/NumPy、真实 Octave 和混合树比较核对。
