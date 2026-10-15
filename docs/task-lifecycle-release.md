# 任务生命周期上线说明

## 迁移

部署会执行 `V6__task_lifecycle.sql`：为 `task_events` 追加状态快照列，并扩展事件类型约束。该迁移不修改已有事件；`TRANSFERRED` 仅保留用于兼容 V5 已写入的历史记录，新的转派复核生效事件为 `REASSIGNED`。

## 待审通用修订排查

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
