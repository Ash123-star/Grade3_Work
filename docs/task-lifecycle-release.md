# 任务生命周期上线说明

## 迁移

PR #17 整合使用 `V12__task_revision_review_kinds.sql`，避开主分支已发布的记忆迁移 V10/V11。审核类型保留 `MEMORY`，同时允许 `TASK_REASSIGN`、`TASK_RESCHEDULE`，不修改历史审核记录或已发布迁移。原 PR 的 V10 文件尚未进入主线；若在独立开发库执行过它，不能直接套用主线迁移历史。

部署会执行 `V6__task_lifecycle.sql`：为 `task_events` 追加状态快照列，并扩展事件类型约束。该迁移不修改已有事件；`TRANSFERRED` 仅保留用于兼容 V5 已写入的历史记录，新的转派复核生效事件为 `REASSIGNED`。

## 待审通用修订排查

## 2026-10-15 PR #17 整合验证

- `scripts/test-backend.ps1 -DockerMaven`：Java 21 / Docker Maven 与隔离 PostgreSQL、Redis、Neo4j，clean verify 成功；92 项测试通过，0 失败、0 错误、0 跳过（18 项全链路、20 项任务日报集成、54 项单元）。
- Flyway V1–V12 在全新隔离库成功迁移，覆盖任务转派改期及组织记忆审核；未对生产库执行升级或待审申请统计。
- `openspec.cmd validate --all --strict`：26 项通过。

## 待审通用修订排查步骤

上线前必须在目标数据库执行以下只读查询。结果大于 0 时，相关申请在新规则下不能生效，申请人需要通过转派或改期专用接口重新提交。

```sql
SELECT id, target_id, applicant_id, created_at
FROM review_requests
WHERE kind = 'TASK'
  AND status = 'PENDING'
  AND (
    candidate ? 'ownerId'
    AND candidate->>'ownerId' IS DISTINCT FROM before_value->>'ownerId'
    OR candidate ? 'deadline'
    AND candidate->>'deadline' IS DISTINCT FROM before_value->>'deadline'
  );
```

本地实现环境没有可用的 PostgreSQL/Docker，尚未获得目标数据库的实际统计结果；发布前由部署负责人执行上述查询并记录数量。
