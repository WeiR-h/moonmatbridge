# MoonMatBridge v0.0.20

增加显式 MAT 名称编码策略，支持 UTF-8 与 Latin1 的变量名、结构字段名和 legacy 类名读写。内存读取、分块文件读取、根目录及选择读取共用策略；写入预检与字段宽度按实际编码字节计算。

两个命令行宿主支持前置 `--name-encoding=utf8|latin1`。JS 新增 `*_with_options` 导出，原有导出及默认 UTF-8 行为保持兼容。混合树快照保存名称文本，恢复旧编码时可明确指定写出策略。

验证覆盖三目标、独立混合元数据检查、压缩输入、uint64、负零、选择顺序和失败原子性。具体执行结果见本版本 verification/reports。使用方法见 docs/NAME_ENCODING.md。
