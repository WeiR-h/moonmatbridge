# 真实 UTF16 非 BMP 案例

本目录的混合文件来自 GNU Octave 8.4.0 的实际生产与双向验证，保留原始文件字节。变量 `unicode_title` 为 `科研🌙`，UTF16 存储维度为 `[1,4]`，对应四个存储单位与三个 Unicode scalar。

来源、提交与 SHA-256 见 unicode-manifest.json；完整执行回执见 verification/reports/octave-v0.0.21.json。生成器为 examples/octave/produce.m，两种宿主的输出由真实 Octave 消费核对。

```powershell
.\moonmat.exe roots octave-utf16-nonbmp.mat
.\moonmat.exe select octave-utf16-nonbmp.mat unicode-only.mat unicode_title
.\moonmat.exe snapshot-tree unicode-only.mat unicode.json
.\moonmat.exe restore-tree unicode.json restored.mat
.\moonmat.exe diff-tree unicode-only.mat restored.mat report.json
```

UTF8 案例按 scalar 数计维度，UINT16/UTF16 按 16 位单位计维度；读写保留存储标签和单位，不自动展平或重编码字符数组。上述执行属于 Octave 证据。
