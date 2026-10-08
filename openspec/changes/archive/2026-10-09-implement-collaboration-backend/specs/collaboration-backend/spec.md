## ADDED Requirements

### Requirement: Authentication and organization scope
服务端 SHALL 注册仅员工、拒绝角色注入、校验唯一手机号并等待归属确认；初始化管理员无默认密码且首次改密。每次读取、修改、导出和 AI 请求 SHALL 校验公司与当前组织范围。

#### Scenario: Pending user and forged role
- **WHEN** 注册指定管理员或待确认用户读取业务
- **THEN** 请求被拒绝，普通合法注册保持待确认员工。

#### Scenario: Transfer or disable
- **WHEN** 审核通过调岗或停用
- **THEN** 既有会话下一次请求应用新范围或被拒绝。

### Requirement: Candidate revisions and independent review
关键修改 SHALL 保持旧版直到团队、部门、公司复核完成，禁止自审、要求驳回原因和版本校验，记录审计。任务复核策略 SHALL 允许管理员申请配置团队及部门复核层级，策略自身通过独立审核后生效且不能关闭公司独立复核。员工复核职责申请 SHALL 由独立管理员审批且不改变员工角色或业务读取范围。

#### Scenario: No independent reviewer
- **WHEN** 无独立公司复核人提交正式修改
- **THEN** 修改保持待审且旧值仍生效。

#### Scenario: Conflict and self review
- **WHEN** 申请人自审或最终通过时版本已变化
- **THEN** 拒绝请求且不覆盖生效内容。

#### Scenario: Review policy change
- **WHEN** 管理员申请变更任务复核层级
- **THEN** 旧策略继续生效直到独立审核通过，新策略仍要求公司独立复核。

### Requirement: Dashboard and logs privacy
服务端 SHALL 提供最多十条置顶重点、本人私人备注、每日唯一草稿/提交/修订/已读评语，禁止上级读取草稿与备注。时间区间 SHALL 以上海业务日期、周一起算。

#### Scenario: Superior views employee
- **WHEN** 范围内上级查看员工日志
- **THEN** 只返回已提交版本，私人草稿及备注不返回。

### Requirement: Task dispatch and lifecycle
任务 SHALL 要求名称、截止时间、一名主负责人及有效派发资格，支持协作人、附件、幂等键和事件时间线。列表 SHALL 不返回完成情况字段，关键变更 SHALL 审核后生效。

#### Scenario: Duplicate or unauthorized dispatch
- **WHEN** 重放相同幂等请求或无资格直接调用
- **THEN** 返回同一任务或权限拒绝，同键不同内容返回冲突。

### Requirement: Notifications and analytics
事务 outbox SHALL 最终投递站内消息并去重提醒，SSE 支持序号重放，统计和 CSV 导出 SHALL 共享详情范围及说明分母。

#### Scenario: Cross scope export
- **WHEN** 员工导出统计和日志
- **THEN** 结果只包含本人授权数据，不能通过 ownerId 越权。

### Requirement: DeepSeek jobs and maps
AI SHALL 由服务端 DeepSeek 生成带来源草稿，支持流式、超时重试、取消、日预算、用量统计和输出校验；用户可在版本校验下编辑建议并维护地图关系，确认后才经过正常派发流程创建任务。

#### Scenario: Provider unavailable or injected log text
- **WHEN** DeepSeek 失败或日志含指令
- **THEN** 基础业务继续运行，AI 不直接写业务且不扩大数据范围。

### Requirement: Shared contract and verified deployment
Android 和 Web SHALL 使用同一 REST/OpenAPI 契约，服务 SHALL 包含迁移、种子、环境示例、部署说明及真实 PostgreSQL/Redis 集成测试。

#### Scenario: Invalid request
- **WHEN** 双端提交缺字段、过期版本或无效会话
- **THEN** 同样返回明确状态码、错误码和 traceId。
