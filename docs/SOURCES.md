# 文件数据源与有界读取

`MatSource` 包含 `size` 和 `read_into(offset, target, start, length) -> Int`。回调填充已有 FixedArray[Byte]，返回实际读取量；0 是 EOF，负数是 I/O 失败。核心处理合法短读并检查边界。调用期间来源必须保持稳定，回调不得保留或异步修改目标缓冲。

`read_tree_from`、`read_selected_from`、`inspect_roots_from` 接收数据源及可选 `SourceLimits`、`TreeLimits`。全部输入验证完成后返回结果，选取顺序遵循请求，空选择仍完整验证。结果拥有自身数据，内部文件偏移不对外缓存。

SourceLimits 默认源文件/累计解压各 1 GiB、所选规范未压缩 MAT 大小 64 MiB、整根暂存 64 MiB、累计元数据 8 MiB、块 1 MiB、累计元素 134217728，其余结构额度延续内存接口默认值。原 Limits 不变。

未压缩路径按块递归解析，未选负载只做校验和消费，不构造完整数据。单个 256 MiB 未选变量可与 1 MiB 所选变量一起处理。压缩路径通过增量 DEFLATE 直接驱动同一分块解析器，只保留 32 KiB 历史窗口及受控块缓冲；不再分配完整压缩根或展开根。roots/select 参数和 JSON 格式保持兼容，通过 native/Node 单次打开文件的数据源读取，检查读前读后状态并在所有退出路径关闭句柄。

```moonbit
let source : @mat.MatSource = {
  size: data.length(),
  read_into: fn(offset, target, start, count) {
    for i = 0; i < count; i = i + 1 { target[start + i] = data[offset + i] }
    count
  },
}
let selected = @mat.read_selected_from(source, ["signal"])
```

JS 导出 make_source(size, readInto)、inspect_roots_source(source)、select_source_mat(source,names)；原有 Bytes 导出继续可用。readInto 应捕获宿主 I/O 异常并返回负数，状态通过现有 result_status/result_bytes 获取。

`max_buffered_root_bytes` 保留以兼容既有配置；当前分块路径不需要整根暂存。累计解压、结果和元数据限额继续独立执行，Adler-32 及全部根变量验证成功后才返回所选结果。
