# MoonMatBridge 项目检查索引

当前版本：**v0.1.4**。核心格式处理、压缩、比较、快照和资源校验由 MoonBit 实现，宿主负责文件与进程适配。本页对应项目的九项检查入口；持续更新公开仓库，无需另行提交表格。

| 检查项 | 仓库入口与复现方式 |
| --- | --- |
| MoonBit 主要实现、moonc ≥ 0.10.16 | [源码](../src/)、[固定工具链](../toolchain.lock.json)；`python scripts/setup-toolchain.py --configure` 后运行 `node scripts/toolchain.mjs`，核对实际 moonc |
| 公开仓库与提交记录 | [GitHub](https://github.com/WeiR-h/moonmatbridge)、[提交记录](https://github.com/WeiR-h/moonmatbridge/commits/main)、[版本记录](../CHANGELOG.md) |
| 结构清晰、核心功能可运行 | [API](API.md)、[格式与额度](FORMAT.md)、[兼容矩阵](COMPATIBILITY_MATRIX.md)；核心包、interchange 和宿主分开维护 |
| README 包含目标、安装、用法和示例 | [README](../README.md)、[文件源](SOURCES.md)、[名称编码](NAME_ENCODING.md)、[容差比较](TREE_CLOSE.md) |
| CI 覆盖检查、构建、测试 | [Windows/Linux 工作流](../.github/workflows/ci.yml)、[验证入口](../scripts/verify.mjs)；Linux 额外执行真实 GNU Octave |
| 至少一个可运行最小样例 | [MoonBit 示例](../src/examples/main/)、[公开包消费者](../examples/registry_consumer/)、[三个科研流程](SCIENTIFIC_WORKFLOWS.md) |
| 核心路径测试 | [核心测试](../src/)、[独立 SciPy/NumPy 检查](../scripts/interop.py)、[覆盖报告入口](../scripts/coverage.py)；`npm run verify` 和 `npm run coverage` |
| 发布到 Mooncakes | [WeiR-h/moonmatbridge@0.1.4](https://mooncakes.io/docs/WeiR-h/moonmatbridge@0.1.4)；`moon add WeiR-h/moonmatbridge@0.1.4`，`npm run verify:registry` 核对公开包实际字节并执行三目标消费者 |
| OSI 开源许可证与第三方说明 | [Apache-2.0](../LICENSE)、[NOTICE](../NOTICE)、[第三方与参考来源](../THIRD_PARTY.md)；发行包许可文件逐字节核对 |

## 完整流程

从 [v0.1.4 发行页](https://github.com/WeiR-h/moonmatbridge/releases/tag/v0.1.4) 获取 Windows、JS、源码或科研流程包。运行 Windows 包内的 `examples/workflows/demo.ps1`，或按 [科研流程说明](SCIENTIFIC_WORKFLOWS.md) 重现混合实验归档、稀疏仿真交换及 NumPy 转换与比较。

`verification/reports` 按版本保存实际验证结果。`v*.json` 包含检查分组、工具版本、源码指纹和 native 哈希；`ci-*` 记录真实执行地址；`octave-*` 记录双向互操作；`mooncakes-*`、`public-downloads-*`、`workflows-public-*` 记录公开消费；`licenses-*` 校验发行包许可。测试数量与覆盖率取自实际报告，不在此固定维护。

兼容范围包括 MAT Level 5 基本类 1—15、递归混合数据、字符存储单位和显式名称编码、CSC 原始索引及容量。legacy object 提供类名、字段和数据互操作。实际独立消费使用 SciPy/NumPy 与 GNU Octave；工具和具体文件结果见兼容矩阵。

[当前路线](NEXT_RELEASES.md) 与历史记录分开维护；[性能报告](PERFORMANCE.md) 区分固定工具链基线、历史测量和新增功能的测量。当前 0.1.x 保持已有接口与报告格式兼容。
