# MoonMatBridge v0.1.11 写入证据

测量版本：v0.1.11；固定提交：`242f58b4d832d87e6d991426f82ed17e5fa09374`。当前版本的适用范围见 [完整来源绑定](performance-binding-v0.1.11.json)。

[原始样本](write-regression-vs-63e2304-run-968be36e-v0.1.11.json)，SHA-256：`7947ca0518ac9cec239a462651862c5ffc0f0b75881a08acbe1b98571fa91097`。保留原始版本与全部不利结果，数据按其原测量版本展示。

| 输入 | 目标 | 编码 | 路径 | 基线 / 候选 中位 ms | 倍速 | 基线 / 候选 峰值 MiB |
| --- | --- | --- | --- | ---: | ---: | ---: |
| dense-16m | native | plain | core | 1.04 / 0.87 | 1.191 | 37.8 / 37.8 |
| dense-16m | native | plain | file | 9.53 / 9.22 | 1.034 | 37.8 / 37.9 |
| dense-16m | native | compressed | core | 748.58 / 505.83 | 1.480 | 37.8 / 37.9 |
| dense-16m | native | compressed | file | 799.94 / 573.39 | 1.395 | 37.8 / 37.9 |
| dense-16m | js | plain | core | 22.89 / 22.71 | 1.008 | 72.8 / 73.2 |
| dense-16m | js | plain | file | 33.84 / 32.76 | 1.033 | 72.8 / 73.2 |
| dense-16m | js | compressed | core | 1262.08 / 1361.22 | 0.927 | 88.5 / 88.3 |
| dense-16m | js | compressed | file | 1220.52 / 1374.26 | 0.888 | 88.4 / 88.4 |
| nested-4m | native | plain | core | 0.29 / 0.30 | 0.961 | 13.8 / 13.9 |
| nested-4m | native | plain | file | 3.02 / 3.31 | 0.913 | 13.8 / 13.9 |
| nested-4m | native | compressed | core | 189.45 / 136.28 | 1.390 | 13.8 / 13.8 |
| nested-4m | native | compressed | file | 201.81 / 137.65 | 1.466 | 13.8 / 13.9 |
| nested-4m | js | plain | core | 9.13 / 9.21 | 0.991 | 48.8 / 49.4 |
| nested-4m | js | plain | file | 12.21 / 13.49 | 0.905 | 48.9 / 49.4 |
| nested-4m | js | compressed | core | 321.92 / 315.86 | 1.019 | 77.8 / 77.8 |
| nested-4m | js | compressed | file | 338.13 / 340.00 | 0.994 | 77.7 / 77.8 |
| sparse-100k | native | plain | core | 0.51 / 0.49 | 1.036 | 8.1 / 8.1 |
| sparse-100k | native | plain | file | 2.24 / 2.11 | 1.061 | 8.1 / 8.1 |
| sparse-100k | native | compressed | core | 79.74 / 41.33 | 1.929 | 9.5 / 9.5 |
| sparse-100k | native | compressed | file | 82.74 / 46.05 | 1.797 | 9.5 / 9.5 |
| sparse-100k | js | plain | core | 13.04 / 15.05 | 0.867 | 43.8 / 44.2 |
| sparse-100k | js | plain | file | 16.10 / 16.88 | 0.954 | 43.9 / 44.2 |
| sparse-100k | js | compressed | core | 131.53 / 129.90 | 1.013 | 58.4 / 58.4 |
| sparse-100k | js | compressed | file | 153.06 / 151.34 | 1.011 | 58.5 / 58.5 |
| resident-256m | native | plain | core | 14.59 / 14.45 | 1.009 | 262.8 / 262.8 |
| resident-256m | native | plain | file | 818.08 / 997.43 | 0.820 | 262.8 / 262.8 |
| resident-256m | native | compressed | core | 1753.19 / 1438.53 | 1.219 | 264.2 / 264.2 |
| resident-256m | native | compressed | file | 1684.57 / 1446.77 | 1.164 | 264.2 / 264.2 |
| resident-256m | js | plain | core | 297.42 / 296.50 | 1.003 | 298.0 / 298.8 |
| resident-256m | js | plain | file | 460.11 / 558.13 | 0.824 | 298.1 / 298.9 |
| resident-256m | js | compressed | core | 3488.35 / 3630.80 | 0.961 | 303.8 / 303.8 |
| resident-256m | js | compressed | file | 3534.39 / 3541.36 | 0.998 | 303.8 / 304.0 |

输入树驻留内存；进程峰值包括准备过程高水位。原始测量采用每批预热 5 次、3 批各 10 次及 3 个独立进程峰值。比较口径见原始报告：固定版本 MatSink 对照与历史同版两接口对照分别保存。

首次观测保留在上表；对应复测原件：[write-regression-vs-63e2304-partial-4000e8cb-v0.1.11.json](write-regression-vs-63e2304-partial-4000e8cb-v0.1.11.json), [write-regression-vs-63e2304-partial-88fa81ae-v0.1.11.json](write-regression-vs-63e2304-partial-88fa81ae-v0.1.11.json), [write-regression-vs-63e2304-partial-07e8e659-v0.1.11.json](write-regression-vs-63e2304-partial-07e8e659-v0.1.11.json), [write-regression-vs-63e2304-partial-1d4895d2-v0.1.11.json](write-regression-vs-63e2304-partial-1d4895d2-v0.1.11.json), [write-regression-vs-63e2304-partial-bb2bf416-v0.1.11.json](write-regression-vs-63e2304-partial-bb2bf416-v0.1.11.json)。复测判定和全部原件哈希见来源绑定。
