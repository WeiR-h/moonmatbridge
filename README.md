# MoonMatBridge v0.0.11

**MoonBit 原生 MAT Level 5 读写与科研数据互操作库。**

MAT 递归 cell/struct/char/legacy object、密集/CSC 稀疏读写、数值编码、zlib/DEFLATE 解压与压缩、JSON/无损快照、NPY 互通和精确差异检查都由 MoonBit 实现。运行核心库和 Windows 命令行程序不需要 MATLAB、Python、SciPy、Node.js 或第三方压缩库。Node.js 仅用于开发脚本与可选 JS 命令行；SciPy/NumPy 仅用作独立兼容性验证。

当前源码版本为 v0.0.11，发布模块名为 `WeiR-h/moonmatbridge`。[v0.0.3](https://github.com/WeiR-h/moonmatbridge/releases/tag/v0.0.3) 完成的五轮核心迭代继续保留，详见 [迭代记录](docs/ITERATIONS-v0.0.3.md)。v0.0.5 补齐的 cell、struct、char 和 legacy object 递归读写继续提供混合文件与独立验证；[最终读写范围与验收终点](docs/COMPATIBILITY.md) 明确全部公开基本类 1–15 的交付目标。

项目定位是把科研数组**连同类型、维度、列优先顺序和复数分量一起保留下来**，让 MoonBit 项目直接交换 MATLAB/Python 数据。

- 以 CSC 存储处理大型稀疏矩阵；只有明确调用 `densify` 才尝试展开，并在分配前检查额度。
- 用 `snapshot` / `restore` 保存原始数值字节、NaN 编码、负零和稀疏容量；普通 JSON 继续用于可读数据交换。
- 用 `diff` 按变量名检查内容与存储元数据，定位变化坐标，忽略原文件的头部描述、压缩形式与大小端；退出码可直接作为 CI 门禁。
- 转换流程支持切片、按轴取样、拼接、整形和轴置换，复制原始字节，保留未处理的稀疏变量。

这些能力共同服务于可复现的科研文件交换；范围比较与已有项目的交集见 [独特性说明](docs/DIFFERENTIATION.md)。

本轮执行记录见 [v0.0.6—v0.0.9 计划与交付索引](docs/NEXT_RELEASES.md)，实测结果见 [性能方法与报告](docs/PERFORMANCE.md)。自定工程目标与官方验收分别记录。

v0.0.6 新增 [15 个基本类的独立读写矩阵](docs/COMPATIBILITY_MATRIX.md)、真实 GNU Octave v6/v7 双向验证入口，以及 [同机性能对照方法](docs/PERFORMANCE.md)。运行报告分别记录已经验证的行为和未关闭的兼容缺口。

v0.0.7 将密集、CSC 与混合树写入统一到预检尺寸的固定缓冲，避免逐层复制；完整输入验证后才分配主要输出。性能结果按宿主与场景分别记录。

v0.0.8 新增 `read_selected`、`inspect_roots` 和 `roots` 命令；未选变量仍执行完整验证，减少其数据树和负载分配。空选择也不会跳过校验。输入仍整体驻留内存，压缩根变量仍需有界解压。

v0.0.9 冻结 API，提供 [三个完整科研流程](docs/SCIENTIFIC_WORKFLOWS.md) 与便携包一键演示，扩大全部基本类的 global 标记交叉验证，并整理 [复审技术附件](docs/REVIEW_EVIDENCE-v0.0.9.md)。完整标准变体和 MATLAB 运行仍有未完成项，保持 0.x。

本轮性能结果保留未达项：v0.0.8 原生选择读取提速约 14.2 倍，峰值下降 38.3%，仍未达到自定 40% 内存目标；JS 对应约 10.3 倍和 48.1%。四组写入目标通过，完整固定场景未发现超过 10% 的退化；原始样本与首轮退化记录均保留。

v0.0.11 为本轮验收交付版，运行时 API 保持兼容。当前三目标各 69 项核心测试；新增 50 项最小兼容行为及写回检查。验证过程记录逐文件指纹并检查源码没有变化，四类发行附件均附许可证与参考说明。验收入口见 [验收索引](docs/ACCEPTANCE.md)；初审已通过（参赛者提供通知），最终验收待提交和正式回执。

## 支持范围

| 能力 | v0.0.11 |
| --- | --- |
| MAT Level 5 读取 | 小端、大端；标准标签与小数据标签；多变量 |
| 压缩读取 | `miCOMPRESSED`；MoonBit 解码 stored/fixed/dynamic DEFLATE，验证 Adler-32 |
| MAT 写入 | 确定性的未压缩/压缩小端文件，固定创建描述，不嵌入时间戳 |
| 递归混合类型 | cell、struct 数组、char、legacy object（类名与字段数据）；多维、空数组和交叉嵌套 |
| 字符 | 六种存储标签；中文、非 BMP；保留编码及原始存储单位，大小端读取 |
| CSC 稀疏 | 二维 double、logical、complex double；混合文件、容量保留、显式密集转换 |
| 数值类型 | float32/64；有符号、无符号 int8/16/32/64；logical |
| 复数 | float32、float64 的实部与虚部分开保留 |
| 形状 | 标量 `[1,1]`、行/列向量、多维和空数组，保持列优先存储 |
| 数据保真 | 同存储类型的 MAT 往返保留原始 IEEE 字节、NaN payload、负零和精确 64 位整数 |
| JSON 互通 | `moonmatbridge/1` 严格字段；64 位整数使用十进制字符串 |
| NumPy 互通 | 导出 NPY v1.0；读取 NPY 1/2/3，大小端与 C/Fortran 顺序，复数交错编码 |
| 数组处理 | 保留原始字节的切片、按轴取样、拼接、reshape、轴置换；混合文件按名称提取变量 |
| 根目录与按需构造 | `roots` / `inspect_roots` 返回根变量元数据；`read_selected` 保持请求顺序并验证未选变量 |
| 无损快照 | 严格 JSON + 原始十六进制字节；密集/CSC、NaN 编码、负零、容量与全局标记 |
| 科研差异 | 按变量名比较原始字节与元数据；全局样本额度、坐标、实/虚部计数和 CI 退出码 |
| 核心编译目标 | JS、wasm-gc、native 已验证 |
| 命令行 | Windows x64 原生 EXE；可选 Node.js 文件适配器 |

**明确边界：**当前不支持 MATLAB 私有对象扩展（MCOS/opaque）、函数句柄、子系统 workspace、MAT v4、HDF5 MAT v7.3、复数整数、流式读取；NPY 的 object/pickle、结构化、字符串、float16、datetime、NPZ 和含义不明确的 native-endian 描述符。CSC 仅支持 double/logical/complex double；活动行索引必须在每列严格递增，重复或乱序返回错误。`info/roundtrip/compress/select` 使用完整混合树；JSON、NPY、变换、快照和 diff 保持原数值/CSC 输入域。遇到不支持的类别会返回错误，不会静默丢掉变量。变量名限非空 UTF-8，避免 NUL；非 UTF-8 旧名称不在此版支持范围内。MAT 类型与存储类型不同的密集文件会按声明类型恢复，拒绝无法安全转换的值。

混合类型案例：[三个可下载 MAT 文件及复现步骤](examples/mixed/README.md)，含 13 个根变量及嵌套 cell/struct/char/CSC，保留精确 uint64、复数和 legacy 类名。真实 GNU Octave 流程由 CI 执行，实际结果见各版 `verification/reports/octave-v*.json`；MATLAB 执行尚无回执，兼容缺口见读写矩阵。

## 直接运行 Windows 程序

从 [GitHub Releases](https://github.com/WeiR-h/moonmatbridge/releases) 下载并解压对应版本的 `windows-x64.zip`，在解压目录打开 PowerShell：

```powershell
.\moonmat.exe version
.\moonmat.exe sample sample.mat
.\moonmat.exe info sample.mat
.\moonmat.exe roots sample.mat
.\moonmat.exe dump sample.mat sample.json
.\moonmat.exe pack sample.json from-json.mat
.\moonmat.exe npy sample.mat temperature temperature.npy
.\moonmat.exe from-npy temperature.npy temperature from-numpy.mat
.\moonmat.exe select sample.mat subset.mat temperature sample_id
.\moonmat.exe roundtrip sample.mat copy.mat
.\moonmat.exe transform sample.mat examples\transform-plan.json transformed.mat
.\moonmat.exe compress transformed.mat compressed.mat
.\moonmat.exe snapshot compressed.mat archive.json
.\moonmat.exe restore archive.json restored.mat
.\moonmat.exe diff compressed.mat restored.mat equality-report.json
.\moonmat.exe sparsify sample.mat temperature sparse.mat
.\moonmat.exe densify sparse.mat temperature dense.mat
```

输出文件必须是新文件；重复路径会报 `output-exists`，不会覆盖已有数据。正常命令返回 JSON，`version`、`help` 返回文字。错误输出到 stderr，退出码为 1。`diff` 内容相同返回 0，内容变化返回 2，输入或输出错误返回 1；变化是有效比较结果。中文及带空格路径已测试。程序只依赖 Windows 系统自带的 `KERNEL32.dll`、`msvcrt.dll`。

仓库构建后也可以运行：

```powershell
node scripts/cli.mjs info sample.mat
```

JS 适配器只读写文件；格式处理使用编译后的 MoonBit。

## MoonBit API

发布模块名为 [`WeiR-h/moonmatbridge`](https://mooncakes.io/docs/WeiR-h/moonmatbridge@0.0.11)。在已有 MoonBit 项目中安装：

```powershell
moon add WeiR-h/moonmatbridge@0.0.11
```

核心代码在 `src/`，公开接口在 `src/pkg.generated.mbti`。包内示例可直接运行：

```powershell
moon run src/examples/main --target js
moon run src/examples/main --target wasm-gc
moon run src/examples/main --target native
```

消费者的 `moon.pkg` 导入：

```moonbit
import {
  "WeiR-h/moonmatbridge" @mat,
}
```

核心调用示例（所在函数声明 `raise @mat.MatError`）：

```moonbit
let a = @mat.numeric_array(
  "signal", @mat.Float64, [2, 2],
  [Floating(1.0), Floating(2.0), Floating(3.0), Floating(4.0)],
)
let bytes = @mat.write_mat([a])
let file = @mat.read_mat(bytes)
let restored = file.get("signal").unwrap()
let position = restored.index([1, 0]) // 0-based coordinates; result is 1
let value = restored.value(position)
let numpy_bytes = @mat.write_npy(restored)
```

`array.reshape([4, 1])` 保持列优先线性顺序；`array.permute_axes([1, 0])` 转置二维数组，也支持更高维置换。`file.select(["signal"])` 按请求顺序提取变量。NPY 输入使用 `read_npy(bytes, "signal")`；标量转为 `[1,1]`、一维向量转为 `[n,1]`，二维及以上形状保持。

`Value` 区分 `Signed(Int64)`、`Unsigned(UInt64)`、`Floating(Double)`、`Boolean(Bool)`。64 位整数不会经由浮点数传递。`raw_array` 接受规范的小端列优先字节，适合批量桥接及保留 NaN 的内部编码。公开数组字段可被调用方构造，写入时会重新校验形状与载荷。

参见 [API 说明](docs/API.md)、[JSON 约定](docs/JSON.md) 和 [格式与资源边界](docs/FORMAT.md)。

混合密集/稀疏文件使用 `read_document` / `write_document`；`read_mat` 保留旧的密集 API，并对稀疏变量明确报错。`document.get(name)` 返回 `Dense(NumericArray)` 或 `Sparse(SparseArray)`。`write_document(variables, compressed=true)` 启用压缩，`compare_documents(left, right)` 返回按名称匹配的精确差异。参见 [科研工作流](docs/RECIPES.md)。

## Python 与 MATLAB 示例

MoonMatBridge 写入的 MAT 可由 SciPy 读取；NPY 可以直接由 NumPy 读取：

```python
import numpy as np
from scipy.io import loadmat, savemat

data = loadmat("sample.mat")
assert int(data["sample_id"][0, 0]) == 9007199254740993
temperature = np.load("temperature.npy", allow_pickle=False)
assert temperature.shape == (2, 3)

# 压缩和未压缩的 dense numeric MAT 都可读入 MoonMatBridge。
savemat("python.mat", {"signal": np.arange(12).reshape(3, 4)}, do_compression=True)
```

仓库提供 [SciPy 示例](examples/python/interop_example.py) 和 [MATLAB 示例](examples/matlab/interop_example.m)。MATLAB 示例是供用户运行的脚本，尚无 MATLAB 实测回执；真实 GNU Octave v6/v7 双向执行结果见对应版本报告，其他兼容证据来自独立 SciPy/NumPy。

## 构建与验证

使用已安装的 MoonBit、Node.js 22+，native 目标还需要 C 编译器。开发验证另外需要 Python 3.12+：

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
npm run check
npm test
npm run build
npm run build:native
npm run verify
npm run package
 npm run verify:registry
```

开发脚本优先使用 `MOON_HOME` / `MOONMAT_MOON`，也能读取忽略提交的 `.local-toolchain.json`，字段为 `moonHome`、`gcc`。Windows C 编译器可以通过 `MOONMAT_GCC` 指定；独立验证 Python 可以通过 `MOONMAT_PYTHON` 指定。不会修改系统 PATH、用户配置或已有项目。

`npm run verify:registry` 创建独立项目，使用固定版本的 `moon add` 下载依赖；禁止本地 workspace/path 替代，核对已下载源码，并在 JS、wasm-gc、native 上验证六个完整消费者场景。示例位于 [examples/registry_consumer](examples/registry_consumer/)。发布时使用 `.moonignore` 的明确文件范围，并通过 `moon package --list` 核对；开发工具、构建输出、个人报名材料及验证工作目录不进入 Mooncakes 包。

本地验证使用 MoonBit `0.1.20260920 (914d7da)`、Node `v24.13.0`、GCC `16.2.0`、Python `3.12.5`、SciPy `1.15.3`、NumPy `2.2.6`。`scripts/verify.mjs` 执行三目标测试、直接示例、构建、压缩差分测试和真实文件互通，并记录源文件指纹。

- 68 项 MoonBit 测试（v0.0.9 基准记录；当前数量以对应版本报告为准），各在 JS / wasm-gc / native 执行一次。
- 62 项独立 SciPy/NumPy 验证分组：21 个密集科研数组、两宿主各 72 个 NPY 导入文件，以及递归混合类型、六种字符存储标签、稀疏、压缩写入、转换流程、快照、精确差异和失败原子性。
- 704 个 zlib 解压对照流、2,072 个截断输入检查，以及 44 个 MoonBit 压缩输出的独立解码检查。

报告位于 [verification/reports](verification/reports/)。这些报告是本地构建与互通证据。[GitHub Actions](https://github.com/WeiR-h/moonmatbridge/actions) 另外执行完整 Linux 科研互通验证并保存报告。各版本公开下载核对以对应发布报告为准；赛事提交、主办方验收及获奖仍需独立确认。报名所需个人材料及本人申报书见 [报名清单](docs/HACKATHON_REGISTRATION.md)。

## 许可与后续

Apache-2.0，详见 [LICENSE](LICENSE)、[NOTICE](NOTICE)、[第三方与参考来源](THIRD_PARTY.md)。实现由 AI 辅助完成；关键格式逻辑可在 MoonBit 源码中直接审查，使用独立实现做验证。

后续优先评估结构化科研数据与扫描/流式接口。当前无损快照保存数组内容和存储元数据，不承诺恢复原始 MAT 头部或压缩字节；精确差异不提供浮点容差比较。各版本的实现范围与验证证据见 [CHANGELOG](CHANGELOG.md)。
