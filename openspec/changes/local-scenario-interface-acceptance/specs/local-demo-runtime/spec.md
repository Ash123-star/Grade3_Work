## ADDED Requirements

### Requirement: Isolated realistic scenario data

P0：数据初始化 SHALL 默认禁用，仅在显式启用且提供安全密码时通过独立 Flyway 历史表向配置指定的数据库追加相互关联的虚构组织、人员、任务、日志与审批数据；不得覆盖现有数据。运行验收 MUST 使用当前接口，不得调用退役日志入口。

#### Scenario: Related business workflows
- **WHEN** 在完成正式结构迁移的数据库显式启用种子目录
- **THEN** SHALL 可查看参与人、派发人、直属上级、评论作者和关联任务一致的业务场景，并覆盖至少15名人员和20项任务、多种状态和期限

#### Scenario: Disabled, conflicting or repeated seed
- **WHEN** 未启用种子目录、未提供合格密码、对象名称冲突，或同一库已完成初始化
- **THEN** MUST 分别保持零种子写入、拒绝执行、事务回滚或由独立Flyway历史跳过，不清库、不重复追加数据

### Requirement: Native runtime acceptance evidence

P0：本地验收 SHALL 使用真实服务和 Android 原生客户端，保留有明确结果的接口及启动证据。

#### Scenario: Valid remembered session
- **WHEN** 用户登录后强制停止并重启 Android 应用
- **THEN** SHALL 通过保存的token和auth/me恢复身份，无需再次输入密码，服务端新会话有效期为168小时

#### Scenario: Unauthorized request
- **WHEN** 待确认/跨公司/非作者用户读取或修改无权限的对象，或使用旧版本
- **THEN** MUST 按当前契约返回可区分错误，不产生业务写入

### Requirement: Varied muted task labels

P0：场景标签 SHALL 提供至少八种可区分的低饱和颜色，按工作类型分配；同一团队成员的任务 MUST 能呈现多种标签色。既有种子升级 SHALL 使用追加迁移并保留用户修改、版本和事件记录。

#### Scenario: Populated native calendar
- **WHEN** 打开已初始化成员的任务月历
- **THEN** SHALL 看到多种柔和标签色，标签名仍可阅读，不以颜色代替标签语义

### Requirement: Routine notification stream expiry

P0：通知 SSE 正常超时 SHALL 完成流并释放定时任务，不得向已提交的事件流写JSON或记录内部错误；非流式异步超时 MUST 返回明确的503错误。

#### Scenario: Client reconnect after timeout
- **WHEN** 通知流到达55秒有效期
- **THEN** SHALL 正常结束并允许客户端重连，不产生JSON序列化异常
