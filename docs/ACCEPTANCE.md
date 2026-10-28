# MoonMatBridge v0.0.11 验收索引

本轮保持 MAT Level 5 公开基本类及递归混合数据级读写方向。报名初审通过依据参赛者提供的通知记录；最终验收材料尚待提交和正式回执。

## 安装和复现

- [Mooncakes 0.0.11](https://mooncakes.io/docs/WeiR-h/moonmatbridge@0.0.11)：`moon add WeiR-h/moonmatbridge@0.0.11`。
- [固定发行资产](https://github.com/WeiR-h/moonmatbridge/releases/tag/v0.0.11)：解压 Windows 包，运行 `powershell -NoProfile -ExecutionPolicy Bypass -File examples/workflows/demo.ps1`。
- [三个科研流程](SCIENTIFIC_WORKFLOWS.md)：混合实验归档、稀疏仿真交换、NumPy 转换和精确差异。
- [兼容矩阵](COMPATIBILITY_MATRIX.md)和[最小案例](../examples/compatibility/README.md)保留成功行为与未完成项。

## 证据

`verification/reports` 中对应 v0.0.11 的报告分别记录三目标、基本类矩阵、兼容缺口、真实 Octave、公开 Mooncakes 消费者、GitHub 下载、三个科研流程、许可证、源码快照和最终交付。报告绑定实际版本、源码指纹、工具环境及文件哈希；CI 报告给出真实执行地址和提交。

三目标核心测试各 69 项；15 类混合往返 16 组；最小兼容案例行为和写回 50 项；Octave v6/v7 双向流程 8 组；三个科研场景在 native、JS 共 6 组。本地验证、公开复验与主办方验收分别记录。

验收 CI 固定官方编译器 `moonc 0.10.14+7d59c7ec9`，与本地验收工具链一致。源码快照检查覆盖自动生成的接口文件；编译器升级需要重新核验，不能沿用验收指纹。

## 质量、许可和边界

核心解析、压缩、转换和核验均为 MoonBit 实现；宿主负责文件及进程接口。Apache-2.0，发行包附 LICENSE、NOTICE 和 THIRD_PARTY.md，并校验其与仓库原件一致。参赛者应能解释资源预算、递归混合模型、字节保真及独立验证方法。

Unicode 生产者维度、非规范 CSC、旧编码名称及 MATLAB 类行为仍有未完成或未验证项，完整兼容终点不缩减。未有 MATLAB 实测回执时保持明确说明。性能只引用经过生产代码一致性检查的历史测量；没有新增实测则不宣称新加速。原 native 选择读取 40% 内存改善目标仍未达。

完整兼容条件未全部通过前保持 0.x。后续混合树 diff、快照及性能增强不计作本次已完成成果。
