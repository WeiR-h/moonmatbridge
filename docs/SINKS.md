# 分块写出

`write_tree_to` 完整预检混合树，再将 MAT 标签、元数据和载荷按块送入 `MatSink`。输出与同版 `write_tree` 的未压缩结果逐字节一致。它覆盖数值、复数、CSC、字符、cell、struct 和 legacy object，保留名称编码、字段顺序、原始数值位、字符单位及 CSC 存储槽位。

```moonbit
pub(all) struct MatSink {
  write_from : (Int32, FixedArray[Byte], Int32, Int32) -> Int32
}

write_tree_to(variables, sink, compressed?, limits?, tree_limits?, name_encoding?)
// -> Int32 raise MatError，成功时返回最终文件长度
```

回调依次接收输出偏移、借用缓冲、缓冲起点和请求长度，返回实际写入量。核心处理合法短写；零、负数或大于请求量均为 `io-error`。回调同步执行，不得修改或保留缓冲；写入期间输入树保持稳定。

## 独立写入额度

| `WriteLimits` 字段 | 默认值 |
| --- | --- |
| `max_output_bytes` | 1 GiB，包含文件头的最终文件长度 |
| `max_uncompressed_bytes` | 1 GiB，规范未压缩 MAT 总长度 |
| `max_metadata_bytes` | 8 MiB，累计维度、编码名称、类名和带填充的字段表 |
| `chunk_bytes` | 1 MiB，支持 1 字节—8 MiB |
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

## 压缩输出

`write_tree_to(..., compressed=true)` 为每个根变量独立生成 zlib 流，编码块直接进入增量 DEFLATE。原始块固定为 65,535 字节，保留 32 KiB 历史窗口，并按实际位成本选择 fixed Huffman 或 stored 块；宿主短写和输出块大小不会改变压缩结果。完成根变量后用定点回填更新 miCOMPRESSED 长度，因此 sink 必须支持回写。

工作内存包含两个输出/编码块、98,303 字节窗口、两个 32,768 项索引表及最多 80,000 项候选字节的单块编码（数组实际内存依目标表示而异）；不保存完整根变量或完整压缩结果。输入树及节点尺寸计划另计。压缩后的实际输出额度在执行中检查，触发错误时文件宿主清理临时文件。

native / Node 的 `compress` 使用此路径，保留原有命令参数和额度。JS 新增 `compress_mat_to` 及 `compress_mat_to_with_options`，旧内存压缩导出继续可用。压缩字节无需与旧编码器一致，展开后的规范 MAT 数据完全一致。

示例支持 `--compressed`，可与 `--small` 同时使用。两种输出均由独立 SciPy 消费核对。[写入测量方法](WRITE_PERFORMANCE.md) 区分输入树、编码缓冲与完整进程峰值。
