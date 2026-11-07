# 首页每日事项接口（Issue #63）

本模块是私人 todo，不引用任务、日志或审批。路径前缀 `/api`，只允许已激活且不需改密的当前登录人。查询、详情、修改、删除、月历计数都同时限制 `company_id` 与 `owner_id`；管理员、上级与跨公司用户不具备代查权限。禁止传入 ownerId、companyId、taskId 或其他未知字段。

| 方法 | 路径 | 输入 | 返回 |
|---|---|---|---|
| GET | `/personal-todos/calendar` | month：YYYY-MM | month、fromDate（含）、toDate（不含）、days：date/total/completed；含邻月的周一至周日完整网格 |
| GET | `/personal-todos` | date；cursor 默认0；limit 默认30、1–100 | items、total、nextCursor；末页为 null |
| GET | `/personal-todos/{id}` | id | 当前 Todo |
| POST | `/personal-todos` | title、date、note（可选） | 201 Todo；version=1、completed=false |
| PUT | `/personal-todos/{id}` | title、date、note（可选）、completed、version | 更新后的 Todo |
| DELETE | `/personal-todos/{id}` | query version | id、deleted=true、新 version |

Todo 为 id/title/note/date/completed/completedAt/version/createdAt/updatedAt。date 为上海自然日（1900–2100），时间戳为 UTC。标题去首尾空白后 1–120 Unicode 字符，备注最多2000字符；completed 必须是布尔值，version 必须是正整数。列表按未完成优先、创建时间、id 排序，使用偏移分页；列表变动后客户端回到第一页。

写入必须提供 `Idempotency-Key`（1–128位，字母数字或 `:_.-`）。同一账号同键同请求在24小时内返回原响应，同键异参为409；回执与业务写入同事务。完成/恢复传目标布尔值，不执行盲目翻转。更新、删除按版本原子比较；删除后的原命令重试仍可重放成功。过期键作为新请求处理，客户端只在当前会话保留不确定命令，重启后需先查看服务端结果，不提供离线保存承诺。

错误沿用 code/message/traceId：400 参数错误；401 会话失效；403 待确认或权限不足；404 不存在、已删除或他人对象；409 VERSION_CONFLICT / IDEMPOTENCY_CONFLICT；429 限流。未知或重复查询参数400。冲突后读取最新版本，用户明确选择保留输入后再次提交，不自动覆盖。网络结果不确定时保留原键和不可变请求重试。

首页任务看板使用 `/tasks/received-card?cursor=0&limit=2` 取摘要，完整页每页30条；沿用 task_participants 范围，包含本人派发且本人参与的任务，保留完成等生命周期。禁止回退到组织范围的 `/tasks` 或 `/dashboard.companyTasks`。支持未来 `labels` 数组并兼容当前 `label`，实际主线仍只有单标签。

公司页面仍用 `/view`，首页仍用 `/dashboard`，已存在深链接兼容。每日事项日期状态不影响公司和日志的共享筛选。
