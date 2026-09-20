## ADDED Requirements

### Requirement: Registration and scoped access
系统 SHALL 要求注册填写账号、密码、唯一手机号和部门，所有新账号只能成为员工；未确认归属的账号不得查看公司内部信息。初始化管理员 MUST 无公开默认密码，并要求首次改密。服务端 SHALL 对管理员、创始人、部门老总、团队长、员工分别执行角色及公司/部门/团队/本人范围控制。

#### Scenario: Reject privilege escalation
- **WHEN** 员工注册请求携带管理员角色或请求他人私有日志
- **THEN** 服务端拒绝越权，不因客户端传参扩大范围

#### Scenario: Respect hierarchy
- **WHEN** 团队长查询下属日志、任务、报表或候选接收人
- **THEN** 仅返回当前组织范围内数据；调岗或停用后重新校验访问资格

### Requirement: Versioned hierarchical review
系统 SHALL 对组织、角色及已发布关键信息修改生成候选版本，按层级复核后生效并记录前后值；申请人 MUST NOT 自审。

#### Scenario: Await independent reviewer
- **WHEN** 修改提交且没有独立复核人
- **THEN** 保持待审且旧版本有效，不自动通过

#### Scenario: Reject stale approval
- **WHEN** 另一修改已使对象版本变更
- **THEN** 阻止过期版本覆盖并要求重新复核
