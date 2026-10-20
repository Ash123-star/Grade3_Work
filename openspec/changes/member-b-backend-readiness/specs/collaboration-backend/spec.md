## MODIFIED Requirements

### Requirement: Authentication and organization scope
服务端 SHALL 注册仅员工、拒绝角色注入、校验唯一手机号并等待归属确认；初始化管理员无默认密码且首次改密。每次读取、修改、导出和 AI 请求 SHALL 校验公司与当前组织范围。认证和组织故事 MUST 以 MVP 分工为范围，覆盖注册、登录、改密、登出、会话失效、组织维护及五角色权限；待确认账号不得读取公司业务数据。

#### Scenario: Pending user and forged role
- **WHEN** 注册指定管理员或待确认用户读取业务
- **THEN** 请求被拒绝，普通合法注册保持待确认员工。

#### Scenario: Transfer or disable
- **WHEN** 审核通过调岗或停用
- **THEN** 既有会话下一次请求应用新范围或被拒绝。

#### Scenario: Valid registration and invalid inputs
- **WHEN** 提交有效员工注册或非法手机号、重复账号/手机号、无效部门
- **THEN** 合法注册创建待确认员工；无效输入被明确拒绝且不留下部分账号或归属记录。

#### Scenario: Initial password and logout
- **WHEN** 初始管理员尚未改密或用户注销当前会话
- **THEN** 初始管理员业务操作被拒绝，改密成功才解除限制；注销后旧凭证无法访问业务接口，认证响应不返回密码或会话存储摘要。

#### Scenario: Scope across clients
- **WHEN** Android 或其他客户端以同一身份查询范围外人员、组织详情或申请组织修改
- **THEN** 服务端一致拒绝，不能通过伪造 companyId、departmentId、teamId 或请求角色扩大范围。

### Requirement: Candidate revisions and independent review
关键修改 SHALL 保持旧版直到团队、部门、公司复核完成，禁止自审、要求驳回原因和版本校验，记录审计。任务复核策略 SHALL 允许管理员申请配置团队及部门复核层级，策略自身通过独立审核后生效且不能关闭公司独立复核。员工复核职责申请 SHALL 由独立管理员审批且不改变员工角色或业务读取范围。审核故事优先级为 MVP，范围为 B 的审核编排与组织变更应用，任务和日报规则由所属模块提供。

#### Scenario: No independent reviewer
- **WHEN** 无独立公司复核人提交正式修改
- **THEN** 修改保持待审且旧值仍生效。

#### Scenario: Conflict and self review
- **WHEN** 申请人自审或最终通过时版本已变化
- **THEN** 拒绝请求且不覆盖生效内容。

#### Scenario: Review policy change
- **WHEN** 管理员申请变更任务复核层级
- **THEN** 旧策略继续生效直到独立审核通过，新策略仍要求公司独立复核。

#### Scenario: Approved and rejected revision
- **WHEN** 独立审核人完成全部层级通过或填写原因后驳回
- **THEN** 全部通过后才原子更新生效版本；驳回保留旧值；两种结果都记录申请人、处理人、时间及修改前后内容。

#### Scenario: Unauthorized or invalid decision
- **WHEN** 非当前有资格审核人处理申请、驳回原因空白、处理已结束申请或提交无效决定
- **THEN** 请求被拒绝且不改变申请或业务对象，不重复生成审计或业务事件。

#### Scenario: Concurrent candidates and decisions
- **WHEN** 同对象的候选申请或同一申请的审核决定并发完成
- **THEN** 生效时进行版本检查，至多一次更新同一版本，冲突明确返回且不丢失已有内容；不额外将 PRD 单条待审限制作为本阶段验收条件。

## ADDED Requirements

### Requirement: Login failure protection
认证服务 SHALL 对同一账号连续五次错误密码尝试锁定十分钟，正确密码成功后清除失败累计；未知账号与错误密码返回一致认证失败提示。失败计数 MUST 在失败响应后仍有效，不因事务回滚丢失。此 P0 补充故事参考 PRD US-02，范围仅为登录防护，不包含找回密码、短信或外部身份提供商。

#### Scenario: Lock and expiry
- **WHEN** 同一账号累计第五次错误密码，随后在锁定期内再次登录
- **THEN** 第五次起不签发会话，锁定期内正确密码也不能登录；十分钟到期后允许重新尝试，锁定中的请求不延长锁定期限。

#### Scenario: Success resets failure count
- **WHEN** 账号累计不足五次错误后以正确密码成功登录
- **THEN** 失败累计清零，后续错误从第一次开始；未知账号与已知账号错误密码的对外提示一致。

#### Scenario: Parallel failures and disabled account
- **WHEN** 多个客户端并发提交错误密码，或停用账号提交正确凭证
- **THEN** 失败次数不丢失，达到阈值后不能绕过锁定；停用账号不签发会话，在已验证密码后可返回停用原因。

### Requirement: Organization integrity
组织维护 SHALL 校验同公司部门与团队归属、五角色合法性、负责人配置、有效账号状态及汇报关系无环；禁止删除或停用最后一位有效管理员。此 MVP 故事范围为现有公司中的组织维护，不包含新公司开户；组织读取 SHALL 保持当前批准的数据范围，不因重构扩大授权。

#### Scenario: Valid organization revision
- **WHEN** 管理员申请合法调岗、账号状态或汇报关系变更并经独立审核通过
- **THEN** 新关系与版本一致生效，下一次请求按新范围授权，历史日志和任务仍保留。

#### Scenario: Invalid hierarchy or administrator removal
- **WHEN** 指定跨公司部门、团队部门不匹配、循环汇报、非法角色或移除最后一位有效管理员
- **THEN** 拒绝变更且保留原组织；并发变更也不能绕过最后管理员约束。

#### Scenario: Complete authorized organization results
- **WHEN** 授权范围内人员超过默认页大小并查询组织或人员列表
- **THEN** 通过明确分页或完整树契约可访问所有获授权结果，不静默截断，不包含范围外人员或不该暴露的认证字段。

### Requirement: Member B backend acceptance evidence
成员 B 后端交付 MUST 提供注册登录、待确认越权、组织隔离、审核通过/驳回、自审拒绝、版本冲突的真实运行证据；核心规则包含正常、边界、异常单元测试，至少一条认证至审核生效的真实数据库集成链路。安全隔离和响应性能分别验证，未实现或未验证项必须如实保留。

#### Scenario: End to end verification
- **WHEN** 执行注册、登录、管理员发起归属确认、独立审核通过、组织候选修改和最终生效链路
- **THEN** 接口返回与数据库状态一致，旧值在通过前有效，审计可追溯，越权及自审请求无法写入。

#### Scenario: Incomplete regression or mock only evidence
- **WHEN** 回归有失败、仅有 Mock 或性能环境未准备
- **THEN** 对应项目保持未完成并记录失败、责任边界和阻塞，不声明功能全部完成或生产可用。
