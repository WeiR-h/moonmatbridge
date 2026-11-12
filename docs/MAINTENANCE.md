# 工具链兼容性维护

2026-11-12 核对官方稳定下载渠道后，当前主分支固定使用以下工具链。官方安装入口为 [MoonBit 下载页](https://www.moonbitlang.com/download/)，Windows/Linux SDK 及标准库地址和 SHA-256 记录于 [toolchain.lock.json](../toolchain.lock.json)。工具链仅安装到项目的 `.local-tools`。

```text
moon 0.1.20261104 (940aa18 2026-11-04)
moonc v0.10.20+65efd5b93 (2026-11-05)
moonrun 0.1.20261104 (940aa18 2026-11-04)
Feature flags enabled: rr_moon_mod,rr_moon_pkg
```

## 兼容性适配

- 将 27 处类型派生声明迁移为 `#derive(...)`，保持原有类型、派生能力和公共调用。
- JS 导出边界用 `FixedArray[String]` 接收普通 JavaScript 数组，转换后调用原有 `Array[String]` 接口。六个选择导出的名称、顺序、数值、重复名称和缺失名称行为均有直接宿主回归。实现不依赖 MoonBit Array 的私有布局。
- 接口对照识别编译器对整数和标准 Json 的等价打印形式，并继续核对函数、结构、枚举、错误及派生声明。
- 当前源码最低编译器为 moonc 0.10.20。v0.1.10、v0.1.11 的发行标签、归档和历史报告保持发布时内容；v0.1.12 交付当前工具链适配；v0.1.11 的核心与 interchange 消费样例保留新工具链兼容回归。

## 从干净检出复现

需要 Node.js 22+、Python 3.12+ 和本机 C 编译器。Windows 使用 MSVC 与 Windows SDK，Linux 使用 C 编译器。安装方式与依赖见 [README](../README.md)。

```sh
python scripts/setup-toolchain.py --configure
# Windows 另外执行 python scripts/setup-msvc.py --configure
python -m pip install -r requirements-dev.txt
node scripts/moon.mjs version --all
python scripts/maintenance-check.py --published 0.1.12
```

Linux 安装 GNU Octave 后执行：

```sh
python scripts/maintenance-check.py --published 0.1.12 --octave
```

维护入口顺序执行三目标检查、测试、构建、核心示例、SciPy/NumPy、宿主异常路径、三个科研流程、源码行覆盖及独立公开消费者。`--octave` 必须找到并真实执行 GNU Octave。未安装 Octave 的 Windows 本机结果与 Linux 实际执行回执分别记录。

每次运行保存在 `verification/local/maintenance/<运行编号>/`，包含 `maintenance.json`、各命令完整日志和新生成报告。退出码非零表示本轮未通过。入口会恢复原有报告字节。CI 分别执行相同的底层命令，并上传当前检出的新报告，保留原有发行核验入口所需的构件结构。原性能数据继续对应原工具链，本次维护不重新标注历史性能测量。

持续验证入口：[Windows/Linux CI](../.github/workflows/ci.yml)。实际执行结果见对应提交的 Actions 日志和同名构件。
