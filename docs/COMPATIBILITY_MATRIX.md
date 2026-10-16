# 可复现的基本类读写矩阵

从 v0.0.6 开始，`scripts/compatibility.py` 用 SciPy 独立生产包含全部基本类的混合文件，再分别通过 native / JS 往返，并由 SciPy 递归核对。不是本库自读自写的自证。

| class | 类型 | 独立混合文件中的案例 |
| --- | --- | --- |
| 1 | cell | 2×2 异构、空多维、cell→struct→cell、struct→cell→sparse |
| 2 | struct | 2×2 数组、字段顺序、空字段表、空多维、递归子值 |
| 3 | legacy object | `ExperimentRecord` 类名、字段、递归值；数据级验证 |
| 4 | char | 中文、非 BMP、字符矩阵和空字符；六种存储标签另见原互操作报告 |
| 5 | sparse | 规范 CSC，与密集数据及容器混合；double/logical/complex 另见原互操作报告 |
| 6 | double | 多维、空多维、复数及精确 IEEE 样例 |
| 7 | single | 多维、空多维、复数及精确 IEEE 样例 |
| 8–15 | int/uint 8/16/32/64 | 每个类型的多维和空多维；精确 uint64 上界另含在混合文件中 |

组合：小端 / 大端 × 未压缩 / 压缩 × native / JS，共 8 组混合文件验证。三目标核心测试与编码、异常输入等验证继续由 `npm run verify` 执行。报告保存文件哈希及明确的剩余问题，见 `verification/reports/compatibility-v*.json`。

## 真实 GNU Octave 验证

`examples/octave` 的生产器与递归比较器使用真实 Octave 进程，生成 v6 / v7 文件，并核对 MoonBit 原生和 JS 的未压缩 / 压缩输出，共 8 组。CI 安装 Octave 后运行 `python scripts/octave-interop.py`；本机没有 Octave 时该命令明确失败，不能生成虚假的成功回执。

Octave 报告保存真实版本、平台、日志、输入和输出哈希，见 `verification/reports/octave-v*.json`。只有实际存在且状态通过的报告才证明该版本的执行结果。它不等于 MATLAB 已执行，也不证明 Octave 未覆盖的 global 标记、legacy 类或所有 Unicode 变体。

## 尚未关闭的问题

| 项目 | 当前状态与处理 |
| --- | --- |
| UTF16 / 非 BMP 的生产者维度差异 | 原始单位保留；继续追踪真实生产文件，不能用 UTF8 样例代替 |
| 非规范 CSC 行顺序或重复项 | 当前拒绝；不把拒绝合法变体记为完整兼容 |
| 非 UTF-8 的旧名称字节 | 当前拒绝；不猜测未知编码后静默改名 |
| legacy object 的 MATLAB 类恢复 | SciPy 数据级验证；实际 MATLAB 类行为未验证 |

最终范围与 v1.0 门槛仍以 [COMPATIBILITY.md](COMPATIBILITY.md) 为准。上述缺口未消除前保持 0.x，不以矩阵的基本类数量冒充所有标准变体都已兼容。
