# MoonMatBridge v0.1.4

write_tree_to 增加 compressed 参数，编码块直接进入有界 DEFLATE，按根生成 zlib 并回填长度。输出不受短写与宿主块边界影响。两个宿主 compress 使用新路径，旧内存接口保持可用。独立 Python zlib / SciPy、三目标单元测试及真实 Octave 交叉验证输出。
