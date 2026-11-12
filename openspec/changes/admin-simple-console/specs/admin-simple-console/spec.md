## Purpose

为仅管理员使用的简易后台定义员工资料录入、直接创建员工账号和公司重要事项维护的可验收边界，复用现有业务权限、独立审核和版本校验，支持本地运行并提供后续云端部署说明。

## ADDED Requirements

### Requirement: Administrator console access
P0，后台 SHALL 仅允许 ACTIVE 且已完成首次改密的 ADMIN 访问员工和公司事项；服务端 MUST 每次重验角色及公司，前端失权清空私人内容。

#### Scenario: Access revoked
- **WHEN** 员工、仅 FOUNDER、待确认账号或撤权管理员访问后台接口
- **THEN** 服务端拒绝401/403，浏览器清理受限内容，不依赖隐藏按钮鉴权

### Requirement: Direct employee provisioning
P0，ADMIN SHALL 填写账号、初始密码、手机号、姓名、部门直接创建 ACTIVE/EMPLOYEE 账号；MUST 强制首次改密，原子写入角色与脱敏审计，不返回密码或哈希。创建不要求幂等键，重复账号或手机号 SHALL 返回409。

#### Scenario: Create and sign in
- **WHEN** 管理员录入有效资料且员工用初始密码登录
- **THEN** 账号立即存在且无需注册审核，员工改密前不能读取业务，改密后使用新密码访问 Android 原业务接口

#### Scenario: Invalid or duplicate creation
- **WHEN** 请求包含管理角色/公司注入、非法密码/手机号、其他公司部门或重复账号
- **THEN** 服务端拒绝，不新增用户、角色或审计，不泄露哈希

### Requirement: Employee maintenance
P0，后台 SHALL 分页搜索本公司员工（含停用账号），支持姓名、部门和停用候选提交，MUST 携带版本和原因并复用独立审核，审核前旧值有效。

#### Scenario: Edit employee
- **WHEN** 管理员提交员工新姓名或停用申请
- **THEN** 页面明确显示待审核，独立审核生效后列表与 Android 使用相同数据，停用撤销会话

#### Scenario: Conflict or foreign user
- **WHEN** 使用旧版本或其他公司员工ID提交候选
- **THEN** 拒绝越权或在最终审批拒绝版本冲突，不覆盖当前资料

### Requirement: Company priorities maintenance
P0，后台 SHALL 支持公司重点新增、编辑、排序、撤下和恢复，MUST 使用 COMPANY_ITEM 候选、原因和版本；最多十条置顶，审核前原内容保持，管理员不得自审。

#### Scenario: Publish priority
- **WHEN** 管理员提交事项并由有效独立审核人通过
- **THEN** Android 公司重点显示同一已生效内容和排序，后台可查看申请结果

#### Scenario: Pin limit or self approval
- **WHEN** 最终审核将超过十条置顶或申请人尝试自审
- **THEN** 服务端拒绝，旧数据和审计事务保持一致，页面展示错误而非成功

### Requirement: Local development and deployment handoff
P0，交付 SHALL 提供本地启动及同源云端静态部署说明；后台 SHALL 呈现加载、空、失败、冲突状态，防重复提交、转义用户文本并适配窄屏和键盘。

#### Scenario: Network failure
- **WHEN** 保存请求失败或返回非JSON错误
- **THEN** 页面保留合法输入提供恢复提示，不自动重放创建操作或展示虚假成功

#### Scenario: Local browser origin
- **WHEN** 管理员从本地5173端口页面登录演示后端，包括复用旧stage.env
- **THEN** 演示启动配置 SHALL 精确允许localhost及127.0.0.1的5173和5175来源，真实浏览器可登录；未授权来源仍拒绝，不启用通配符
