# 初审意见的技术补充

2026-10-16。原 v0.0.2 申报书将 cell、struct、char、sparse 排除在外，且没有明确兼容终点；该范围说明需要修正。

项目最终交付目标为 **MAT Level 5 公开格式基本类 1–15 的完整数据级读写**：cell、struct、legacy object 的类名及字段、char、CSC sparse、全部标准数值类、logical 和浮点复数，覆盖混合文件及递归嵌套。读取支持大小端与文件级压缩；写入统一为合法、确定性的小端 Level 5，可选择压缩。逐项范围、计划日期、验收门槛及当前未完成项见 [COMPATIBILITY.md](COMPATIBILITY.md)。

v0.0.5 已增加 MoonBit 原生递归 `read_tree` / `write_tree`，并升级 `info`、`roundtrip`、`compress`、`select`。cell、struct、char 不再属于本版的排除类型；legacy object 只保存类名及数据，不执行 MATLAB 类。原数值/CSC API 保持原输入域，明确拒绝容器而不丢弃它们。

[公开混合案例](../examples/mixed/README.md) 含三个 MAT 文件（小端、大端、压缩），每个有 13 个根变量，包含混合 cell、2×2 struct 数组、中文及非 BMP 字符、稀疏矩阵、精确 uint64、logical、复数、空容器和三维数组。案例由 SciPy 独立生成；MoonBit 在原生和 JS 宿主写回后，再由 SciPy 递归核对类型、形状、数值、字段与嵌套关系，并核对 legacy 类名。另覆盖六种字符存储标签的大小端输入；生成器、校验值、复现步骤均在案例目录中。

当前限制如 UTF16 非 BMP 跨工具维度差异、旧名称编码、非规范 CSC、MATLAB 私有 function/opaque/subsystem 扩展均已明确记录。MAT v4 和 HDF5 MAT v7.3 是不同格式，不属于本项目的 Level 5 兼容终点。**实际 MATLAB/Octave 回执尚未完成**，列入 v1.0 必须完成的验收条件；当前独立 SciPy 通过不等于这些外部工具已经实测，更不代表主办方复审通过。

技术证据：[版本记录](../CHANGELOG.md)、[测试与互操作报告](../verification/reports)、[递归实现](../src/tree.mbt)、[独立互操作验证](../scripts/interop.py)。本文件仅作可核验技术补充，报名表及本人申报书由参赛者核对更新后提交。
