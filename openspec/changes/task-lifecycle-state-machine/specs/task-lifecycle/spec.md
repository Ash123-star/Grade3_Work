## Purpose

定义任务从派发到归档的状态机、各角色可执行的动作、转派与改期的复核生效方式，以及基于版本号的并发控制，保证任务状态只按合法路径变化且可追溯。

## ADDED Requirements

### Requirement: 状态与合法转换
任务状态 SHALL 只在下列转换内变化，且每次转换 SHALL 追加一条事件，记录操作人、动作、前后状态和生效版本：

| 动作 | 执行人 | 允许的当前状态 | 结果状态 |
|---|---|---|---|
| `RECEIVED` 接收 | 主负责人 | `DISPATCHED` | `RECEIVED` |
| `FEEDBACK` 反馈 | 主负责人或协作人 | `RECEIVED`、`FEEDBACK` | `FEEDBACK` |
| `ACCEPTED` 验收通过 | 派发人或管理员 | `FEEDBACK` | `ACCEPTED` |
| `RETURNED` 验收退回 | 派发人或管理员 | `FEEDBACK` | `RECEIVED` |
| `ARCHIVED` 归档 | 派发人或管理员 | `ACCEPTED` | `ARCHIVED` |
| `WITHDRAWN` 撤回 | 派发人或管理员 | `DISPATCHED`、`RECEIVED`、`FEEDBACK` | `WITHDRAWN` |

`ARCHIVED`、`WITHDRAWN` 为终态。反馈、退回、撤回 MUST 附 1–2000 字说明。

#### Scenario: 正常生命周期
- **WHEN** 主负责人接收任务、提交反馈，派发人验收通过后归档
- **THEN** 任务依次进入 `RECEIVED`、`FEEDBACK`、`ACCEPTED`、`ARCHIVED`，时间线按顺序记录每次动作及前后状态，版本每次加 1

#### Scenario: 验收退回后再次反馈
- **WHEN** 派发人对反馈中的任务执行退回并填写原因，主负责人再次反馈
- **THEN** 任务先回到 `RECEIVED`，再进入 `FEEDBACK`，退回原因保留在时间线中

#### Scenario: 协作人多次反馈
- **WHEN** 协作人在 `RECEIVED` 状态提交反馈，随后主负责人再次反馈
- **THEN** 两次反馈都写入时间线，任务保持 `FEEDBACK`

### Requirement: 非法状态转换被拒绝
当前状态不允许该动作时，系统 SHALL 返回 409 `INVALID_TRANSITION`，不修改状态、版本和时间线。未知动作 SHALL 返回 400 `INVALID_EVENT`。缺少必填说明 SHALL 返回 400。

#### Scenario: 跳过接收直接反馈
- **WHEN** 主负责人对 `DISPATCHED` 状态的任务提交反馈
- **THEN** 系统返回 409 `INVALID_TRANSITION`，任务仍为 `DISPATCHED`

#### Scenario: 未反馈即验收
- **WHEN** 派发人对 `RECEIVED` 状态的任务执行验收通过
- **THEN** 系统返回 409 `INVALID_TRANSITION`

#### Scenario: 终态后再操作
- **WHEN** 对已归档或已撤回的任务执行任何动作、转派或改期
- **THEN** 系统返回 409 `INVALID_TRANSITION`，时间线不增加事件

#### Scenario: 撤回已验收任务
- **WHEN** 派发人撤回 `ACCEPTED` 状态的任务
- **THEN** 系统返回 409 `INVALID_TRANSITION`

### Requirement: 角色与越权
执行动作的用户 MUST 能读取该任务，并具有表中对应角色。范围外用户 SHALL 收到 404 `NOT_FOUND`；能读取但角色不符 SHALL 收到 403 `FORBIDDEN`。组织上级仅因数据范围可读时，不因此获得接收、反馈或验收权限。判定顺序 SHALL 为：读取范围、角色、版本、状态。

#### Scenario: 协作人尝试接收或验收
- **WHEN** 协作人执行接收，或主负责人执行验收
- **THEN** 系统返回 403 `FORBIDDEN`，任务不变

