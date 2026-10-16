# 混合类型文件案例

这组文件由 SciPy 1.15.3 / NumPy 2.2.6 独立产生，固定头部描述以便重复生成并核对 SHA-256。产品解析和写回逻辑由 MoonBit 执行。文件清单与校验值见 [manifest.json](manifest.json)，生成与递归比较工具见 [mixed_types.py](../python/mixed_types.py)。

| 文件 | 编码 |
| --- | --- |
| [research-mixed.mat](research-mixed.mat) | 小端、未压缩，SciPy 生成 |
| [research-mixed-compressed.mat](research-mixed-compressed.mat) | 小端、zlib 压缩，SciPy 生成 |
| [research-mixed-big-endian.mat](research-mixed-big-endian.mat) | 独立工具逐元素转为大端，SciPy 再读取确认 |

每个文件含 13 个根变量：精确 uint64 编号、复数、logical、CSC 稀疏矩阵、中文及非 BMP 文本、二维字符矩阵、2×2 混合 cell、2×2 struct 数组、legacy object、空 cell/struct/char 和三维整数数组。cell 内嵌套 struct 与 sparse，struct 字段又嵌套 cell，检查递归关系和列优先字段顺序。

```powershell
.\moonmat.exe info examples\mixed\research-mixed.mat
.\moonmat.exe roundtrip examples\mixed\research-mixed.mat mixed-copy.mat
.\moonmat.exe compress examples\mixed\research-mixed.mat mixed-compressed.mat
.\moonmat.exe select examples\mixed\research-mixed.mat subset.mat measurements experiments title
```

核心库使用 `read_tree` / `write_tree`；JS 接口使用 `inspect_mat` / `roundtrip_mat` / `compress_mat` / `select_mat`。混合树不会经过仅支持数值的 JSON、快照或 NPY 接口。

`npm run verify` 会重复生成三个案例，核对公开案例字节，然后分别通过 Windows 原生和 JS 宿主读写、压缩、选择变量，再用 SciPy 递归比较全部数据、形状、字段顺序和 legacy 类名。另独立验证六种 char 存储标签的大小端输入。

实际 MATLAB/Octave 尚未运行。可在 MATLAB 中调用 [verify_mixed.m](../matlab/verify_mixed.m) 检查原文件与写回文件。legacy object 的 MATLAB 类恢复需要相应类定义；本库只保存类名和字段数据，不执行类构造或方法。
