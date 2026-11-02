## MODIFIED Requirements

### Requirement: Candidate revisions and independent review
除 `MEMBERSHIP` 注册成员确认外，关键修改 SHALL 保持旧版直到唯一直属上级审核通过，禁止普通申请人自审、要求驳回原因和版本校验并记录审计；审核不得再串行经过团队、部门、公司多级。`MEMBERSHIP` 注册确认 SHALL 继续由管理员审批，不转交直属上级且不适用创始人自动免审。有效创始人发起其权限内的其他审核型动作 SHALL 经同样业务及版本校验后自动批准并生效，记录系统免审依据，不需要上级步骤且不扩大其原有发起权限。本人日报24小时内正文修改为无需审核的明确例外。

#### Scenario: No independent reviewer
- **WHEN** 非创始人没有配置有效的直属上级
- **THEN** 保持待审和旧值，不随意选择更高级人员、不自动批准，显示审核人未配置

#### Scenario: Conflict and self review
- **WHEN** 普通申请人自审或生效时版本已变化
- **THEN** 拒绝且不覆盖生效内容，创始人自动批准也不能绕过版本冲突

#### Scenario: Review policy change
- **WHEN** 新单级规则启用或管理员查看原多级策略设置
- **THEN** 不再创建团队/部门/公司链，移除可恢复多级链的开关；单级审核人按已确认的组织规则路由，历史记录保留

#### Scenario: Direct manager changed or historical pending request
- **WHEN** 审核时直属关系改变、上级停用，或旧多级待审申请迁入新规则
- **THEN** 旧审核人无法继续批准，重路由保留历史且只安排一个当前有效直属上级；无上级保持待审，不能把旧链中间同意当成最终批准

#### Scenario: Founder automatic approval
- **WHEN** 当前有效创始人发起其已有权限允许的关键变更
- **THEN** 同事务业务生效、APPROVED结果、审计与outbox一致，不生成等待上级任务；非法请求失败不产生半完成结果

#### Scenario: Membership confirmation remains administrator-only
- **WHEN** 待确认员工提交或等待 `MEMBERSHIP` 注册成员确认
- **THEN** 申请仍由管理员处理，不路由给直属上级，不因申请人或审核人为创始人而自动批准；旧待审成员确认迁移后仍保留一个有效管理员审核步骤，无管理员时保持待审且不应用候选

#### Scenario: Historical founder request and actions without review
- **WHEN** 系统升级时存在创始人历史待审候选，或创始人执行原本无需审核的动作
- **THEN** 升级不擅自批量生效历史业务；创始人明确继续或重提本人旧申请后，按当前权限/版本校验并幂等自动批准；原本无审核的合法动作继续直接执行，不新增人工审核步骤

### Requirement: Dashboard and logs privacy
服务端 SHALL 保留最多十条置顶重点、本人私人备注、每日唯一日志及历史/评论。本人日志仅上海今天/昨天/前天可首次提交；首次提交后不足24小时可直接改work，无需审核且时间不重置，满24小时只读。移动端停用阅读登记，历史已读不删除；上级不可读草稿与私人备注。日期按上海、周一起算。

#### Scenario: Superior views employee
- **WHEN** 范围内上级查看员工日志
- **THEN** 只返回已提交工作正文与评论所需数据，不返回私人草稿/备注，不因查看而自动登记已读

#### Scenario: Direct diary edit and compatibility
- **WHEN** 本人合法窗口内修改已提交正文，或旧客户端通过修订/撤回重提路径试图越过窗口
- **THEN** 合法修改原子增加版本和历史且无需审核；旧路径不得延长首次提交时间或使过期候选覆盖新正文

## ADDED Requirements

### Requirement: Personal profile fields and superior contact visibility
服务端 SHALL 允许本人按版本修改介绍、手机号、邮箱、性别、年龄及本人上传头像，拒绝自行修改姓名/职位/部门/角色。手机号更新与权威身份字段及唯一约束一致，不虚报验证。电话/邮箱 SHALL 仅本人、实际组织关系的所有上级及既有合法组织管理员可见，不向平级或无关高职级人员批量泄漏。

#### Scenario: Valid profile update and ancestor read
- **WHEN** 本人保存合法电话等可写字段，直属及递归上级在有效范围内读取该资料
- **THEN** 保存原子生效且其他字段保留，两类上级可读真实资料，个人重点不参与资料更新

