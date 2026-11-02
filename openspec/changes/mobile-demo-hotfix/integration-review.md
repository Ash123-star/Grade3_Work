# PR #48 合入当前开发分支的审查记录

日期：2026-10-30。来源：PR #48，提交 b704e30a4f1a5d020161d2754ac16392be41b14c。目标：chore/annual-scenario-dataset，合并前 HEAD 为 3e0f324。关联已有 Issue #40。

## 冲突处理

- form_page.dart 保留当前分支的 TaskLabelSelector。它已读取服务端名称、颜色和有效状态，且包含加载失败、空列表、历史失效标签的提交校验；不恢复 PR 中固定颜色的较旧选择器。
- task_interval_http_test.dart 的三条原有区间查询断言与 PR 相同，保留 PR 新增的响应夹具和创建/审核两条断言。
- 原有五个未提交文件单独暂存并在合并后恢复，不纳入本次合并提交。

## 待修复问题

1. **P2：月视图未限定本人任务。** providers.dart 仅修改 datedRecordsProvider；CalendarContent 月模式通过 calendarMonthTasksProvider((ownerId, month)) 请求，而主视图传入的 ownerId 为 null。月视图仍会展示经理有权读取但本人未参与的任务，与日/周视图及新增规格不一致。应将未指定成员的月视图限定为当前会话 ID，同时保留成员日历的显式成员 ID，并覆盖日/周/月请求筛选。
2. **P2：驳回路径仍未使用申请预期版本。** detail_pages.dart 的 action() 为通过操作改用 baseVersion，但驳回调用 edit(item, 'reject') 进入 FormPage；该表单 loadExisting() 使用 item.version，提交也使用 loadedVersion。HTTP review Record 在无 version 字段时默认为 1；因此 expected_version 为 0 或其他非 1 值的申请，驳回仍提交错误 expectedVersion 并被服务端拒绝。应保持表单自身版本冲突检查，并在决定请求中单独传递 original.fields['baseVersion']，覆盖创建申请和高版本修改申请的驳回。

## 验证边界

- 本轮 OpenSpec 严格校验退出 0，44/44 通过。
- 仅进行代码与接口契约审查、合并冲突处理和 Git 差异检查；遵循此前用户要求，未运行测试或编译。PR 原有验证记录是其作者记录，不作为本次合并后的验证结果。
- 本地开发分支集成不表示 PR 已通过发布验收；上述问题未修复，完整测试和设备验证未完成，不合并远程 main。