#### Scenario: 范围外用户操作或读取
- **WHEN** 其他部门员工或其他团队团队长对任务执行动作、读取时间线
- **THEN** 系统返回 404 `NOT_FOUND`，不泄露任务存在性

#### Scenario: 上级仅凭组织范围操作
- **WHEN** 部门老总对本部门成员负责、但由他人派发的任务执行验收
- **THEN** 系统返回 403 `FORBIDDEN`

### Requirement: 版本并发控制
所有动作、转派与改期申请 MUST 携带当前 `version`。版本不一致 SHALL 返回 409 `VERSION_CONFLICT`，不写入状态、事件、审计或通知。成功的动作 SHALL 使版本加 1 并在响应中返回新版本。并发提交同一版本的多个动作时 SHALL 只有一个成功。

#### Scenario: 旧版本提交
- **WHEN** 客户端持有版本 2，而任务已因接收变为版本 3，客户端以版本 2 提交反馈
- **THEN** 系统返回 409 `VERSION_CONFLICT`，时间线不增加事件

#### Scenario: 并发动作
- **WHEN** 派发人同时以相同版本提交撤回，主负责人提交反馈
- **THEN** 恰好一个请求成功，另一个返回 409，任务只有一条对应事件

#### Scenario: 缺少或非法版本
- **WHEN** 请求缺少 `version` 或其不是非负整数
- **THEN** 系统返回 400 `INVALID_VERSION`

### Requirement: 转派
派发人或管理员 SHALL 能对非终态任务申请更换主负责人，申请 MUST 附原因与当前版本，并经现有候选修订复核通过后生效。新主负责人 MUST 是派发人范围内的同公司在职用户且不同于当前主负责人。生效时 SHALL：替换主负责人，若新主负责人原为协作人则移出协作人；原主负责人不再是参与人；状态回到 `DISPATCHED`；追加 `REASSIGNED` 事件记录新旧负责人；版本加 1。复核通过前任务保持原负责人与原状态。

#### Scenario: 转派生效
- **WHEN** 派发人对 `RECEIVED` 任务申请转派给同团队另一成员，复核全部通过
- **THEN** 新负责人可读取并接收任务，任务状态为 `DISPATCHED`，时间线出现 `REASSIGNED`，原负责人不在参与人中

#### Scenario: 复核前不生效
- **WHEN** 转派申请仍在复核中
- **THEN** 任务负责人、状态和版本不变，原负责人仍可反馈

#### Scenario: 转派给范围外或同一负责人
- **WHEN** 派发人申请转派给其他部门用户、非在职用户或当前负责人本人
- **THEN** 系统返回 403、404 或 400 `SAME_OWNER`，不创建复核申请

#### Scenario: 复核期间任务已变化
- **WHEN** 转派申请提交后任务版本因反馈变化，随后复核通过
- **THEN** 生效步骤返回 409 `VERSION_CONFLICT`，任务保持反馈后的状态

### Requirement: 改期
派发人或管理员 SHALL 能对非终态任务申请修改截止时间，申请 MUST 附原因、带时区的新截止时间与当前版本，经现有复核通过后生效。生效时 SHALL 更新截止时间、保持当前状态、追加 `RESCHEDULED` 事件记录新旧截止时间，版本加 1。

#### Scenario: 改期保持进度
- **WHEN** 对 `FEEDBACK` 状态任务的改期申请复核通过
- **THEN** 截止时间更新，任务仍为 `FEEDBACK`，时间线出现 `RESCHEDULED`

#### Scenario: 非法改期
- **WHEN** 新截止时间不带时区、与原截止时间相同，或由非派发人申请
- **THEN** 系统返回 400 或 403，不创建复核申请

### Requirement: 双端一致与失败处理
Web 与 Flutter SHALL 使用同一动作接口与错误码；客户端是否显示按钮不构成授权。任一步骤失败时，状态更新、事件、审计和 outbox 记录 SHALL 在同一事务中整体回滚。

#### Scenario: 事件写入失败
- **WHEN** 状态更新成功但事件写入失败
- **THEN** 整个请求回滚，任务状态与版本保持原值

#### Scenario: 客户端绕过界面直接调用
- **WHEN** 员工绕过界面直接调用验收接口
- **THEN** 系统按角色规则返回 403，与界面隐藏按钮的结果一致
