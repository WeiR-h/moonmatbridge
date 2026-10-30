# MoonMatBridge v0.1.6 写入证据

测量版本：v0.1.5；固定提交：`272840f0feedc51ffd7a54a3213e9b4b95111f93`。当前版本的继承条件见 [完整来源绑定](performance-binding-v0.1.6.json)。

[原始样本](write-performance-v0.1.5.json)，SHA-256：`05316f75038d7f7b95335e7a715a67e68abacb2f6a7cf2a9615184877a711845`。保留原始版本与全部不利结果，本页没有生成新的计时。

| 输入 | 目标 | 编码 | 路径 | 旧 / Sink 中位 ms | 倍速 | 旧 / Sink 峰值 MiB |
| --- | --- | --- | --- | ---: | ---: | ---: |
| dense-16m | native | plain | core | 3.87 / 0.86 | 4.524 | 37.1 / 37.1 |
| dense-16m | native | plain | file | 10.28 / 6.84 | 1.502 | 37.1 / 37.1 |
| dense-16m | native | compressed | core | 694.35 / 690.44 | 1.006 | 69.9 / 37.1 |
| dense-16m | native | compressed | file | 709.82 / 702.47 | 1.010 | 69.9 / 37.1 |
| dense-16m | js | plain | core | 76.64 / 71.94 | 1.065 | 72.0 / 72.0 |
| dense-16m | js | plain | file | 84.06 / 78.36 | 1.073 | 72.1 / 72.0 |
| dense-16m | js | compressed | core | 1658.58 / 1309.11 | 1.267 | 966.2 / 80.9 |
| dense-16m | js | compressed | file | 1673.21 / 1311.66 | 1.276 | 966.4 / 81.2 |
| nested-4m | native | plain | core | 0.71 / 0.28 | 2.492 | 13.1 / 13.1 |
| nested-4m | native | plain | file | 3.19 / 2.60 | 1.228 | 13.1 / 13.1 |
| nested-4m | native | compressed | core | 173.58 / 175.81 | 0.987 | 22.4 / 13.1 |
| nested-4m | native | compressed | file | 177.07 / 178.05 | 0.995 | 22.4 / 13.1 |
| nested-4m | js | plain | core | 20.00 / 19.38 | 1.032 | 48.4 / 48.2 |
| nested-4m | js | plain | file | 23.05 / 21.71 | 1.062 | 48.5 / 48.2 |
| nested-4m | js | compressed | core | 378.01 / 337.84 | 1.119 | 244.9 / 74.9 |
| nested-4m | js | compressed | file | 379.34 / 339.24 | 1.118 | 245.0 / 74.9 |
| sparse-100k | native | plain | core | 0.47 / 0.47 | 0.996 | 7.4 / 7.4 |
| sparse-100k | native | plain | file | 2.02 / 2.03 | 0.993 | 7.4 / 7.4 |
| sparse-100k | native | compressed | core | 75.48 / 74.46 | 1.014 | 9.1 / 8.8 |
| sparse-100k | native | compressed | file | 77.04 / 78.73 | 0.978 | 9.2 / 8.8 |
| sparse-100k | js | plain | core | 10.79 / 12.96 | 0.832 | 43.4 / 43.2 |
| sparse-100k | js | plain | file | 13.02 / 14.73 | 0.884 | 43.4 / 43.3 |
| sparse-100k | js | compressed | core | 98.88 / 107.23 | 0.922 | 76.9 / 57.4 |
| sparse-100k | js | compressed | file | 103.17 / 109.04 | 0.946 | 77.1 / 57.1 |
| resident-256m | native | plain | core | 48.04 / 11.37 | 4.225 | 517.0 / 262.0 |
| resident-256m | native | plain | file | 132.83 / 89.17 | 1.490 | 517.0 / 262.0 |
| resident-256m | native | compressed | core | 限额 / 1687.71 | — | — / 263.4 |
| resident-256m | native | compressed | file | 限额 / 1694.87 | — | — / 263.4 |
| resident-256m | js | plain | core | 738.23 / 645.46 | 1.144 | 552.8 / 297.6 |
| resident-256m | js | plain | file | 828.35 / 720.12 | 1.150 | 552.9 / 297.9 |
| resident-256m | js | compressed | core | 限额 / 4274.85 | — | — / 304.0 |
| resident-256m | js | compressed | file | 限额 / 4274.97 | — | — / 303.3 |

输入树驻留内存；进程峰值包括准备过程高水位。原始测量采用每批预热 5 次、3 批各 10 次及 3 个独立进程峰值。此表比较同版内存与分块接口，各场景取舍分别保留。
