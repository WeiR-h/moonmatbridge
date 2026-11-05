# MoonMatBridge 项目检查索引

**固定验收基线为 v0.1.10。当前公开发行是 v0.1.11。** 两个版本的源码、发行资产和验证回执分别记录。

| 版本 | 源码 | GitHub 发行 | Mooncakes | 验证结果 |
| --- | --- | --- | --- | --- |
| v0.1.10 · 固定基线 | [标签 163d65b](https://github.com/WeiR-h/moonmatbridge/tree/v0.1.10) | [发行页](https://github.com/WeiR-h/moonmatbridge/releases/tag/v0.1.10) | [公开包](https://mooncakes.io/docs/WeiR-h/moonmatbridge@0.1.10) | [Windows/Linux CI](https://github.com/WeiR-h/moonmatbridge/actions/runs/41177075270) · [公开交付回执](https://github.com/WeiR-h/moonmatbridge/blob/858eb7acfe2c4c1aae0d902085a750ce3b7732b6/verification/reports/distribution-v0.1.10.json) |
| v0.1.11 · 当前发行 | [标签 da564f4](https://github.com/WeiR-h/moonmatbridge/tree/v0.1.11) | [发行页](https://github.com/WeiR-h/moonmatbridge/releases/tag/v0.1.11) | [公开包](https://mooncakes.io/docs/WeiR-h/moonmatbridge@0.1.11) | [Windows/Linux CI](https://github.com/WeiR-h/moonmatbridge/actions/runs/41206292702) · [公开交付回执](https://github.com/WeiR-h/moonmatbridge/blob/3e6cd73cf2fc397f40e753fd7f5ef9866e480bf7/verification/reports/distribution-v0.1.11.json) |

## 运行固定基线的示例

下载 [v0.1.10 Windows 便携包](https://github.com/WeiR-h/moonmatbridge/releases/download/v0.1.10/MoonMatBridge-v0.1.10-windows-x64.zip)，解压到路径较短的目录。在含 `moonmat.exe` 的目录中执行以下命令。

```powershell
$results = Join-Path $env:TEMP ('moonmat-demo-' + [guid]::NewGuid().ToString('N'))
powershell -NoProfile -ExecutionPolicy Bypass -File .\examples\workflows\demo.ps1 -OutputDirectory $results
```

终端应显示 `All three workflows passed`。结果目录中的 `demo-receipt.json` 记录命令、退出码和文件哈希，可与 [v0.1.10 公开演示回执](https://github.com/WeiR-h/moonmatbridge/blob/858eb7acfe2c4c1aae0d902085a750ce3b7732b6/verification/reports/workflows-demo-public-v0.1.10.json) 核对。便携包内指南为发布时快照，当前操作步骤以本页为准。

## 免登录复验

从 [当前仓库](https://github.com/WeiR-h/moonmatbridge) 获取源码，在仓库根目录用 Python 3.12+ 执行以下命令。

```sh
python scripts/verify-published.py --version 0.1.10
```

脚本核对 GitHub 标签、发行资产清单和 Mooncakes 包的构建状态及登记校验值，下载四种发行 ZIP 和混合样例并计算 SHA-256。成功时输出 `"status": "passed"`。加 `--windows-demo` 可在 Windows 上执行便携演示，并比对实际输出哈希。安装 Node.js 22+ 后可加 `--node-demo`，用公开 JS 模块核对混合样例中的基本类 1—15。将版本改为 `0.1.11` 可复验当前发行。

只有 Node.js 时，可从固定版发行页下载 [JS ZIP](https://github.com/WeiR-h/moonmatbridge/releases/download/v0.1.10/MoonMatBridge-v0.1.10-js.zip) 和 [混合样例](https://github.com/WeiR-h/moonmatbridge/releases/download/v0.1.10/all-base-classes.mat)，解压 JS ZIP 后执行以下命令。

```sh
node scripts/verify-mixed-sample.mjs ./MoonMatBridge-v0.1.10-js/bridge.mjs ./all-base-classes.mat
```

## 九项核对

| 检查项 | 仓库入口与复现方式 |
| --- | --- |
| MoonBit 主要实现、moonc ≥ 0.10.16 | [源码](https://github.com/WeiR-h/moonmatbridge/tree/v0.1.10/src) · [固定工具链](https://github.com/WeiR-h/moonmatbridge/blob/v0.1.10/toolchain.lock.json)。从源码运行 `python scripts/setup-toolchain.py --configure` 与 `node scripts/toolchain.mjs` 核对实际编译器。 |
| 公开仓库与提交记录 | [GitHub](https://github.com/WeiR-h/moonmatbridge) · [基线提交记录](https://github.com/WeiR-h/moonmatbridge/commits/v0.1.10/) · [版本记录](https://github.com/WeiR-h/moonmatbridge/blob/v0.1.10/CHANGELOG.md) |
| 结构清晰、核心功能可运行 | [API](https://github.com/WeiR-h/moonmatbridge/blob/v0.1.10/docs/API.md) · [兼容矩阵](https://github.com/WeiR-h/moonmatbridge/blob/v0.1.10/docs/COMPATIBILITY_MATRIX.md)。核心包、interchange 和宿主分开维护。 |
| README 包含目标、安装、用法和示例 | [基线 README](https://github.com/WeiR-h/moonmatbridge/blob/v0.1.10/README.md) · [当前运行说明](https://github.com/WeiR-h/moonmatbridge/blob/main/docs/SCIENTIFIC_WORKFLOWS.md) |
| CI 覆盖检查、构建、测试 | [双平台工作流](https://github.com/WeiR-h/moonmatbridge/blob/v0.1.10/.github/workflows/ci.yml) · [验证入口](https://github.com/WeiR-h/moonmatbridge/blob/v0.1.10/scripts/verify.mjs)。Linux 额外执行真实 GNU Octave。 |
| 至少一个可运行最小样例 | [基线 MoonBit 示例](https://github.com/WeiR-h/moonmatbridge/tree/v0.1.10/src/examples/main) · [当前公开包消费者](https://github.com/WeiR-h/moonmatbridge/tree/main/examples/registry_consumer) · 本页便携示例。 |
| 核心路径测试 | [基线测试结果](https://github.com/WeiR-h/moonmatbridge/blob/v0.1.10/verification/reports/v0.1.10.json) · [SciPy/NumPy 验证](https://github.com/WeiR-h/moonmatbridge/blob/v0.1.10/scripts/interop.py) · [Octave 结果](https://github.com/WeiR-h/moonmatbridge/blob/v0.1.10/verification/reports/octave-v0.1.10.json) |
| 发布到 Mooncakes | `moon add WeiR-h/moonmatbridge@0.1.10` · [基线安装回执](https://github.com/WeiR-h/moonmatbridge/blob/858eb7acfe2c4c1aae0d902085a750ce3b7732b6/verification/reports/registry-v0.1.10.json) |
| OSI 开源许可证与第三方说明 | [Apache-2.0](https://github.com/WeiR-h/moonmatbridge/blob/v0.1.10/LICENSE) · [NOTICE](https://github.com/WeiR-h/moonmatbridge/blob/v0.1.10/NOTICE) · [第三方来源](https://github.com/WeiR-h/moonmatbridge/blob/v0.1.10/THIRD_PARTY.md) |

兼容范围包括 MAT Level 5 基本类 1—15、递归混合数据、显式名称编码、字符存储单位和 CSC 原始存储。legacy object 支持类名、字段及数据。独立工具实际运行以 SciPy/NumPy 和 GNU Octave 回执为准。

从当前源码运行 `npm run verify:registry -- --published 0.1.11`，可在独立目录按原样检查、测试和运行 README 的消费者示例。维护者的 [版本交付流程](https://github.com/WeiR-h/moonmatbridge/blob/main/docs/RELEASING.md) 另行绑定源码、性能和发行回执。
