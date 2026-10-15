# 成员 B 第一批：认证契约与验收

关联 Issue #3；OpenSpec member-b-backend-readiness 2.1–2.6。运行状态以 docs/member-b-delivery.md 为准。

## 调用路径

AuthController → AuthApplicationService / DefaultAuthApplicationService → AuthPolicy / AuthRepository。
注册在同一事务中创建待确认员工、员工角色和归属申请；任一步失败整体回滚。
首次管理员由 AuthBootstrap 调用初始化用例，只创建、不覆盖；无默认密码。
登录由应用服务显式事务编排，错误结果提交失败状态后才映射认证错误。Controller 不执行 SQL。

## 接口

- GET /api/auth/departments：公开注册部门 id/name，无版本或幂等键。
- POST /api/auth/register：account、password、phone、name、departmentId；角色固定 EMPLOYEE、状态 PENDING，不接受 role；密码至少 12 字符且 UTF-8 不超过 72 字节。返回 id、role、status、reviewId、phoneVerified=false。非法输入 400、部门不存在 404、账号/手机号重复 409；重复申请不采用幂等键。当前服务不提供短信认证或确认密码字段，客户端可做确认密码输入校验。
- POST /api/auth/login：account、password，返回 token、expiresAt、公开 user。账号大小写沿用数据库精确匹配，前后空白沿用现有 trim 规则；每次成功新建会话。未知账号/错误密码/锁定均 401 INVALID_CREDENTIALS；验证正确密码的停用账号 403 ACCOUNT_DISABLED。IP 限流 429、Redis 不可用 503。无版本或幂等键。
- GET /api/auth/me：有效会话读取本人公开字段；无密码摘要、手机号或私人备注，未认证/会话失效 401。
- POST /api/auth/password：有效会话，oldPassword、newPassword；旧密码错误 401，新密码无效或相同 400；成功清除首次改密标记并撤销全部旧会话，返回 reloginRequired=true。旧凭证重试失败，无版本或幂等键。
- POST /api/auth/logout：有效会话，无 body，撤销当前 token，返回 ok=true。数据库删除幂等，旧 token 再次调用 HTTP 被过滤器拒绝 401；其他会话保留。

统一错误包含 code、message、traceId，响应头 X-Trace-Id。待确认账号可登录和查看本人/自身申请，但公司业务读取拒绝；首次改密账号只能访问改密、本人和注销入口。停用和调岗后下一请求按当前数据库状态授权。

## 迁移和并发

新增 V10__auth_login_protection.sql，保留远端 V1–V9。原 lyb 的认证 V5 尚未合入 main，本次统一为 V10；已执行旧认证 V5 的开发库需按 docs/member-b-merge-upgrade.md 处理。auth_login_state 只存规范化账号 SHA-256 摘要、失败数、锁定截止和更新时间，不存明文账号或密码。唯一键及行锁序列化同账号失败，五次触发十分钟锁定；锁定期间不延期；到期后新失败从一次开始；成功清零。
登录读取用户行时加锁，与改密串行，避免改密撤销后又用旧密码签发会话。每小时清理超过 24 小时未更新且没有有效锁定的状态，活跃锁不删除。保留 IP 限流；不同来源大量未知账号的容量测试尚待综合性能验收。
回退应用保留新增表，不修改已发布迁移；旧应用不识别锁定状态，回退会失去该防护，应明确记录。

## 验证入口

仓库全套：powershell -ExecutionPolicy Bypass -File scripts/test-backend.ps1 -DockerMaven。
定向类：AuthPolicyTest、AuthIntegrationTest；需真实隔离 PostgreSQL/Redis 与环境变量，不使用开发数据库作清理测试。
单元覆盖五次阈值、精确到期、锁定不续期、UTF-8 密码边界及账号输入；集成覆盖失败提交、并发计数、锁定恢复、注册原子性、权限限制、会话撤销、停用和调岗、安全字段、清理及 远端 V9→V10 升级。

本模块 JavaDoc/运行时登录错误说明已同步；公共 OpenAPI 快照、E 的客户端错误展示和真实 Flutter 接入需独立核对，不能仅凭后端通过声明双端联调完成。
