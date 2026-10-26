# 成员 B 安全与回归记录（2026-10-21）

## 本批实现

- 组织用户角色审核生效时，在同一事务内撤销该用户所有旧会话；驳回不撤销，普通资料修改不触发角色撤销。
- 管理命名空间认证/权限拒绝的401、403写入 workspace_access_audit。记录操作者（匿名可空）、公司、方法、固定入口分类、状态和追踪ID，不记录令牌、任意URL、查询参数或正文。写入失败保留拒绝响应，并记录不含敏感参数的错误日志。
- 新增 V19__workspace_access_audit.sql，不修改已发布迁移。回退应用时保留审计表和记录；部署前应核对团队新迁移编号有无冲突。
- 经用户授权，公共 BackendIntegrationTest 仅更新角色变更登录夹具：旧令牌401断言后重新登录，原业务断言全部保留。
- Mock 日志对齐真实规则：不允许直接更新已提交内容；修订要求原因及版本；撤回重提保留首次时间；到24小时禁止继续编辑；修订批准时核对申请时版本。Mock结果不代替真实后端验收。

## 验证证据

环境：Windows、JDK21、Maven3.9.11、Docker隔离数据库；Flutter SDK使用仓库现有依赖。

- `powershell -ExecutionPolicy Bypass -File scripts/test-backend.ps1`：139项、0失败、0错误、0跳过，BUILD SUCCESS，退出码0。Flyway V1–V16成功执行。日志：`output/security-regression.log`。
- 构建结束时 Surefire 曾报告 fork JVM 退出等待30秒后被终止；全部测试和最终打包成功。此记录不代表生产服务优雅停机已验收。
- Flutter `test --no-pub --dart-define=USE_MOCK=true test/demo_workflow_test.dart test/command_http_contract_test.dart --reporter expanded`：16项通过，退出码0。日志：`output/log-security-contract-tests.log`。
- Flutter同配置运行 `test/week5_mock_workflow_test.dart`：6项通过，退出码0。日志：`output/week5-mock-regression.log`。
- 定向运行 demo_workflow 与 attachment_assignment_http：13项通过、1项失败，退出码1。附件HTTP协议测试已通过；剩余派发UI测试依赖旧主负责人/协作人表单，与HCJ多参与人表单不符。日志：`output/regression-batch-two.log`。

安全验证覆盖旧会话失效、匿名/越权管理访问留痕及日志窗口；事务可靠性验证覆盖审核版本冲突、未批准不改原文，相关真实HTTP测试包含在139项中。

## Flutter 回归收尾（同日后续，取代上面的中间失败结果）

- 全量命令：`dart flutter_tools.snapshot test --no-pub --dart-define=USE_MOCK=true --reporter expanded`，267通过、0失败、1跳过，退出码0；日志 `output/flutter-regression-final.log`。未新增skip、未删除测试。原有跳过项是 `member_b_real_backend_test.dart`，需要专用stage-demo环境及 `RUN_STAGE_INTEGRATION=1`，不计为真实联调通过。
- `dart flutter_tools.snapshot analyze --no-pub`：No issues found，退出码0；日志 `output/flutter-analysis-final.log`。`openspec.cmd validate --all --strict`：31通过、0失败，退出码0；`git diff --check`通过。
- 原42项失败全部在本次全量中关闭。修复旧任务字段兼容、旧任务参与人摘要、AI人工派发默认紧急程度、统计图字号溢出、小屏筛选弹层滚动、Mock日志窗口/修订及部门作者查询、不存在对象的操作拒绝。
- 测试适配保留了真实HTTP请求字段、幂等重试、权限/版本冲突、加密草稿账号隔离、关联任务和评论回复断言。用独立固定数据替代依赖演示ID；适配新版下拉/日期控件、富文本评论、跨日任务条、显式恢复草稿入口及审核后生效规则。
- 派发UI测试验证新版多参与人字段和附件ID发送至测试HTTP适配器；这不证明当前真实后端已经实现新任务契约。旧单负责人协议测试仍保留。
- 截图覆盖320/360/390/412/480宽度及1.5倍字号；截图输出到忽略目录 `output/flutter-evidence`，人工检查下属日志小屏截图。布局测试通过不等于完整无障碍认证。

## 仍需后续交付验证

- 多参与人、标签和新任务增删改审核依赖C契约，遵循用户选择等待C，不将新字段静默降级为旧单负责人。
- HCJ部门筛选、撤回页面真实服务验收仍待完成；完整Mock配置Flutter回归已通过。
- 2026-10-21 验证结束时尚未提交或推送；2026-10-22 按用户要求整理为阶段提交，关联 Issue #22。本次不创建新 PR，真实联调及 C 契约依赖继续保持未完成。用户 .idea 目录、output 和无关指标文件不纳入提交；实际推送结果以 Git 远端记录为准。

