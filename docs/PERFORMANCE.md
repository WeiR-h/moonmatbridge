# 性能测量

从 v0.1.11 起，快速原生核心操作使用固定数量的重复调用形成一个计时样本，报告每次操作的平均耗时，并保存原始总耗时和重复数。每批仍先执行 5 次单调用预热，再测量 10 个样本，共 3 批；峰值内存继续使用 3 个独立进程的单次操作。重复数按固定场景制定，基线和候选使用相同设置；JS、耗时较长的压缩场景和 CLI 保持单调用。历史单调用数据保持原样，新口径独立记录。

CLI 测量结束后独立消费输出，记录输出大小和 SHA-256，再清理可重建的临时 MAT 文件。固定输入、所有计时及独立内存样本继续保留。


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



当前工具链的核心与文件读取对照保留在 [24 组核心测量](../verification/reports/performance-vs-85fef84-v0.1.4.json) 和 [6 组文件测量](../verification/reports/file-performance-v0.1.4.json)。v0.1.5 的生产源码、工具链及构建参数一致性由[独立摘要](../verification/reports/performance-summary-v0.1.5.json)记录，原始数据保留原版本。

新增驻留树写入使用单独的 [测量方法与结果入口](WRITE_PERFORMANCE.md)，覆盖两种编码、核心与文件流程。旧内存路径的完整字节缓冲直接交给同一宿主写入器。下面保留历史测量及其环境边界。

## v0.1.1 工具链基线

固定源码提交 `85fef84de68b69b7e762c3c6317266bb6674ff84`，采用 moonc `0.10.16+b1a0e846e`、配套标准库、Windows x64 MSVC `19.44.35229` C 后端、Windows SDK `10.0.22621.0` 和 Node `24.13.0`。工具链归档及标准库校验值见 `toolchain.lock.json`，构建工具包校验值见 `msvc.lock.json`。

保留原有 24 组核心及 6 组文件场景，分别报告 native 和 JS。预热5次、三批各10次，进程峰值使用三个独立进程；全部样本、中位数、p95、吞吐和请求块记录在 [核心报告](../verification/reports/performance-vs-85fef84-v0.1.1.json) 与 [文件报告](../verification/reports/file-performance-v0.1.1.json)。

本轮两组对照执行相同的固定提交，用于建立新工具链参考并记录运行波动；表中的速度比不代表代码优化。后续变更以该固定源码和相同工具链重新构建对照。历史 GCC / 旧编译器测量保留原样，单独展示。复用测量必须同时核对生产文件集合、运行时哈希、编译器、标准库、宿主与构建配置。

## 历史运行时的固定基线测量

直接对照 v0.0.19（8a1f479），原始测量版本为 v0.0.21、提交6571450。三批各10次，预热与独立进程峰值按既定协议执行。全部24组核心与6组文件结果、首次波动及同协议复测均保留；性能复用要求完整生产文件集合与哈希一致。

| 指定场景 | 宿主 | 速度比（基线/当前） |
| --- | --- | --- |
| CSC 索引写入 | native | 1.684x |
| CSC 索引写入 | js | 2.359x |
| 256 MiB 未选压缩变量＋1 MiB 选中变量 | native | 1.008x |
| 256 MiB 未选压缩变量＋1 MiB 选中变量 | js | 1.747x |

原始数据见 performance-vs-8a1f479-v0.0.21.json、file-performance-v0.0.21.json 及 performance-evaluation-v0.0.21.json。稀疏读取首轮超过阈值，后续同协议复测在10%以内；完整原始样本保持公开。文件峰值相对 v0.0.19 基本相同。此前相对 v0.0.14 的内存改善及相对更早版本的工程目标保留在历史报告中，基线分别列示。后续版本仅在运行时代码一致时引用这些测量，未声称重新计时。

## 增量压缩读取的固定样例实测

v0.0.18 对固定 v0.0.14 的历史结果如下；v0.0.19 本版测量与全部原始样本独立保存在对应版本 JSON 中。

| 文件场景 | 宿主 | 文件流程提速 | 进程峰值下降 |
| --- | --- | --- | --- |
| select-1-of-16 | native | 2.412 倍 | 69.0% |
| select-1-of-16 | js | 1.554 倍 | 25.8% |
| large-uncompressed | native | 2.552 倍 | 97.4% |
| large-uncompressed | js | 2.065 倍 | 85.6% |
| large-compressed | native | 1.001 倍 | 98.4% |
| large-compressed | js | 1.050 倍 | 86.5% |

