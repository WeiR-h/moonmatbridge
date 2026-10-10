# v0.0.3 五轮核心迭代

实施日期：2026-10-10；起点 v0.0.2。五轮在一个兼容版本中交付，保留 v0.0.1/v0.0.2 历史版本。

| 轮次 | 解决的问题与完成内容 | 对应开发提交 | 验证方式 |
| --- | --- | --- | --- |
| 1 | 科研数组需要选择窗口/样本及组合结果。新增 slice、gather_axis、concat_arrays、严格转换计划和 CLI | `4cf4740` | 原始浮点/复数/uint64 字节保留；NumPy 九步转换流程对照；错误不写出文件 |
| 2 | 只有解压，不能产出压缩 MAT。新增有界确定性 LZ77、固定 Huffman 编码、stored 回退及压缩写入 | `ef61fbf` | 44 个输出由 Node zlib 独立解码；704 个反向输入流；重复输出一致；SciPy 读取压缩 MAT |
| 3 | 实际科研文件含稀疏矩阵。新增 CSC、混合文档、容量保留和显式密集转换 | `a2e89f2` | SciPy double/logical/complex/empty/巨大形状；Python 独立大端夹具；指针、越界和乱序拒绝 |
| 4 | 普通 JSON 不能存档所有 IEEE 编码。新增 raw-hex 快照与恢复 | `da98286` | 独立夹具逐字节核对两平面；CSC 未使用容量；恢复后精确比较；畸形输入不留输出 |
| 5 | 转换后缺少可用于科研回归的差异说明。新增按名称匹配、坐标、计数、全局样本额度与 CI 退出码 | `9b9d859` | NaN payload、负零、uint64 的单字节变化；压缩/顺序变化相同；报告文件及拒绝覆盖 |

完整验收由 `npm run verify` 执行三目标测试、示例、两宿主和独立科学库；`npm run package` 检查源码指纹，并从新目录解压验证源码、Windows 程序和 JS 包。当前测试声明共 52 项，含混合文件名称冲突回归；独立 SciPy/NumPy 验证共 54 组。每种环境的实际结果和版本保存在 [报告目录](../verification/reports/)，不得将本地结果替代未执行的目标。

本轮增强了科研 MAT 数据接口及可复现检查。完整性边界见 [FORMAT.md](FORMAT.md)，科研案例见 [RECIPES.md](RECIPES.md)，与已有生态项目的交集见 [DIFFERENTIATION.md](DIFFERENTIATION.md)。
