# Spec Delta

## MODIFIED Requirements

### Requirement: Dashboard and logs privacy
服务端 SHALL 提供最多十条置顶重点、本人私人备注、每日唯一草稿/提交/修订/已读评语，并提供管理范围内已提交日报的阅读人员清单查询；禁止上级读取草稿与备注。时间区间 SHALL 以上海业务日期、周一起算。阅读清单 SHALL 仅返回完成展示所必需的读者身份和时间字段。

#### Scenario: Superior views employee
- **WHEN** 范围内上级查看员工日志
- **THEN** 只返回已提交版本，私人草稿及备注不返回。

#### Scenario: Authorized reader list
- **WHEN** 管理者查询范围内已提交日报的阅读清单
- **THEN** 服务端返回分页清单和阅读时间；无记录返回空清单，不伪造未读结论。

#### Scenario: Draft or forbidden log reader list
- **WHEN** 请求草稿或范围外日志的阅读清单
- **THEN** 服务端拒绝且不泄露日志或读者信息。

### Requirement: Task dispatch and lifecycle
任务 SHALL 要求名称、截止时间、一名主负责人及有效派发资格，支持协作人、附件、幂等键和事件时间线。列表 SHALL 不返回完成情况字段，关键变更 SHALL 审核后生效；退回补充 SHALL 经权限、当前阶段和版本校验，并记录原因、事件和通知。

#### Scenario: Duplicate or unauthorized dispatch
- **WHEN** 重放相同幂等请求或无资格直接调用
- **THEN** 返回同一任务或权限拒绝，同键不同内容返回冲突。

#### Scenario: Valid return-for-supplement
- **WHEN** 有权限的派发者在允许验收阶段提交当前版本和非空退回原因
- **THEN** 服务端原子记录退回事件、更新任务阶段、发送去重通知并返回新版本。

#### Scenario: Invalid or stale return
- **WHEN** 无权限、当前阶段不允许、原因为空或版本已过期
- **THEN** 服务端拒绝操作且不写入部分任务状态或事件。

### Requirement: DeepSeek jobs and maps
AI SHALL 由服务端 DeepSeek 生成带来源草稿，支持流式、超时重试、取消、日预算、用量统计和输出校验；用户可在版本校验下编辑建议并维护地图关系，确认后才经过正常派发流程创建任务。AI 作业范围 SHALL 与当前 Actor 的组织权限取交集；确认任务 SHALL 原子校验 job/output 版本、来源权限和幂等任务创建。

#### Scenario: Provider unavailable or injected log text
- **WHEN** DeepSeek 失败或日志含指令
- **THEN** 基础业务继续运行，AI 不直接写业务且不扩大数据范围。

#### Scenario: Scope is within authorization
- **WHEN** 用户选择当前角色允许的个人或管理范围
- **THEN** AI 输入只包含该范围内的已提交日志、任务和重点，客户端不能扩大范围。

#### Scenario: Scope exceeds authorization
- **WHEN** 用户请求超出当前组织范围的人员或对象
- **THEN** 服务端拒绝或安全收窄请求，不向模型发送越权或敏感数据。

#### Scenario: Stale AI confirmation
- **WHEN** job 在客户端读取后已被编辑或来源权限发生变化
- **THEN** 确认返回版本冲突或权限错误，不创建任务、不写部分审计且保留用户输入。

#### Scenario: Idempotent AI confirmation retry
- **WHEN** 相同幂等键和相同载荷重复确认，或相同幂等键携带不同载荷
- **THEN** 前者返回同一任务，后者返回幂等冲突，数据库最多产生一个任务。

## ADDED Requirements

### Requirement: Feedback contract
服务端 MUST 为意见反馈提供经过认证的数据范围契约，覆盖提交、本人查询和处理进度；附件、状态、分页、错误和保留期限 MUST 在公开 OpenAPI 中明确。

#### Scenario: Feedback resource is requested
- **WHEN** Flutter 请求反馈列表或反馈详情
- **THEN** 服务端提供已定案的路径和响应，或客户端在契约定案前不发送未实现的反馈路径请求。

#### Scenario: Unauthorized feedback access
- **WHEN** 用户读取其他用户的反馈或提交无效内容
- **THEN** 服务端拒绝请求并返回统一错误，不泄露反馈正文或附件。