相同输入生成器、工具链和适配器，源文件和结果额度一致。内存工程目标：小文件选择下降 40%，256 MiB 场景下降 75%；目标是否达到以每行实测和报告布尔值为准。

## 分块文件流程

v0.0.18 对照固定 v0.0.14，独立报告三类文件流程。性能报告包含环境、文件哈希、实际读取量、最大请求、全部计时样本和三个独立峰值进程。进程完整耗时另随内存进程记录；核心操作和完整命令行的既有 24 组报告继续保留。

复现：`python scripts/file-performance.py --candidate-ref <固定提交>`。当前结果见 `verification/reports/file-performance-v0.0.18.json`；不能将工程目标当作实测值。

v0.0.17 已测结果（候选 49ed45e，对照 21291ce）：

| 文件场景 | 宿主 | 文件流程提速 | 进程峰值下降 |
| --- | --- | --- | --- |
| select-1-of-16 | native | 2.164 倍 | 69.0% |
| select-1-of-16 | js | 1.587 倍 | 25.8% |
| large-uncompressed | native | 2.865 倍 | 97.4% |
| large-uncompressed | js | 2.025 倍 | 85.6% |

首轮小文件结果及优化后的完整测量分别保留，见 file-performance-initial-v0.0.17.json 与 file-performance-v0.0.17.json。

## v0.0.16 文件流程

固定 v0.0.14（21291ce）与数据源实现提交 03ce6ec，用相同工具链和开发适配器测量打开文件、读取、校验、选取、关闭与序列化；启动时间和文件生成不计入该表。

16 个各 1 MiB 变量选一个：native 峰值由 22,757,376 降至 7,057,408 字节，下降 69.0%。JS 和全部 30 个样本、三个独立峰值进程、实际读取量与最大请求大小见 [文件流程报告](../verification/reports/file-performance-v0.0.16.json)。此指标与预加载内存核心基准分别记录。


## v0.0.14 固定提交对照

新入口支持同时指定基线和候选 Git 提交；注解标签会解析到实际提交。直接基线为 v0.0.9 (`4d1e261bd6189260575b191ca786018b0906ec0d`)，候选为 `de4ffddc08c9def613e581c9f6d76ddbbc08424c`。两个版本用同一 MoonBit、GCC、Node 和 release 参数构建，原始样本及运行时源码哈希随报告保留。

```powershell
.venv\Scripts\python.exe scripts/performance-revisions.py --baseline-ref v0.0.9 --candidate-ref de4ffdd
.venv\Scripts\python.exe scripts/performance-revisions.py --baseline-ref v0.0.5 --candidate-ref de4ffdd --case select-1-of-16 --host native
```

固定八种输入、24 个操作与宿主组合。核心计时每批预热 5 次，3 批各测量 10 次；基线和候选分批交错执行。进程峰值使用三个独立进程，命令行另外执行 5 次预热和 30 次完整调用。报告保存全部样本、中位数、p95、吞吐、输出大小和进程峰值，局部复测使用独立文件。报告中的 `output_bytes=null` 表示读取操作没有生成输出文件。

| 16 MiB 压缩随机数据读取 | 核心提速 | 核心耗时下降 | 进程峰值下降 |
| --- | --- | --- | --- |
| native | 3.476 倍 | 71.2% | 22.7% |
| js | 3.556 倍 | 71.9% | 82.7% |

[完整 24 组原始报告](../verification/reports/performance-vs-4d1e261-v0.0.14.json)、[短操作复测](../verification/reports/performance-vs-4d1e261-partial-085ca5f5-v0.0.14.json)和[历史选择读取复测](../verification/reports/performance-vs-b9df1ed-partial-292bfae3-v0.0.14.json)保留全部样本；[结果汇总](../verification/reports/performance-evaluation-v0.0.14.json)核对运行时哈希。压缩读取的两个宿主均超过耗时降低 25% 的工程目标。

原生选择读取的额外峰值下降相对 v0.0.9 为 0.0%；相对 v0.0.5 提速 19.047 倍、峰值下降 38.2%，额外下降 10% 和历史下降 40% 的目标未达。首轮两项原生短操作波动超过 10%，同输入、同协议复测均回到阈值内；首轮及复测同时保留。

## 历史测量


