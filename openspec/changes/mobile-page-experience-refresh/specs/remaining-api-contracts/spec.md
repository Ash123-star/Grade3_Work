## ADDED Requirements

### Requirement: Retire obsolete log mutation endpoints

P0：日志 SHALL 只通过PUT /logs/draft、POST /logs/{id}/submit和PUT /logs/{id}/content写入正文。系统 MUST 删除POST /logs/{id}/read、POST /logs/{id}/revisions和POST /logs/{id}/withdraw及客户端调用，不保留兼容业务处理器；历史阅读数据、正文版本与审核审计不得因此删除。未知日志命令 MUST 在客户端发请求前拒绝，不能落入草稿保存。其他模块仍有效的版本、评论、任务和组织接口 SHALL 按当前规格验证，不能为了迁就旧测试恢复旧行为。

#### Scenario: Removed routes and unchanged historical records
- **WHEN** 已激活用户请求已移除日志接口或通过历史LOG审核候选修改正文
- **THEN** 不执行阅读登记、撤回或审核正文修改，日志正文、首次提交时间、版本、审核、outbox均无新增写入；旧HTTP路由返回404，历史LOG候选仍不可应用

#### Scenario: Recover a failed submission using latest log APIs
- **WHEN** 保存草稿成功但提交失败，作者退出后重新打开同账号同日期日志并重试
- **THEN** 本机加密正文与已确认服务端ID/version保留，读取真实草稿后按当前version保存并提交；未知动作、过期版本、超过三日首次提交及24小时外正文更新不产生部分写入

#### Scenario: Verify current client identity during draft restoration
- **WHEN** 草稿读取或提交期间当前账号会话改变
- **THEN** 旧会话响应不得填充或提交新会话页面，原账号草稿保留且不泄露至新账号

### Requirement: Remaining mobile operations use real server contracts
P1：系统 SHALL 接通现有任务评论及日志回复接口、任务RETURNED事件和授权团队目录，成果反馈 SHALL 支持最多5个本人上传的同公司附件。现有任务评论重复幂等键继续返回DUPLICATE_COMMENT；日志回复保持只追加、同日志父节点及当前读取权限。退回 SHALL 仅允许派发人/管理员在FEEDBACK阶段以当前version和非空原因执行，转为RECEIVED，保留RETURNED事件、审计和outbox。

#### Scenario: Return and resubmit with materials
- **WHEN** 派发人退回待验收任务，参与人补充正文和合法附件后重新反馈
- **THEN** 当前版本原子递增，真实事件保留；仅授权读取任务的人可下载新材料；过期版本、非法阶段、他人未绑定材料或错误父评论被拒绝且不产生部分写入

### Requirement: Remove product support feedback
用户已取消意见反馈功能。移动端 SHALL 删除意见反馈表单、我的反馈列表/详情入口与Mock资源支持；成果反馈、任务/日志评论及AI分析评价 SHALL 保留。

#### Scenario: Removed feedback deep links
- **WHEN** 用户进入帮助页或尝试旧support/feedback深链
- **THEN** 界面无意见反馈入口，旧深链安全返回帮助页且不请求不存在的feedback服务

### Requirement: AI scope selection and atomic confirmation
P1：AI作业 SHALL 支持scope=SELF/AUTHORIZED，默认AUTHORIZED；两者均与服务端实时授权取交集。SELF只纳入本人日志、本人参与或派发任务及本人重点，候选人员只含本人；AUTHORIZED沿用当前权限。后台执行及重试 SHALL 保留所选范围。确认 SHALL 携带作业version、actionIndex、task和Idempotency-Key，在同一事务锁定作业、重验来源和派发权限、版本及行动索引，并进入现有TASK_CREATE审核流程。

#### Scenario: Stale confirmation and idempotent retry
- **WHEN** 作业编辑后提交旧version，或同键重试同一已成功确认命令
- **THEN** 旧版本拒绝且无任务或审核残留；同键同规范化内容返回原确认结果，同键异内容返回IDEMPOTENCY_CONFLICT，即使之后编辑作业也不重复派发

#### Scenario: Scope preserved and privilege revoked
- **WHEN** SELF作业被后台执行或重试，或原来源权限在确认前被撤销
- **THEN** SELF不会扩大为AUTHORIZED；失权来源不送入模型或确认生效，客户端不得指定任意部门或人员扩大范围

### Requirement: Workbench shares task creation review contract

AI办事模块 SHALL 复用当前TaskApi创建审核响应，待审时回执只提供reviewId和WAITING_REVIEW，不将审核ID或缺失version当作已创建任务；交付授权及候选 SHALL 使用task_participants。

#### Scenario: Existing workbench task creation needs review
- **WHEN** 办事模块收到TASK_CREATE待审响应
- **THEN** 作业等待该审核，审批生效后才显示成功；任务不存在时不提供任务详情链接

### Requirement: Deferred unified acceptance

全部新增接口 SHALL 在实现后统一运行编译、测试、迁移升级及HTTP验收。2026-10-29用户已授权统一验收；系统 MUST 记录实际结果，不把文档或源码核对当作功能通过证据。已停用阅读登记 SHALL 不新增人员清单。

#### Scenario: Implementation status without execution
- **WHEN** 本批完成代码及契约接入但未运行统一验收
- **THEN** task保持未验证，运行时OpenAPI快照等待真实服务生成
