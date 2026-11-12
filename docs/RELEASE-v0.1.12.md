# MoonMatBridge v0.1.12

适配官方 moonc 0.10.20+65efd5b93 及配套标准库，迁移类型派生声明，保持原有公共类型与调用。

修复新版编译器下六个 JavaScript 选择导出的名称数组边界，使用普通 JavaScript 数组时保留请求顺序、非空数据、重复名称和缺失名称诊断。MoonBit 公共调用与 JavaScript 导出名称保持兼容。

Windows/Linux 持续检查覆盖 JS、wasm-gc、native 的检查、构建、测试和示例；完整工具链版本、SciPy/NumPy、真实 Octave 及公开消费者结果随版本保存。新工具链的固定场景测量与历史性能结果分别记录。
