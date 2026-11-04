# Issue #63 实施与验收记录

日期：2026-11-04。实现分支 `feature/63-home-daily-todos`，检查基线 `05d6c25`。用户已批准实施，功能代码不依赖未合并的 #55/#57/#59/#61/#62。本记录区分本批定向通过与整库发布验收；不宣称已部署、已合并或整库全绿。

## 已实现

- 底栏首页/公司更名，保留 `/dashboard`、`/view` 路由及旧个人重点/日志数据；首页只保留事件纪、任务看板摘要和每日事项。
- 任务看板以 received-card 参与人范围取数，摘要2条，完整页30条分页；全部参与者和参与派发者可见，不混入管理范围内的其他任务。兼容 labels/label。
- personaltodo 分层模块、V26迁移、严格输入校验、本人CRUD和月历计数、版本冲突及24小时幂等重放。无任务/日志/AI关联。
- Flutter 独立数据类型、Repository、会话状态、月历、表单、删除确认、完成/恢复；不确定响应保留原请求，冲突需明确处理，切换账号清除旧数据。

## 验证证据

Windows，Flutter SDK `D:\flutter`，Java 21.0.8，Maven 3.9.9，Docker PostgreSQL16。数据容器均随机命名、动态端口，测试结束清理；未修改共享服务。命令的完整日志保留在忽略目录 output。

| 检查 | 结果与范围 |
|---|---|
| `openspec.cmd validate --all --strict` | 46通过、0失败 |
| `flutter analyze --no-pub` | 无问题，退出0 |
| `flutter test --no-pub test/personal_todos_test.dart test/home_daily_todos_visual_test.dart test/task_display_test.dart --reporter expanded` | 25通过，退出0；账号切换、失败重试、日期、首页结构与四种宽度×两种字号 |
| Maven `-Dtest=PersonalTodoIntegrationTest,TodoDraftTest,TodoMigrationUpgradeTest,TaskQueryServiceTest,TaskDispatchIntegrationTest test` | 隔离数据环境47通过，退出0；其中todo 12、任务35；受影响头参数变更后 PersonalTodoIntegrationTest 再验7通过 |
| `flutter build apk --debug --no-pub --dart-define=USE_MOCK=false` | 构建成功，退出0；首次SQLite下载超时，改从同一官方Release获取、按sqlite3包提供的SHA256验证缓存后成功 |
| `powershell -ExecutionPolicy Bypass -File scripts/test-home-todos-live.ps1` | 退出0，1条系统链路通过；`output/workpanel-home-live-00e3b1904c/flutter.log`；页面新增/完成/删除、重登读取、跨日/恢复、他人读写拒绝、A/B各读12条任务与非参与者空列表；使用独立服务和数据库，不替代Android设备验收 |

后端定向测试覆盖正常新增、详情、月计数、完成/恢复、跨日修改、删除、删除后原键重试、非法日期/字段、越权（同公司同事/上级/管理员/创始人/跨公司）、待确认和停用账号、并发同键仅创建一次、同版本仅一个成功、分页第11/12条、V23→V26保留用户。任务测试覆盖两名参与者各读12条、非参与者不可见、本人派发并参与可见、管理范围不混入、生命周期顺序及候选审批。

非功能一（安全/隐私）：上述HTTP越权和账号切换用例通过；未接入通用审计正文、AI或组织导出。非功能二（可靠性）：同键重放、同键异参、并发版本冲突、客户端失败保留输入与原键通过。可用性：320/360/390/480dp ×1/1.5字体无布局异常，独立新增按钮与派发按钮、状态文字及日期语义标签已实现；TalkBack和系统键盘仍需设备验证。

实际Flutter截图：[首页内容](../../../mobile/docs/screenshots/home-daily-todos.png)。截图由测试宿主渲染真实组件，使用明确的合成数据；宿主未绘制正式底栏。HTML原型测试不是Flutter或后端证明。

## 整库失败及对照

- 必需命令 `powershell -ExecutionPolicy Bypass -File scripts/test-backend.ps1` 已运行，退出1：455测试、51失败、2错误；日志 `output/home-backend.log`。失败涉及旧审批契约、AI执行等待、日志提交日期、任务时间线等，不能报告为通过。
- 在未修改的 `05d6c25` 独立检出中复跑 BackendIntegrationTest、TaskComponentsTest：32测试、7失败、1错误，复现审批版本、任务响应、日志窗口/范围、AI记忆及时间线断言问题。此对照仅证明这些失败已有，未对所有51项逐一归因。
- Flutter完整Mock模式：314通过、3跳过、32失败（含旧标签选择器超时）；默认HTTP模式：311通过、3跳过、42失败。见 `output/home-flutter-full.log`、`output/home-flutter-default.log`。两种模式存在不同测试夹具要求，整库均未达发布标准。
- 主线同条件复验五个UI文件：15通过、12失败，复现AI地图、AI工作台、旧截图用例、demo中的AI断言；导航旧名称断言已随需求更新，curated_ui_assets定向通过。没有把所有其他失败归为历史问题。

## 发布前待办

1. #55/#57/#59/#61/#62仍无非作者审阅；#57/#62迁移重号与#59草稿/不同基线问题仍待处理，未合并或假称已拉取合并结果。
2. V26上线前协调V24/V25最终迁移顺序，不能先发布V26后直接补低版本。迁移回滚说明见 docs/database-schema.md；旧数据不删除。
3. 整库失败与未审阅PR阻止正式合并/发布；本批可作为草稿PR供审阅。未归档OpenSpec或同步为已发布规格。
4. 当前 `adb devices` 无连接设备。Android实机、TalkBack、系统大字号、键盘遮挡和安装验收未执行。APK编译与桌面Flutter真实HTTP链路不替代该项。
5. Issue #63已关联；负责人/Sprint尚待团队分配。断网未确认命令仅保留当前会话，不承诺重启后的离线队列。

## 人工验收步骤

1. 使用已激活账号打开首页：底栏首页/公司名称正确，个人重点和日志卡片不再出现；公司、日志、AI地图、我的及既有深链保持可进入。
2. 给A/B共同派发并通过审核至少12个任务：两人均在任务看板看到完整列表；未参与者及仅管理下属的账号不混入；未批准候选不显示。
3. 新增私人事项，重新登录仍可读取；完成、恢复、改至跨年/闰日、删除。月历计数和选中日列表同步，公司的选日不受影响。
4. 另一账号直接访问/修改该id必须404；空标题/非法日期400。网络结果不确定时重试不重复新增；双客户端版本冲突必须先查看最新版本再确认修改。
