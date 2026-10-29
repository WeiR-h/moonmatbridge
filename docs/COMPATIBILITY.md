# MAT Level 5 数据范围与兼容性

## 数据级读写范围

MoonMatBridge 以公开 MAT Level 5 基本类 **1—15** 的数据级读写为稳定范围，覆盖递归混合文件。写入生成确定性的小端文件；读取支持大小端及压缩、未压缩文件。兼容对象为名称、类型、形状、字段顺序、递归关系、全局标记及有效数据，文件描述与压缩布局规范化。

| 类编号 | 数据范围 |
| --- | --- |
| 1 cell | 多维、空数组、异构递归元素 |
| 2 struct | 标量与多维数组、字段表、字段顺序、空结构与递归数据 |
| 3 legacy object | 类名、字段、形状与递归值的数据级存储 |
| 4 char | miINT8、UINT8、UINT16、UTF8、UTF16、UTF32；空数组、多维及非 BMP |
| 5 sparse | 二维 CSC double、logical、complex double；原始索引顺序、重复槽位及容量 |
| 6—15 numeric | double、single、有符号及无符号 8/16/32/64 位整数、logical 标记、浮点复数 |

容器内匿名矩阵、小数据标签、标准标签及文件级压缩均纳入验证。数值同存储类型保留原始 IEEE 位、NaN payload、负零与精确整数；跨存储类型执行检查转换，无法无损表示时明确失败。logical 规范化为 0/1。

## 字符、名称与稀疏存储

UTF8 以 Unicode scalar 数计维度，UINT16/UTF16 以 16 位存储单位计维度（包括代理项），UTF32 保留合法 scalar。真实 Octave 非 BMP 生产案例及原始文件见 [Unicode 案例](../examples/unicode/README.md)：`科研🌙` 使用四个 UTF16 单位，两种宿主读写后由 Octave 再次消费核对。

名称默认严格 UTF-8；可显式指定 Latin1，覆盖变量名、字段名与 legacy 类名，不自动猜测编码。比较和快照保存解码后的名称文本，恢复旧字节编码时明确使用相同写出策略，详见 [名称编码](NAME_ENCODING.md)。

CSC 保留活动索引顺序、重复项、未用槽位及 nzmax；`is_canonical()` 单独判断排序与重复状态。显式 densify 按原存储顺序累加重复数值，复数分量分别处理，logical 使用逻辑或。

## 独立证据与生产者差异

- 基本类、混合文件、大小端、压缩、空数组、多维、global 与字段顺序由独立 SciPy/NumPy、格式检查及三目标回归共同验证。
- 真实 GNU Octave 执行 v6/v7 生产、MoonBit 读写、Octave 消费输出，以及分块根目录和选择读取；具体版本、日志和哈希见各版 octave 回执。
- 四个固定 Octave 8.4 特例保留原始文件及逐项诊断：短字符矩阵声明多出四个字节；logical CSC 使用普通数组类标记。各工具是否容忍这些文件单独记录，不能把容忍畸形文件等同于标准符合性。分析见 producer-variants 回执。
- legacy object 的数据由独立工具核对；类执行和 MATLAB 私有运行时恢复不属于数据接口。MATLAB 工具本身的执行结论仅在有真实回执时记录。

## 接口额度与格式边界

内存接口默认输入、输出及累计展开各 64 MiB；文件数据源默认输入、累计展开各 1 GiB，所选规范 MAT 体积 64 MiB，元数据 8 MiB，块 1 MiB。各接口独立执行额度；这些值不等于进程峰值内存。未选变量仍完整校验，详情见 [文件数据源](SOURCES.md)。

MAT v4、HDF5 MAT v7.3、私有 function/opaque/MCOS 与 subsystem workspace 使用其他格式或运行时机制；流式写入、多 GiB 与 NPY object/pickle 分别规划。legacy mxOBJECT 数据支持不执行类方法。

## 稳定发行门槛

全部公开基本类及已知标准变体须有独立案例；任何未解决或未判定的标准项都阻止稳定发行。三目标、真实工具、资源边界、性能及公开包消费通过后才发布稳定版本，日期不替代完成条件。当前路线见 [开发记录](NEXT_RELEASES.md)，历史报告保持原样。

证据入口：[兼容矩阵](COMPATIBILITY_MATRIX.md)、[混合案例](../examples/mixed/README.md)、[科研流程](SCIENTIFIC_WORKFLOWS.md)、[验证报告](../verification/reports)。规范参考：[MathWorks MAT-File Format](https://www.mathworks.com/help/pdf_doc/matlab/matfile_format.pdf)、[SciPy Level 5 实现](https://github.com/scipy/scipy/tree/v1.15.3/scipy/io/matlab)。
