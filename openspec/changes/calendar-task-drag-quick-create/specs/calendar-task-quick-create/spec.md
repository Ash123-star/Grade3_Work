## ADDED Requirements

### Requirement: Long pressing unused day space opens a dated task form

故事 C-06；优先级 P0；范围为“视图→月”的日期单元格空白。作为有创建资格的用户，我希望长按日期空白直接创建该日任务，减少重复选日。月历 SHALL 将任务条、现有操作和空白区分命中；在可用空白有效长按后 SHALL 复用现有创建表单并传入该上海业务日期，有任务的日期也 SHALL 支持剩余空白长按。

#### Scenario: Creating from an empty or partly occupied day
- **WHEN** 用户在没有任务或仍有可用空白的某日单元格长按
- **THEN** 打开同一个既有任务创建表单，明确显示所选业务日期并将截止时间选择器定位该日；用户仍需确认具体时间和其他必填项

#### Scenario: Pressing a task or moving before the threshold
- **WHEN** 用户按在任务条、`+N` 或其他已有操作上，或长按成立前开始滚动
- **THEN** 执行相应任务／已有操作或滚动，不打开快捷创建表单

#### Scenario: Invalid or read-only date surface
- **WHEN** 用户长按月标题、未加载的月份、没有日期含义的占位、只读成员日历，或没有创建资格
- **THEN** 不开放快捷创建，不因日期参数获得新增派发或代他人创建权限

### Requirement: Date prefill preserves form validation and user input

故事 C-06／C-07；优先级 P0；范围为日期预填至创建结果。创建表单 SHALL 仅在首次新建初始化时消费预填日期，不自动提交，不擅自设置开始时间或人员。后续用户修改 SHALL 优先于初始值。创建 SHALL 沿用既有服务端权限、人员／标签范围、必填及时间校验、幂等和审核语义。

#### Scenario: Valid creation using the selected date
- **WHEN** 用户确认该日具体截止时间、填写有效名称及必填人员信息并提交
- **THEN** 使用既有创建接口和幂等键；日期转换为正确带时区时刻；待审返回只提示申请待审，正式任务生效后重新查询月历

#### Scenario: The user edits the date or the form rebuilds
- **WHEN** 用户手动改为其他日期、取消时间选择，或表单重建／服务端校验失败
- **THEN** 不以初始所选日期覆盖已编辑的内容，取消时间选择保留此前有效输入，其他字段不被日期预填清空

#### Scenario: Invalid fields or scope
- **WHEN** 缺少名称、未确认具体截止时间、时间区间无效，或提交越权人员／标签
- **THEN** 本地及服务端按既有契约拒绝，说明可纠正原因，不创建正式任务或伪装为成功

#### Scenario: Cancelled form or repeated submission
- **WHEN** 用户取消创建，或在等待响应时重复点击提交／重试相同请求
- **THEN** 取消不产生创建请求；重复提交遵循既有幂等语义，不产生重复任务或重复创建申请

### Requirement: Quick-create dates are explicit and never silently clamped

故事 C-06／C-07；优先级 P0；范围为日期预填边界、路由输入及没有空白的日期。快捷创建 SHALL 使用服务端 `scheduleConstraints` 的时区、日期范围和版本，首次默认范围与现有选择器窗口一致；越界／无效日期 MUST NOT 静默夹到边界或回退为今天。只对本次创建入口显式传递约束，不修改共享选择器的全局行为；无可用空白时 SHALL 保留既有创建替代入口。

#### Scenario: A prefilled date is outside the allowed window
- **WHEN** 月历所选日或路由参数越界、为无效闰日、格式错误，或服务端约束不可用
- **THEN** 明确反馈并阻止以该值提交，不暗中改为今天／边界日期，不清除用户其他已填内容

#### Scenario: The constraints change while the form is open
- **WHEN** 用户确认时服务端跨年或更新了约束版本
- **THEN** 携带旧约束头的快捷创建被明确拒绝，读回新约束后要求用户重新确认，不自动换日后重提；历史无头创建调用继续兼容

#### Scenario: A dense day has no unused hit area
- **WHEN** 当天任务条及已有操作占满可用区域
- **THEN** 不挤占任务／`+N` 命中区强行触发创建，用户可从既有创建入口带所选日期进入相同表单