#### Scenario: Forged fields duplicate phone and hierarchy change
- **WHEN** 请求包含保护字段、重复手机号、他人头像，或调岗后原上级再读取
- **THEN** 服务端返回可辨校验/冲突/范围错误，不部分更新、不泄露资料，不沿用旧缓存授权

### Requirement: Analytics dimensions and drilldown consistency
服务端 SHALL 对日期、部门/团队/人员及指标白名单进行当前权限校验，提供真实条形分组、折线趋势、任务阶段分布及同范围分页明细，返回区间、粒度、数量、比率分子/分母与更新时间。汇总、图表、钻取、导出 SHALL 共享数据范围，无法形成的历史维度不以当前快照伪造。

#### Scenario: Interactive chart and export
- **WHEN** 同一用户选择某部门月份并点选阶段或某天数据点后导出
- **THEN** 图中值、分页明细与导出在同一过滤条件下一致，个人范围账号不能选任意部门ID

#### Scenario: Empty invalid and revoked analytics query
- **WHEN** 时间区间无数据、分母为零、维度非法或权限在钻取后撤销
- **THEN** 区分无数据与零值，拒绝非法维度，停止返回旧范围明细；不泄漏原始手机号或私人草稿

### Requirement: Mobile P0 task and diary query contracts
服务端 SHALL 为移动端接收任务卡片、任务网格查询、下属日志范围查询和下属日志月份状态提供正式 HTTP 契约。所有 ID 过滤都 SHALL 与当前 Actor 的公司和可见范围取交集；区间筛选 SHALL 使用显式上海业务时间范围和左闭右开边界；分页 SHALL 返回稳定排序、`items/total/nextCursor`。

#### Scenario: Received task history and interval intersection
- **WHEN** 有效成员请求 `GET /tasks/received-card` 或以 `from/to/ownerId` 请求 `GET /tasks`
- **THEN** 卡片返回当前有权接收的完整历史及真实派发事件时间，区间查询返回任务时间跨度与 `[from,to)` 相交的记录；普通旧 `date/period` 请求仍兼容

#### Scenario: Range boundaries and unauthorized member
- **WHEN** 任务仅在区间右边界开始、在左边界结束，或请求者筛选不可见员工
- **THEN** 右边界不纳入、左边界相交语义按任务截止时间明确处理；越权筛选拒绝或按已定安全策略返回一致不可见结果，不泄漏员工/任务数据

### Requirement: Subordinate diary calendar and employment date
服务端 SHALL 支持 `GET /logs/subordinates?ownerId&from&to&departmentId&search` 和 `GET /logs/subordinates/calendar?ownerId&month`。月状态 SHALL 返回上海自然月每一天的 `SUBMITTED/MISSING/FUTURE/UNKNOWN` 状态、员工 `employmentStartDate`（可空）与必要日志 ID；仅返回完整授权范围内已提交日志事实。未知入职日 SHALL 不推算，历史未知区间返回 `UNKNOWN`；新确认成员 SHALL 从确认生效业务日期开始计入职。

#### Scenario: Complete month status and unknown start date
- **WHEN** 授权上级查询完整月份，且成员入职日已知或为空
- **THEN** 已提交日期为 `SUBMITTED`，已到且在职未提交为 `MISSING`，未来为 `FUTURE`，空入职日期所覆盖的早期日期为 `UNKNOWN`；月内每日均有状态，不以分页首屏推算缺交

#### Scenario: Subordinate range and access revocation
- **WHEN** 下属日志筛选携带日期、部门、搜索和成员参数，或查询期间关系已撤销
- **THEN** 参数组合在服务端生效且草稿不可见；越权/失权请求不返回成员资料或日志，撤权后重试不能读取旧范围

### Requirement: Versioned direct diary content update
服务端 SHALL 提供 `PUT /logs/{id}/content`，仅允许有效作者在首次提交后24小时窗口内以 `{work,version}` 修改已提交正文。校验、历史版本写入、旧待审正文候选失效和正文更新 SHALL 在同一事务完成；成功 SHALL 保留原 `submitted_at`。首次提交 SHALL 仅允许上海今天、昨天或前天，三日限制不延长既有日志的24小时编辑窗口。

