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

公开只读复验只核对历史性能来源，不把历史计时转移到当前机器；新候选发布仍要求测量环境一致。重复复验的回执单独存放，保留已经公布的历史文件。

Windows GitHub REST 上传使用本机 HTTPS 直连；如环境要求系统代理，可先设置 `$env:MOONMATBRIDGE_GITHUB_ROUTE="system"`。认证由 gh 获取，只驻留进程内存，禁止认证请求跟随重定向。连接中断后先核对草稿中的名称、大小与 SHA-256，再复用原文件续传；正式发布的资产不可替换。

发布工具默认使用已保存的 WeiR-h 登录，并核对身份及仓库写权限。协作者可在命令前设置 `$env:MOONMATBRIDGE_GITHUB_USER="登录名"`。凭据仅驻留本次进程及子进程环境，全局 gh 活动账号保持原有设置；缺少所选账号时明确失败。

新测量可使用 `python scripts/bind-performance.py --baseline-ref REF --candidate-ref S --core-report CORE.json --file-report FILE.json --write-report WRITE.json`，报告路径指向 verification/reports 中保留的原始文件。绑定核对真实提交、固定场景成员、全部批次与内存样本，不依赖旧版本文件名。运行时及测量范围未改变时继续引用原报告，不重新生成计时。
