## ADDED Requirements

### Requirement: Founder exemption without peer review
P0；创始人权限内非 MEMBERSHIP 新申请 SHALL 同事务校验权限和版本后以 APPROVED/FOUNDER_EXEMPT 生效，无论公司创始人数；MUST NOT 创建互审步骤。
#### Scenario: Multiple founders
- **WHEN** 公司有多位创始人且其中一位提交合法修改
- **THEN** 修改 SHALL 免审生效、留审计并通知本人，其他创始人不收到待审任务
#### Scenario: Unauthorized founder action
- **WHEN** 创始人提交越权或过期版本候选
- **THEN** 系统 MUST 拒绝且不产生部分生效数据

### Requirement: Direct superior reviews department manager requests
P0；部门经理等非创始人的申请 SHALL 只分配当前有效直属上级，禁止随机选择其他创始人或管理员兜底。MEMBERSHIP SHALL 仍由管理员确认。
#### Scenario: Multiple founders above organization
- **WHEN** 部门经理的直属上级是创始人A，公司另有创始人B
- **THEN** 只有A SHALL 能审核；B读取或决定 MUST 返回403；申请人不能更换审核人
#### Scenario: No valid direct superior
- **WHEN** 直属上级未配置、停用或关系成环
- **THEN** 申请 SHALL 保持待审并通知配置关系，不分配其他创始人
#### Scenario: Relation changes
- **WHEN** 当前直属关系经合法组织变更更新
- **THEN** 待审步骤 SHALL 在同一事务内按新关系更新，旧审核人失去决定权；组织变更失败不改派

### Requirement: Retire pending founder peer requests
P0；V31前向迁移 SHALL 将旧FOUNDER_PEER待审申请及其待审步骤设为SUPERSEDED，保留已决历史和候选，写审计和通知。MUST NOT 应用候选或修改目标业务对象。旧申请必须重新提交，不能继续或更换审核人。
#### Scenario: Upgrade pending and decided records
- **WHEN** 数据库包含互审待审、已批准和直属审核申请
- **THEN** 仅互审待审 SHALL 作废，已决和直属申请不变，业务版本不变
#### Scenario: Old client retries
- **WHEN** 旧客户端尝试决定、换人或reroute旧互审申请
- **THEN** 服务端 MUST 拒绝，不新增步骤、业务修改或成功通知

### Requirement: Concurrent direct decisions apply once
P0；决定 SHALL 锁定申请并校验PENDING、直属关系、版本和非自审；无效或重复决定 MUST 回滚。
#### Scenario: Parallel approval
- **WHEN** 直属上级并发批准同一申请
- **THEN** 仅一次 SHALL 生效、写审计和outbox，其他请求返回409

### Requirement: Client review display consistency
P1；真实和Mock客户端 SHALL 使用同一免审及直属规则；历史互审显示已停用，不提供换人入口，作废通知跳转审核详情。请求失败 MUST NOT 伪装成功。
#### Scenario: Retired request display
- **WHEN** 申请人查看旧互审作废记录
- **THEN** 客户端 SHALL 显示作废和重新提交提示，无批准或恢复入口
