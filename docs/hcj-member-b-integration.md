# HCJ 与成员B接入记录

## 2026-10-21 最新回归结果

前次42项Flutter失败已逐项关闭：Mock配置全量267通过、0失败、1项原有真实stage联调跳过，退出码0；静态检查No issues found，OpenSpec31通过。后端本日139项通过，角色变更旧会话撤销与管理入口401/403审计已实现。详见 `docs/member-b-security-regression.md`。真实页面后端联调及C标签/新任务审核契约仍未完成；以下为修复前历史记录，不代表当前失败状态。本地尚未推送。

## 2026-10-21 修复前核验记录（历史）

用户要求确认无错误后才推送并创建PR。本轮未满足门槛，未推送、未新建PR，未删除或改写失败断言。

- 正确页面回归配置：`dart flutter_tools.snapshot test --no-pub --dart-define=USE_MOCK=true --reporter expanded`，224通过、42失败、1跳过，明确退出1。日志在`output/member-b-prepush-mock-tests.log`。
- 另一次默认真实模式运行225通过、47失败、1跳过，退出1；不将这次配置不同的数字替代Mock页面回归结果。日志在`output/member-b-prepush-tests.log`。
- 失败涵盖任务旧字段/参与人契约、日志Mock修订流程、旧页面入口与控件、布局/截图断言。须逐项确认是实际回归还是HCJ变更导致旧测试失配；尚未逐项归因，不能全称为历史问题或仅测试问题。
- `git diff --check`通过；OpenSpec严格校验31通过。这不能抵消功能测试失败。此前静态检查的2项提示和1项警告未在本轮修复，不能报告分析无问题。
- 后端137项通过是2026-10-19的已提交后端版本证据；本轮没有重跑后端全套或新版Flutter真实服务全链路。

依据用户重新提供的week6分工，B的Web要求明确包括401/403访问记录；该项尚未实现。角色撤销当前阻止管理接口访问，但不撤销整个会话；分工验收中的“旧令牌失效”未完全满足。此前将这些列为可选扩展的说明需以此更正。标签权限仍依用户决定等待C契约，新任务审核联调未完成。认证、组织、审核SPI已有历史验收，不能照搬10月11日材料中的旧缺口为当前缺口。

以origin/HCJ b75f8ce与main dc00e2b为依据，本地lyb合并提交457061a，无文本冲突。用户确认继续使用24小时内申请修订、审核后生效，不使用直接修改。

已接入：修订表单与审核提示；评论parentCommentId和后端parentId双向转换；评论ID与作者保留；下属日志departmentId/search服务端查询并在分页保留；按canWithdraw展示撤回入口、携带version及必填理由；草稿编辑和提交尊重服务端canEdit，避免撤回后绕过窗口。Mock日志修订恢复使用已有审核流程。

2026-10-20契约测试command_http_contract_test：11通过、1失败，退出1。新增回复与撤回测试通过。日志提交失败恢复重试测试改为HCJ“继续草稿”的明确入口draftSource=diary，原正文保留与服务端版本断言不变，通过。唯一失败为HCJ任务转派的新participantIds与既有group/collaborators期望不同，保留失败证据，等待C契约。

Flutter静态分析还报告HCJ已有的两个字符串插值提示和own_profile_page未使用导入；不能称全量检查通过。真实联调启动时发现Docker未运行，启动脚本失败；已尝试启动Docker Desktop，后续须确认就绪并验证服务链路。页面真实验收、完整Mock回归尚未完成，OpenSpec 6.1/6.2未勾选。

接口说明：已提交日志使用POST /logs/{id}/revisions；评论POST /logs/{id}/comments使用text与可选parentId；撤回POST /logs/{id}/withdraw使用version/reason。标签、新任务增删改审核仍等待C，未以旧功能替代验收。未推送本批未验收修改；本地.idea保留且不得提交。
