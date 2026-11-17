## Context

V4 已建立 `log_tasks(company_id, log_id, task_id)` 及日报、任务复合外键，并回填旧 JSON `taskIds`。现有日志 Controller 以 `Business.ownerScope` 过滤列表，草稿通过 `(submitted OR owner_id=actor)` 隐藏；但草稿保存后直接同步 `taskIds`，候选修订审核生效也直接同步，缺少对申请人当前任务范围的再校验。

## Goals / Non-Goals

**Goals:**
- 下属入口仅管理者可用，且只返回组织范围内他人的已提交日报。
- 草稿永不经下属入口、列表或详情暴露给他人。
- 每个日志任务关联在写入和审核生效时均验证申请人的服务端任务读取范围。
- 关联表与 JSON `taskIds` 同事务保持一致。

**Non-Goals:**
- 不改变日报正文、提交、评论或审核链本身。
- 不增加跨组织分享、批量导出、通知或 AI 读取逻辑。

## Decisions

### 1. 查询服务

`LogQueryService.list(Actor, Query, subordinate)` 使用 `Business.ownerScope`。普通列表允许本人草稿；下属模式先要求 `actor.manager()`，强制 `owner_id <> actor.id` 和 `submitted=true`。`ownerId` 先验证同公司用户存在，再用 `actor.canSeeUser` 判定，其他公司返回 404，同公司范围外返回 403。日期范围使用既有上海业务日期工具。

### 2. 关联校验和同步

`LogTaskLinks.validate(db, actor, body)` 对去重后的 `taskIds` 调用 `Business.task(actor, id, false)`。`sync` 只能在验证成功后执行：先删除当前日志的关联，再插入每个任务 ID。草稿保存和修订申请调用验证；审核通过应用 `LOG` 候选时使用申请人身份再次验证，防止审批期间权限变化后仍写入越权关联。

### 3. 草稿隐私

所有列表和详情继续以 `(submitted OR owner_id=actor)` 过滤；`subordinate=true` 再附加 `submitted`，形成数据库和应用层双重限制。对草稿 ID 的非本人读取保持 404，不能通过评语、已读、版本或下属列表探测。

### 4. Flyway

新增 V9：

```sql
CREATE INDEX daily_logs_submitted_owner_date_id
ON daily_logs(company_id, owner_id, business_date DESC, id)
WHERE submitted;
```

它支持下属范围列表与负责人筛选；不改 V4 关联表、既有外键或数据。

## Risks / Trade-offs

- [审核通过时访问权已变化] → 重校验会让候选生效返回 404/403，需要申请人重新编辑，优先保护组织范围。
- [同步采用删后插] → 必须在已有事务中调用；异常会回滚，集成测试验证。
- [索引增加维护成本] → 仅索引已提交日报，规模小于全表并匹配入口查询。

## Migration Plan

1. 已应用 V1–V8 的数据库执行 V9，创建部分索引。
2. 部署查询服务和关联重校验；无需回填，V4 已完成历史回填。
3. 回滚可保留索引；旧代码仍可读写已有 `log_tasks`。

## 2026-11-17 今日任务

已确认可选范围是当前员工本人参与、已接收但未完成（RECEIVED）的全部任务，不新增待验收（FEEDBACK）任务，不按日志日期截断。正文下方以紧凑下拉框多选，展开面板内保留标签颜色胶囊与勾选状态，收起仅显示已选数量，taskIds 使用现有 body 与 log_tasks 存储，无新表。PUT /logs/{id}/content 增加可选 taskIds，省略时保留关联，空数组明确清空；新增关联要求当前参与且未完成，已有历史关联继续保留，读取仍按现有服务端权限。正文、关联表和历史版本同事务写入，版本冲突回滚；草稿按账号隔离。删除日志页右上角下属日志入口，保留后端授权查询及其他既有成员入口。

用户验收进一步明确：入口名称为“关联任务”，仅 RECEIVED 可作为新增候选，不包含待验收 FEEDBACK；历史已关联任务仍保留可读展示与移除。服务端与客户端同步收紧，不扩张数据权限。