## 原42项失败追溯

以下保留修复前用例名称；当前全量均已通过。与新需求冲突的名称已同步调整，测试未删除；每项最终证据均见 flutter-regression-final.log。

1. [x] attachment_assignment_http_test.dart: actual attachment/collaborator IDs and feedback blocker text use existing supported contracts
2. [x] command_http_contract_test.dart: transfer and reschedule submit complete candidate without changing effective task
3. [x] calendar_agenda_test.dart: page chrome removes title and unused bar, preserves actions and back
4. [x] demo_workflow_test.dart: one shared demo preserves dispatch receive feedback return acceptance archive across users
5. [x] demo_workflow_test.dart: daily log is unique and revisions only apply after full review
6. [x] demo_ui_test.dart: logs use a single independent date and allow member selection
7. [x] attachment_assignment_http_test.dart: dispatch UI sends uploaded IDs and unique collaborators from actual member choices
8. [x] curated_ui_assets_test.dart: semantic badges and dog decorations preserve narrow and scaled navigation
9. [x] demo_ui_test.dart: AI task draft and existing focus editor are prefilled
10. [x] diary_task_links_contract_test.dart: real revision editor cancel preserves links; delete and encrypted reopen preserve remaining array
11. [x] inbox_sync_contract_test.dart: profile counts include late notifications and pending approvals
12. [x] diary_task_links_contract_test.dart: actual multiple association picker renders at360dp text1.5
13. [x] ai_http_workflow_test.dart: human task confirmation retries with stable idempotency and actual active owner
14. [x] read_http_contract_test.dart: historical document displays HTTP version body rather than current content
15. [x] profile_dog_ui_test.dart: profile keeps task management entry with local dog art
16. [x] sunny_design_system_test.dart: semantic roles interpolate colors, geometry and motion
17. [x] member_workspace_contract_test.dart: carried date, clear, picker and category changes remain member scoped
18. [x] read_http_contract_test.dart: actual task events drive one owner or dispatcher action and unknown stays read-only
19. [x] stage3_interaction_test.dart: diary save, invalid hours, offline retry and keyboard preserve dated content
20. [x] week5_mock_workflow_test.dart: Shanghai week includes Sunday and mock business day follows Shanghai across UTC midnight
21. [x] secure_local_state_test.dart: editor restores encrypted draft across disposal; account/date not leaked
22. [x] stage3_interaction_test.dart: review requires a rejection reason and does not show self decisions
23. [x] stage3_supporting_ui_test.dart: acceptance reads actual results and transfer keeps current context
24. [x] week5_mock_workflow_test.dart: public task and log comments support replies; empty, invalid parent and mutations fail
25. [x] stage3_interaction_test.dart: stale diary editor requires explicit reload without losing its draft
26. [x] workflows_test.dart: self review fails and outdated versions are rejected
27. [x] stage3_interaction_test.dart: task has one fixed primary action and more menu contains secondary actions
28. [x] ai_http_workflow_test.dart: map creates actual directed edge and source purpose uses original date/period
29. [x] stage3_supporting_ui_test.dart: new own private note saves and remains hidden on another member focus
30. [x] stage3_supporting_ui_test.dart: failed detail action stays visible by fixed action and missing record recovers safely
31. [x] secure_local_state_test.dart: failed encryption keeps editor input and recovers with explicit save
32. [x] week5_ui_acceptance_test.dart: nine annotated screens have reproducible renders and responsive geometry
33. [x] workflows_test.dart: dispatch fields validate without a completion field
34. [x] week5_ui_acceptance_test.dart: diary row edits directly; detail comments can post and reply
35. [x] tuantuan_screenshot_repair_test.dart: screenshot repairs fit 360.0 scale 1.0 and navigate
36. [x] week5_ui_acceptance_test.dart: small screen task filters scroll and empty search recovers
37. [x] layout_test.dart: all routes fit Size(412.0, 915.0) at scale 1.5
38. [x] week5_ui_acceptance_test.dart: department and author filters combine; calendar opens all daily records
39. [x] tuantuan_screenshot_repair_test.dart: screenshot repairs fit 390.0 scale 1.0 and navigate
40. [x] tuantuan_screenshot_repair_test.dart: screenshot repairs fit 412.0 scale 1.5 and navigate
41. [x] week5_ui_acceptance_test.dart: create diary, save draft, reopen, submit and directly change content
42. [x] tuantuan_screenshot_repair_test.dart: screenshot repairs fit 360.0 scale 1.5 and navigate
