# 2026 MoonBit 10 月黑客松报名清单

核对日期：2026-10-07。此文件记录报名要求和可核验技术事实，不是项目申报书。当前尚未提交报名，未取得官方提交成功回执。

## 项目资料

| 字段 | 已准备信息 |
| --- | --- |
| 项目名称 | MoonMatBridge |
| GitHub ID | WeiR-h；团队参赛须补全实际队员 ID |
| 项目公开仓库 | https://github.com/WeiR-h/moonmatbridge |
| 下载版本 | https://github.com/WeiR-h/moonmatbridge/releases |
| 提交历史 | https://github.com/WeiR-h/moonmatbridge/commits/main/；已有不少于 10 个实际开发提交 |
| 参赛方向 | 新项目申报；如希望兼顾季度评选，表单选“新项目申报-参与季度评选” |
| 许可和参考 | Apache-2.0，详见 LICENSE、NOTICE 和 THIRD_PARTY.md |

## 需本人完成的资料

[官方报名表](https://bxup9uklfcb.feishu.cn/share/base/form/shrcnWUMlgpbwHaXgzV7HmNhNhg) 要求飞书登录，并填写姓名、国内邮箱、可加微信的电话、所属高校/组织（没有则填“无”），上传身份证正反面和学历/学籍材料，提供银行卡号码和所属分行，并阅读确认[参赛诚信承诺书](https://bxup9uklfcb.feishu.cn/wiki/GKDswxuptiJRcxkzPgZcw1J6nAd)。推荐人和备注为选填。身份证照片可按表单说明添加水印。

请将证件、学历和银行信息直接填写/上传到官方表单，不应放入公开源码仓库。本文没有替任何人作出参赛诚信承诺，也没有保存个人证件或收款信息。

## 本人项目申报书

官方明确要求：“请使用 markdown 格式，长度控制在一页以内，不要使用 AI 编写。”

请参赛者亲自创建 Markdown 文件，涵盖：项目名称、简介、项目方向和通用性、至少 3 个完整使用场景、拟实现核心功能、原创/移植/参考情况、如移植则说明来源及许可证、GitHub 仓库链接。可查看[官方申报书样本](https://bxup9uklfcb.feishu.cn/wiki/Rm3PwCxC7iEwJtkK1xMcYHZkn36)。仓库需不少于 10 个有效提交；空提交、重复提交和无意义拆分不满足该要求。

以下是便于本人核对的技术事实：

- 核心格式逻辑、解压、JSON 和 NPY 互通在 MoonBit 中实现，C/JS 宿主只承担文件和参数传输。科学库仅用于独立验证。
- 支持 MAT Level 5 dense numeric/logical；读压缩，写未压缩；保留形状、类型、列优先顺序、复数分量及精确 64 位整数。
- v0.0.2 支持 primitive NPY 导入/导出、无损 reshape、轴置换和变量选择。NPY scalar/vector 明确提升为 MAT 的二维形状。
- 36 项 MoonBit 测试分别在 JS、wasm-gc、native 通过；35 项 SciPy/NumPy 独立验证分组，含每宿主 72 个 NumPy 生成的 NPY 文件；704 个 zlib 对照流和 2,072 个截断检查。
- 不支持 cell/struct/char/sparse、MAT v4/v7.3、压缩写入和流式处理；NPY 不执行 pickle，也不支持结构化、对象、字符串等数据。
- 实现由 AI 辅助完成，格式依据来自公开规范，没有复制 mat4js/matio/moon-npy 的实现。参加答辩前需本人理解和能解释源码。MATLAB/Octave 的实际执行尚未验证。

## 提交和回执

填写上述个人信息后，上传本人申报书并提交。表单成功后会跳转赛事群页面；按官方要求入群并将昵称改为 GitHub ID。官方公开页面的群入口为 https://work.weixin.qq.com/gm/5b6b92c8677d0555f3fb6a3f1a081399 。

以表单“提交成功”页面和个人已提交记录确认完成；公开仓库、版本下载、自动测试通过均不代表已经报名或获主办方验收。
