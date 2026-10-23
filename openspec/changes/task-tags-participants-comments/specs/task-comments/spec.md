## ADDED Requirements

### Requirement: 公开任务评论与回复

系统 SHALL 允许有任务读取权限的用户读取公开评论，并允许具备任务参与或派发资格的用户新增评论或回复。评论 SHALL 包含作者、昵称、头像标识、创建时间、正文和可选父评论 ID，且一经创建 MUST NOT 编辑或删除。

#### Scenario: 评论回复

- **WHEN** 有权限用户向同一任务中的现有评论提交非空回复
- **THEN** 系统 SHALL 保存父评论 ID 并按创建时间返回该回复

#### Scenario: 空评论、错误父评论或越权评论

- **WHEN** 正文为空、父评论不属于当前任务，或范围外用户读取/提交评论
- **THEN** 系统 SHALL 分别返回 `400 INVALID_COMMENT`、`400 INVALID_PARENT_COMMENT` 或 `404 NOT_FOUND`

### Requirement: 评论去重与事务通知

系统 SHALL 使用调用方提供的幂等键拒绝同任务同作者的重复评论，并 SHALL 在同一事务内写入评论、审计和对应 outbox 通知。

#### Scenario: 重复评论提交

- **WHEN** 同一作者以相同幂等键再次向同一任务提交评论
- **THEN** 系统 SHALL 返回 `409 DUPLICATE_COMMENT`
- **AND** 系统 MUST NOT 新增第二条评论或第二组通知

#### Scenario: 通知写入失败

- **WHEN** 评论写入后的通知写入失败
- **THEN** 整个事务 SHALL 回滚
- **AND** 数据库中 MUST NOT 留下评论、审计或部分 outbox 记录
