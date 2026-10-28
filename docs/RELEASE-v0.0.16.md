# MoonMatBridge v0.0.16

新增 MatSource、SourceLimits 和三个数据源读取接口。roots/select 使用可复用缓冲的文件适配，按根变量加载和释放，完整检查未选变量。原有内存接口及命令行参数保持兼容。

native 和 Node 使用单次打开的文件句柄，处理短读、I/O 失败及源变化。读取结果拥有自身数据，失败不会生成输出文件。SourceLimits 分别约束来源、展开量、结果、暂存、元数据及结构规模。

接口和阶段性暂存范围见 SOURCES.md。

固定 16×1 MiB 选一场景的 native 进程峰值相对 v0.0.14 文件流程下降 69.0%。JS 与全部样本单独记录。
