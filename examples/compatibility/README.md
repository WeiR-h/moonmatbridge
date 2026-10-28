# 最小兼容案例

由 `python scripts/compatibility-gaps.py` 使用独立 SciPy 和小型 Level 5 单位编码器产生。文件哈希及行为见 manifest.json，各版执行结果在 verification/reports/compatibility-gaps-v*.json。

UTF16 案例保留代理项原始单位，空数组保留多维形状；legacy object 仅验证数据。CSC 乱序、重复项和 Latin1 名称是公开保留的兼容缺口，断言本版拒绝只防止行为漂移，不计作兼容成功。

Octave 原始异常文件继续保留在 ../octave/variants；其真实生产和消费结果由 Octave CI 独立记录。所有案例的规范参考为 MathWorks MAT-file Format。没有 MATLAB 实测时，不把其他工具结果写成 MATLAB 已验证。
