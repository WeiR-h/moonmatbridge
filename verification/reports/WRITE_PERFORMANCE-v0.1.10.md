# MoonMatBridge v0.1.10 写入证据

测量版本：v0.1.8；固定提交：`b227850062bdd1315e2e252049048fee2be22094`。当前版本的适用范围见 [完整来源绑定](performance-binding-v0.1.10.json)。

[原始样本](write-regression-v0.1.8.json)，SHA-256：`4d2db4de82cdb077093352a20663529ab89ae0a00d7b2fa069be95383861303b`。保留原始版本与全部不利结果，数据按其原测量版本展示。

| 输入 | 目标 | 编码 | 路径 | 基线 / 候选 中位 ms | 倍速 | 基线 / 候选 峰值 MiB |
| --- | --- | --- | --- | ---: | ---: | ---: |
| dense-16m | native | plain | core | 0.88 / 0.90 | 0.980 | 37.9 / 37.9 |
| dense-16m | native | plain | file | 7.75 / 7.72 | 1.004 | 37.9 / 37.9 |
| dense-16m | native | compressed | core | 750.57 / 746.74 | 1.005 | 37.9 / 37.9 |
| dense-16m | native | compressed | file | 761.49 / 757.17 | 1.006 | 37.9 / 37.9 |
| dense-16m | js | plain | core | 78.45 / 18.68 | 4.200 | 73.0 / 73.0 |
| dense-16m | js | plain | file | 89.30 / 27.44 | 3.254 | 73.0 / 72.9 |
| dense-16m | js | compressed | core | 1418.29 / 1329.28 | 1.067 | 81.7 / 81.8 |
| dense-16m | js | compressed | file | 1488.98 / 1432.86 | 1.039 | 82.6 / 81.8 |
| nested-4m | native | plain | core | 0.40 / 0.30 | 1.346 | 13.9 / 13.9 |
| nested-4m | native | plain | file | 3.13 / 3.44 | 0.910 | 13.9 / 13.9 |
| nested-4m | native | compressed | core | 199.65 / 200.96 | 0.993 | 13.9 / 13.9 |
| nested-4m | native | compressed | file | 196.01 / 193.08 | 1.015 | 13.9 / 13.9 |
| nested-4m | js | plain | core | 20.78 / 5.36 | 3.879 | 49.1 / 49.2 |
| nested-4m | js | plain | file | 24.63 / 8.61 | 2.859 | 49.1 / 49.2 |
| nested-4m | js | compressed | core | 367.53 / 340.10 | 1.081 | 76.2 / 76.3 |
| nested-4m | js | compressed | file | 372.83 / 338.05 | 1.103 | 75.9 / 76.5 |
| sparse-100k | native | plain | core | 0.50 / 0.49 | 1.027 | 8.2 / 8.2 |
| sparse-100k | native | plain | file | 2.14 / 2.13 | 1.007 | 8.2 / 8.2 |
| sparse-100k | native | compressed | core | 80.91 / 83.11 | 0.973 | 9.5 / 9.5 |
| sparse-100k | native | compressed | file | 88.32 / 94.61 | 0.934 | 9.5 / 9.5 |
| sparse-100k | js | plain | core | 14.16 / 4.65 | 3.044 | 44.3 / 45.0 |
| sparse-100k | js | plain | file | 16.73 / 6.73 | 2.486 | 45.8 / 46.1 |
| sparse-100k | js | compressed | core | 128.63 / 118.92 | 1.082 | 59.5 / 60.0 |
| sparse-100k | js | compressed | file | 131.22 / 131.83 | 0.995 | 59.7 / 59.8 |
| resident-256m | native | plain | core | 17.64 / 17.81 | 0.990 | 262.8 / 262.8 |
| resident-256m | native | plain | file | 529.10 / 544.07 | 0.972 | 262.8 / 262.8 |
| resident-256m | native | compressed | core | 1893.72 / 1831.77 | 1.034 | 264.2 / 264.2 |
| resident-256m | native | compressed | file | 1833.33 / 1845.16 | 0.994 | 264.2 / 264.2 |
| resident-256m | js | plain | core | 688.82 / 301.28 | 2.286 | 298.6 / 298.9 |
| resident-256m | js | plain | file | 799.21 / 386.63 | 2.067 | 299.0 / 299.0 |
| resident-256m | js | compressed | core | 4671.26 / 4505.87 | 1.037 | 305.1 / 304.5 |
| resident-256m | js | compressed | file | 4602.78 / 4454.87 | 1.033 | 304.4 / 304.5 |

输入树驻留内存；进程峰值包括准备过程高水位。原始测量采用每批预热 5 次、3 批各 10 次及 3 个独立进程峰值。比较口径见原始报告：固定版本 MatSink 对照与历史同版两接口对照分别保存。
