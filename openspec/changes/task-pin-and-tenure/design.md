# Design

## 1. 任务置顶

### 路线比较
| 方案 | 说明 | 结论 |
| --- | --- | --- |
| A. 独立 `task_pins(user_id,task_id)` 表 | 个人偏好与任务数据分离，不触发审核和版本 | 采用 |
| B. `tasks.pinned` 列 | 全局置顶，必须走审核、递增版本，与用户选择不符 | 拒绝 |
| C. 仅客户端本地存储 | 换设备丢失，分页后排序不正确 | 拒绝 |

### 数据
```sql
CREATE TABLE task_pins (
  user_id text NOT NULL, task_id text NOT NULL, company_id text NOT NULL,
  pinned_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, task_id),
  FOREIGN KEY (user_id, company_id) REFERENCES users(id, company_id) ON DELETE CASCADE,
  FOREIGN KEY (task_id, company_id) REFERENCES tasks(id, company_id) ON DELETE CASCADE
);
CREATE INDEX task_pins_user_idx ON task_pins(user_id, pinned_at DESC);
```
外键列组合以实际存在的租户唯一约束为准，编码时核对 V2。

### 接口
| 接口 | 权限 | 结果 | 错误 | 幂等 |
| --- | --- | --- | --- | --- |
| `PUT /api/tasks/{id}/pin` | 有效登录用户且 `TaskAccess.readable` | `{taskId,pinned:true,pinnedAt}` | 不可见 403/404；第 11 项 409 `PIN_LIMIT` | 已置顶返回原 pinnedAt |
| `DELETE /api/tasks/{id}/pin` | 同上 | `{taskId,pinned:false}` | 不可见 403/404 | 未置顶也返回成功 |

- 计数与插入在同一事务内，先 `SELECT ... FOR UPDATE` 锁本人 users 行，防止并发超过 10 项。
- 用户失去任务可见权限后，列表自然不返回该任务，置顶记录不泄露任务信息；置顶计数只统计仍可见的任务，避免不可见记录占满额度。
- 不写审计和通知（个人显示偏好）。

### 列表
`TaskQueryService.list` 增加 `LEFT JOIN task_pins tp ON tp.task_id=t.id AND tp.user_id=?`，`ORDER BY (tp.task_id IS NOT NULL) DESC, tp.pinned_at DESC, t.deadline, t.id`；`LIST_COLUMNS` 与 `TaskListView.COLUMNS` 增加 `pinned`、`pinnedAt`。count 查询不受影响。

### 客户端
- 任务管理表每行增加图钉按钮（已置顶为实心并在行首显示标记），操作后刷新 `recordsProvider('tasks')`；失败提示错误并恢复原状态；达到上限提示“最多置顶 10 项”。
- 任务详情页提供同样的置顶开关。
- Mock 仓库按相同规则实现（上限、排序）。

## 2. 工龄

- 数据来源：`GET /profiles/me` 的 `employmentStartDate`（可空，管理员确认成员时写入，历史账号可能为空，不从 created_at 推测）。
- 计算：纯函数 `tenureLabel(DateTime? start, DateTime today)`，today 取上海时区日期：
  - null 或晚于 today → “未提供”；
  - 按完整月周年日计算总月数，短月周年日截至该月月末；从最近周年日起算剩余日数，统一显示“X年X个月X天”，同日为“0年0个月0天”。日期运算用 UTC 民用年月日避免夏令时影响；无效日期拒绝解析。
- 展示：`dashboard_pages.dart` 我的页头部卡片角色徽章旁显示“工龄 X”；`own_profile_page.dart` 资料信息网格增加只读“入职日期”“工龄”。
- Mock 资料补充 `employmentStartDate`。

## 3. 测试
- 后端集成：置顶/取消、幂等、第 11 项 409、不可见任务被拒、排序跨页一致、他人置顶不影响本人列表、置顶不改变任务 version。
- Flutter 单元：tenureLabel 边界（null、未来日期、29 天、1 个月、11 个月、1 年、1 年 3 个月、月末/闰日）。
- Flutter widget：任务表置顶按钮切换与失败恢复；我的页显示工龄与“未提供”。

## 4. 风险
- 迁移编号需在多创始人迁移之后，合并前再次核对。
- 任务管理表同时是成员 A 本周改动范围，置顶只新增按钮，不改其列宽与折叠逻辑。
- 种子用户工龄均不足一年，显示“0年N个月D天”。