从 v0.0.6 开始固定 [基准清单](../benchmarks/manifest.json) 和输入种子 `20261017`。`scripts/performance.py` 从提交 `b9df1eddaacdefebc2e32eee468fada8cc9e6020` 取出 v0.0.5 源码，仅加入相同开发计时适配器，再用同一工具链构建对照。

```powershell
.venv\Scripts\python.exe scripts/performance.py --baseline-only
.venv\Scripts\python.exe scripts/performance.py
```

数据覆盖 16 MiB 密集数组、16 MiB 复数、4 MiB 递归混合树、100,000 项 CSC、压缩随机数据、全零压缩和从 16 个变量选择一个。大端读取单列。生成和启动不计入核心耗时；写入对象在计时前准备。每个目标使用三个新进程批次，每批预热 5 次、测量 10 次，报告 30 个原始样本、中位数与 p95。比较版本交错测量；历史基线另行保留。

内存单独启动新进程，不预热，执行一次操作；重复三个进程，记录全部峰值及其中位数。Windows 为峰值工作集，Linux 为峰值 RSS。输入、宿主和写入准备成本都计入峰值；不能把它解释为纯输出缓冲的大小。JS 在计时外主动 GC，native 采用自身运行时，两者只各自与同目标的旧版本比较。

计时与内存适配器位于独立开发包，不进入 Windows 产品命令行的依赖。宿主只提供读文件、时钟和进程内存统计，编解码继续执行 MoonBit 实现。

正式结果放在 `verification/reports/performance-*.json`。`measured` 表示已获得数据，目标是否达到需按每个场景和宿主分别判断；不能把总体平均值作为某项通过证明。兼容性失败、输入被超限拒绝或工具崩溃都不能作为有效速度成绩。

工程目标：指定未压缩写入耗时降低 30%、峰值降低 25%；未压缩文件选择一个变量达到 2 倍速度、峰值降低 40%。它们是工程目标，未达到时明确报告。完整兼容及赛事验收不由这些数字代替。

## 本轮实测与交付汇总

v0.0.7 正式测量：Windows 11 x64，同机 MoonBit 0.1.20260920、GCC 16.2.0、Node 24.13.0。固定样例保留全部 30 个核心样本、30 个命令行样本和 3 个独立峰值样本。以下为与固定 v0.0.5 相比的核心结果；完整 p95、吞吐、大小端/压缩/CSC 结果及命令行耗时见原始报告。

| v0.0.7 写入场景 | 宿主 | 核心提速 | 进程峰值下降 |
| --- | --- | --- | --- |
| 16 MiB 密集数组 | native | 12.232 倍 | 38.6% |
| 16 MiB 密集数组 | JS | 10.905 倍 | 87.0% |
| 4 MiB 嵌套混合树 | native | 105.552 倍 | 35.2% |
| 4 MiB 嵌套混合树 | JS | 59.987 倍 | 87.4% |

这四组写入目标均通过；固定场景没有可重复的超过 10% 退化。v0.0.7 的选择读取目标尚未通过，原始不利结果保留，不能计为当版已完成。

v0.0.8 使用相同场景和规则复测全部 24 个操作/宿主组合；选择读取的两个目标和其他场景的回归逐项列在 `performance-v0.0.8.json` 与 `performance-evaluation-v0.0.8.json`。不要用某宿主的通过结果代替另一宿主。

| v0.0.8：16 个各 1 MiB 变量中选一个 | 核心提速 | 峰值下降 | 2 倍 / 40% 工程目标 |
| --- | --- | --- | --- |
| native | 14.187 倍 | 38.3% | 内存目标未达；速度通过 |
| JS | 10.349 倍 | 48.1% | 通过 |

native 峰值为 23,736,320 字节，对照为 38,445,056 字节。保持原定样例和包含输入的进程测法，未将 38.3% 写成 40%。四组写入目标继续通过，最终 24 组无超过 10% 的退化。首轮原生 CSC 退化与压缩读取偏慢的全部数据保留在 `performance-attempt-17c4f0d-v0.0.8.json`；调整热路径后用相同协议完整复测。

v0.0.9 冻结运行时，仅版本描述及验收资料变化。`scripts/performance-summary.py` 验证其运行时代码与 v0.0.8 一致（排除版本文字、规范化换行），并生成 `performance-summary-v0.0.9.json`，明确引用历史测量版本和哈希；不伪称 v0.0.9 又测出了新加速成绩。若一致性检查失败，应重新测量，不能直接继承结论。
