## MODIFIED Requirements

### Requirement: Candidate revisions and independent review
关键修改 SHALL 保持旧版直到配置的唯一直属上级审核通过，禁止普通申请人自审、要求驳回原因和版本校验并记录审计；审核不得再串行经过团队、部门、公司多级。有效创始人发起其权限内的动作 SHALL 经同样业务及版本校验后自动批准并生效，记录系统免审依据，不需要上级步骤且不扩大其原有发起权限。本人日报24小时内正文修改为无需审核的明确例外。

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
