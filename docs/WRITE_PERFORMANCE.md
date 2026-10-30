# 分块写入测量


## 固定 v0.1.5 对照（v0.1.8）

当前版本分别重测 24 组核心、6 组文件读取和 32 组同一 MatSink 接口的固定版本对照。原始版本、全部样本与测量环境分别保存，新增工程目标只针对 JS 未压缩 CSC，实际达成情况以报告为准。

- [24 组核心](../verification/reports/performance-vs-70f87e2-v0.1.8.json)
- [6 组文件读取](../verification/reports/file-performance-v0.1.8.json)
- [32 组写入对照](../verification/reports/write-regression-v0.1.8.json)
- [可读汇总](../verification/reports/WRITE_PERFORMANCE-v0.1.8.md)

```powershell
python scripts/write-regression.py --baseline-ref v0.1.5 --candidate-ref v0.1.8
```

以下保留历史同版两接口比较及其环境边界。


固定同一提交中的旧内存写入和新 MatSink 路径，使用相同的定点文件适配策略。旧写入实现的完整已有核心源码对照固定新工具链基线 `85fef84`，确认未修改。输入包括 16 MiB 密集数据、4 MiB 混合树、100k CSC 和驻留 256 MiB 数据树；大树由固定种子 32 KiB 块重复生成。

```powershell
python scripts/write-performance.py --candidate-ref v0.1.5
```

每项预热 5 次、3 批各 10 次、3 个独立进程峰值，保存全部样本。核心测量使用已驻留树和丢弃 sink，排除启动、准备及文件 I/O；文件流程包含写入、关闭和禁止覆盖的发布，单独记录完整进程耗时。进程峰值包含输入树，操作前高水位单列，不能直接相减宣称编码器占用。

旧内存接口可以在显式 1 GiB 限额下写出 256 MiB 未压缩文件；其旧 DEFLATE 仍限制单根输入 64 MiB，因此该项压缩不计算旧新提速。新压缩输出允许不同压缩字节，未压缩路径比较完整文件哈希。

本轮写入测量见 [完整测量与原始样本](../verification/reports/write-performance-v0.1.5.json)。历史 24 组核心和 6 组文件读取测量保留，新运行时代码绑定固定工具链；完全相同的生产源码和构建配置才允许引用已有原始测量。
