## Context

`daily_logs` 已有 `UNIQUE(owner_id,business_date)`、`submitted`、`version` 和 `submitted_at`；`log_versions` 已按 `(log_id,version)` 保存提交与修订历史。V4 已增加正文对象和提交一致性约束。当前 Controller 可工作，但直接执行 SQL 和业务规则，`LogApplicationService` 没有实现，导致模块分层与可测试性不足。

## Goals / Non-Goals

**Goals:**
- 一名用户每天只有一份主日报，草稿可覆盖、提交后不可直接覆盖。
- 草稿只对本人可见；上级只可看范围内已提交日报。
- 所有写入带版本，冲突不覆盖数据；提交和修订都保留可追溯历史。
- 评论和已读只面向已提交日报。

**Non-Goals:**
- 不改组织审核链或审阅人选择；已提交修订仅调用既有 `ReviewApplicationService`。
- 不实现通知投递，保留已有 outbox 写入。
- 不在此变更扩展下属入口、组织查询或 `log_tasks`，它们属于变更 5。

## Decisions

### 1. 应用层用例

实现 `LogWorkflowService`，提供 `saveDraft`、`submit`、`revise`、`detail`、`versions`、`markRead`、`comment`。Controller 保留路径、`@Transactional` 边界和日志列表查询，委托应用服务；服务不依赖 HTTP 对象。下属列表与日志任务关联将在变更 5 单独收敛。

### 2. 草稿、提交与唯一性

保存草稿按 `(owner_id,business_date)` 获取并锁行；新草稿仅允许 `version=0`，已有草稿以 `UPDATE ... WHERE version=?` 乐观锁更新。数据库唯一约束是并发时的最终保护。提交前必须验证正文，更新 `submitted=true`、`submitted_at=now()`、版本加一，并同事务插入 `log_versions`。提交后草稿保存返回 409 `REVIEW_REQUIRED`。

### 3. 可见性与错误顺序

读取按 `Business.log`：同公司、组织范围且 `(submitted OR owner_id=actor)`。因此草稿对非本人显示为 404，避免泄露存在性。评论、已读和历史版本先执行相同范围读取，再要求 `submitted=true`；草稿请求返回 403。写评论者必须为日报本人或管理者。

### 4. 修订与历史版本

已提交日报只能创建 `LOG` 候选修订，不直接改写正文。既有审核通过后以当前版本更新、插入 `log_versions`，过期申请在最终生效时返回 409。版本列表按版本升序、只对可见的已提交日报返回。

### 5. Flyway

V8 创建索引：

```sql
CREATE INDEX daily_logs_company_submitted_date_id
ON daily_logs(company_id, submitted, business_date DESC, id);
```

该索引仅支持列表读取，不更改 V1–V7、已有数据或日志唯一性约束。

## Risks / Trade-offs

- [从 Controller 提取服务可能改变错误顺序] → 为现有端点编写集成回归测试，并保持 `Business.log` 的 404 语义。
- [每日唯一约束已经存在] → 不重复添加约束；迁移只添加索引，部署前验证 Flyway 在 V1–V7 数据库通过。
- [审核修订由其他模块处理] → 仅维持现有调用和测试最终版本冲突，不改变审核链。

## Migration Plan

1. 在已应用 V1–V7 的库上执行 V8，新增索引。
2. 部署模块服务和控制器委托；接口路径、请求体和存量数据保持兼容。
3. 回滚时旧代码可继续使用表，新增索引可保留。
