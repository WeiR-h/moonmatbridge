# MoonMatBridge v0.1.3

新增 MatSink / WriteLimits / write_tree_to，整树预检后分块输出全部现有类型，与同版未压缩内存写出逐字节一致。native、Node 的 roundtrip/select/restore-tree 使用临时文件并在成功关闭后生成最终文件名，保留原参数和额度。增加大型驻留树示例、短写与文件失败测试，公开消费者不再固定旧版本断言。
