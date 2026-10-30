# 版本交付

每版在独立分支提交源代码并推送。先执行 `npm run verify`、`npm run coverage`，记录受测源码提交 S；等待该提交最新的 Windows/Linux CI 及真实 Octave 验证成功。

```powershell
python scripts/release.py check --version V --source-ref S
python scripts/release.py package --version V --source-ref S
python scripts/release.py publish --version V --source-ref S
python scripts/release.py verify-public --version V --source-ref S
```

V 使用实际数字版本。当前检出必须与 V 一致。检查会核对每个受测源文件与 S 的 Git 字节、实际 moonc、两个 CI 平台和科学工具回执。源码、宿主、基准适配器、构建配置、工具链完全一致才可继承旧测量；绑定生成器为 `release_evidence.performance_binding`，代码改变后必须提供新的固定对照。原始报告始终保留其测量版本。

将验证报告提交为证据提交 E，再打包；E 可以在 S 之后，但两者受测源码指纹必须一致。候选包与许可验证通过后才创建 E 的不可变标签。发布默认依次使用 Mooncakes、GitHub；可用 `--channel` 指定单个渠道。已有内容只有哈希完全一致才可复用，发布中断后可按原输入恢复。

公开复验从发布元数据取得资产哈希，独立下载并运行其中的原生/JS 科研流程，不要求本地重建 ZIP 与原发行具有相同时间戳。Mooncakes 包重新安装后检查精确版本、源码及三目标消费者。公开复验通过后另补回执提交，才将分支快进合并到 main。

干净检出先配置固定 SDK、C 编译器与开发依赖，再执行上述检查。临时目录可重建，不依赖原机的辅助脚本或绝对路径。认证仅由现有 gh / MoonBit 配置提供，不能放入版本库和报告。`check --offline` 仅供诊断，不授权发布。