#### Scenario: Direct update within and at the 24-hour boundary
- **WHEN** 作者使用当前版本在 `submitted_at + 24h` 之前修改，或恰好到达/超过边界时修改
- **THEN** 窗口内只更新正文并写历史，不产生审核申请且保留首次时间；边界及之后返回可区分的窗口错误，不产生部分写入

#### Scenario: Concurrent update, other author, and stale review candidate
- **WHEN** 两个更新竞争同一版本、非作者修改、日志已撤回/无效，或旧正文审核候选晚于新正文尝试生效
- **THEN** 仅一个当前版本写入成功，其他请求返回409/403；旧候选不得覆盖新正文，失败不写部分历史/审计

### Requirement: Analytics summary, details, and export share authorization
服务端 SHALL 让 `GET /analytics`、`GET /analytics/details` 和 `GET /analytics/export` 共享日期周期、部门/团队/员工过滤解析和同一授权范围。服务端 SHALL 校验指标白名单、分组和游标分页；响应 SHALL 提供移动端图表字段，趋势只基于实际保存事件。CSV SHALL 与同条件汇总/明细使用相同过滤，并保留公式注入转义和数量上限。

#### Scenario: Summary, drilldown, and CSV parity
- **WHEN** 同一授权用户使用相同日期、组织过滤请求汇总、分页明细和 CSV
- **THEN** 三者的对象集合和聚合口径一致，CSV 分页至完整结果，越权条件不被忽略

#### Scenario: Invalid metric and zero denominator
- **WHEN** 请求不支持的指标/分组、越权部门/团队/人员或零分母数据
- **THEN** 无效/越权参数返回统一 400/403，不返回旧缓存；零分母按 null/暂无表达，不伪造成 0% 成功率或历史趋势

#### Scenario: Unknown employment denominator and current snapshots
- **WHEN** 授权范围包含未知入职日或无法确定历史在职区间的已提交日志，或任务经历修订及重新验收
- **THEN** 日报率 SHALL 返回 `denominatorKnown=false` 和 `rate=null`；按期验收率以区间首次实际验收为分母，最新REVISED后的有效验收不晚于当前deadline才纳入分子；组织分组和派发任务阶段分布明确为当前归属/阶段口径，不宣称历史快照

### Requirement: Direct-manager review and founder exemption persistence
除 `MEMBERSHIP` 外，关键变更 SHALL 仅分配一个当前有效直属上级人工审核步骤，按实时同公司 reporting relation 验证审核人、申请人、自审和当前版本；未配置有效直属上级时保持待审且没有可操作步骤。`MEMBERSHIP` 注册成员确认 SHALL 继续分配给管理员，不能被直属关系或创始人身份绕过。有效创始人对其已有权限内的其他新审核型操作 SHALL 在同一事务校验并应用，记录 `APPROVED` 与 `FOUNDER_EXEMPT` 审计/outbox，不产生人工步骤。管理员不自动获得创始人免审。旧已决定步骤 SHALL 保留为历史审计；旧待审步骤失效后按当前规则迁移，历史创始人候选不自动应用。

#### Scenario: Direct manager approval and stale relationship
- **WHEN** 唯一直属上级以当前 expectedVersion 决定申请，或旧审核人已不再是当前直属上级
- **THEN** 直属上级单次决定后申请立即生效；失效审核人被拒绝，审核结果不继续路由祖先，版本/关系冲突不写部分结果

#### Scenario: Founder exemption and legacy pending requests
- **WHEN** 创始人发起已有权限的审核型修改，或服务升级时存在创始人历史待审候选
- **THEN** 新请求按原业务权限和版本校验后原子生效并留下免审审计；迁移不应用历史候选，旧步骤留存但不再可执行

#### Scenario: Membership remains an administrator exception
- **WHEN** 新注册或存量 `MEMBERSHIP` 申请待确认
- **THEN** 只由有效管理员审核，迁移后最多有一个有效管理员步骤；直属上级单级路由和创始人免审均不适用

#### Scenario: Explicit founder continuation and visible decision history
- **WHEN** 有效创始人通过 `POST /reviews/{id}/reroute` 明确继续本人非MEMBERSHIP历史待审申请，或仍有当前审核权限的审核人读取已决历史
- **THEN** 服务端 SHALL 在原业务权限和目标版本校验后原子免审应用并记录FOUNDER_EXEMPT，重复已免审请求返回原结果；已决历史在列表及详情中一致可见，失权或SUPERSEDED步骤不能提供读取权限
