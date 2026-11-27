## ADDED Requirements
### Requirement: Explicit personnel permissions
P0。系统 SHALL 只允许有效管理员或获得显式READ/MANAGE授权的人员访问合同；仅管理员维护授权，普通员工不能通过直接接口读取合同。
#### Scenario: Unauthorized request
- **WHEN** 未授权员工或其他公司人员请求合同或附件
- **THEN** 系统拒绝访问且不返回敏感字段
#### Scenario: Revoked access
- **WHEN** 管理员撤销授权
- **THEN** 旧会话后续请求立即失去合同访问权限
### Requirement: Employee contract archive
P0。系统 SHALL 复用员工ID和岗位，支持职责、合同日期及私有附件归档；修改必须检查版本并记录审计。
#### Scenario: Valid archive
- **WHEN** 授权管理人员提交有效日期和本人上传的独立附件
- **THEN** 合同保存并可由授权人员查看
#### Scenario: Invalid revision
- **WHEN** 日期无效、员工跨公司、附件被其他业务占用或版本过期
- **THEN** 请求拒绝且不部分修改
### Requirement: Idempotent expiry reminder
P0。系统 SHALL 按北京时间在到期前30天、7天、当天向指定且仍获授权人员发送站内提醒；合同版本、节点、人员组合不得重复发送。
#### Scenario: Repeated scan
- **WHEN** 同一节点被重复或并发扫描
- **THEN** 每位接收者仅生成一条事务消息
#### Scenario: Ineligible recipient
- **WHEN** 接收者已停用或撤权
- **THEN** 不发送提醒且不能读取合同
### Requirement: Independent Web entry
P0。系统 SHALL 提供独立Web人事入口，展示授权能力和错误状态，不开放原管理员后台。
#### Scenario: Initial password change
- **WHEN** 首次登录的账号需要更换初始密码
- **THEN** 人事入口先允许改密并要求以新密码重新登录，在授权确认前不加载人事数据；原密码错误时保留改密入口并显示错误
#### Scenario: Read only member
- **WHEN** READ人员进入
- **THEN** 可查合同但所有写操作在服务端拒绝
