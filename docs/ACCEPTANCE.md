# MoonMatBridge 项目检查索引

当前版本：**v0.1.11**。核心格式处理、压缩、比较、快照和资源校验由 MoonBit 实现，宿主负责文件与进程适配。本页对应项目的九项检查入口；持续更新公开仓库，无需另行提交表格。

| 检查项 | 仓库入口与复现方式 |
| --- | --- |
| MoonBit 主要实现、moonc ≥ 0.10.16 | [源码](../src/)、[固定工具链](../toolchain.lock.json)；`python scripts/setup-toolchain.py --configure` 后运行 `node scripts/toolchain.mjs`，核对实际 moonc |
| 公开仓库与提交记录 | [GitHub](https://github.com/WeiR-h/moonmatbridge)、[提交记录](https://github.com/WeiR-h/moonmatbridge/commits/main)、[版本记录](../CHANGELOG.md) |
| 结构清晰、核心功能可运行 | [API](API.md)、[格式与额度](FORMAT.md)、[兼容矩阵](COMPATIBILITY_MATRIX.md)；核心包、interchange 和宿主分开维护 |
| README 包含目标、安装、用法和示例 | [README](../README.md)、[文件源](SOURCES.md)、[名称编码](NAME_ENCODING.md)、[容差比较](TREE_CLOSE.md) |
| CI 覆盖检查、构建、测试 | [Windows/Linux 工作流](../.github/workflows/ci.yml)、[验证入口](../scripts/verify.mjs)；Linux 额外执行真实 GNU Octave |
| 至少一个可运行最小样例 | [MoonBit 示例](../src/examples/main/)、[公开包消费者](../examples/registry_consumer/)、[三个科研流程](SCIENTIFIC_WORKFLOWS.md) |
| 核心路径测试 | [核心测试](../src/)、[独立 SciPy/NumPy 检查](../scripts/interop.py)、[覆盖报告入口](../scripts/coverage.py)；`npm run verify` 和 `npm run coverage` |
| 发布到 Mooncakes | [WeiR-h/moonmatbridge@0.1.11](https://mooncakes.io/docs/WeiR-h/moonmatbridge@0.1.11)；`moon add WeiR-h/moonmatbridge@0.1.11`，`npm run verify:registry` 核对公开包实际字节并执行三目标消费者 |
| OSI 开源许可证与第三方说明 | [Apache-2.0](../LICENSE)、[NOTICE](../NOTICE)、[第三方与参考来源](../THIRD_PARTY.md)；发行包许可文件逐字节核对 |

## 完整流程

从 [v0.1.11 发行页](https://github.com/WeiR-h/moonmatbridge/releases/tag/v0.1.11) 下载 `MoonMatBridge-v0.1.11-windows-x64.zip`。解压到路径较短的目录，在含 `moonmat.exe` 的目录中执行以下命令。

```powershell
$results = Join-Path $env:TEMP ('moonmat-demo-' + [guid]::NewGuid().ToString('N'))
powershell -NoProfile -ExecutionPolicy Bypass -File .\examples\workflows\demo.ps1 -OutputDirectory $results
```

终端会显示结果目录，其中的 `demo-receipt.json` 保存三个科研流程的命令、退出码和文件哈希。需要使用 MoonBit API 时，按 [README 的公开包消费者步骤](../README.md#moonbit-api) 在独立目录运行最小示例。完整输入、预期结果和独立核对方法见 [科研流程说明](SCIENTIFIC_WORKFLOWS.md)。

## v0.1.11 验证证据

- 固定源码 `242f58b`，发行标签 `da564f4`。Windows/Linux CI 覆盖 JS、wasm-gc、native 的检查、构建和测试，Linux 执行真实 GNU Octave 验证。[CI 执行](https://github.com/WeiR-h/moonmatbridge/actions/runs/41206292702) · [测试报告](../verification/reports/v0.1.11.json) · [Octave 报告](../verification/reports/octave-v0.1.11.json)
- 从公开 Mooncakes 包安装精确版本并运行三目标消费者。公开安装包内的 182 个文件与 GitHub 发行标签逐字节一致。GitHub 另提供工具、运行资产和报告。[安装回执](../verification/reports/registry-v0.1.11.json) · [包文件及 SHA-256](../verification/reports/mooncake-audit-v0.1.11.json) · [固定标签](https://github.com/WeiR-h/moonmatbridge/tree/v0.1.11)
- 使用公开下载的 Windows 程序和 JS 模块重跑三个科研流程，核对结果哈希及四种发行包中的许可材料。[三流程回执](../verification/reports/workflows-public-v0.1.11.json) · [便携演示回执](../verification/reports/workflows-demo-public-v0.1.11.json) · [许可核对](../verification/reports/licenses-public-v0.1.11.json)

`verification/reports` 按版本保存实际验证结果。`v*.json` 包含检查分组、工具版本、源码指纹和 native 哈希；`ci-*` 记录真实执行地址；`octave-*` 记录双向互操作；`mooncakes-*`、`public-downloads-*`、`workflows-public-*` 记录公开消费；`licenses-*` 校验发行包许可。测试数量与覆盖率取自实际报告，不在此固定维护。

兼容范围包括 MAT Level 5 基本类 1—15、递归混合数据、字符存储单位和显式名称编码、CSC 原始索引及容量。legacy object 提供类名、字段和数据互操作。实际独立消费使用 SciPy/NumPy 与 GNU Octave；工具和具体文件结果见兼容矩阵。

[当前路线](NEXT_RELEASES.md) 与历史记录分开维护；[性能报告](PERFORMANCE.md) 区分固定工具链基线、历史测量和新增功能的测量。当前 0.1.x 保持已有接口与报告格式兼容。

固定版本的检查、打包、发布与独立公开复验见 [版本交付](RELEASING.md)。维护入口核对受测源码与真实 CI，公开复验完成后才更新主分支。

## 本期固定验收基线

固定版本为 **v0.1.10**。源码提交及双平台执行地址见 [CI 回执](../verification/reports/ci-v0.1.10.json)；标签提交、公开渠道和结果见 [公开交付回执](https://github.com/WeiR-h/moonmatbridge/blob/main/verification/reports/distribution-v0.1.10.json)。后续版本不修改这些版本化记录。

从对应 GitHub 发行页或 Mooncakes 获取固定版本，最小消费者与三流程演示入口见上表。性能原始测量保持其原版本，通过来源绑定说明适用范围。后续新增成果按真实完成时间记录。
