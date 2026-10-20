# Spec Delta

## MODIFIED Requirements

### Requirement: Task dispatch and lifecycle

任务 SHALL 要求名称、开始时间、日期/小时/分钟截止时间、标签和至少一名参与人，并校验有效派发资格。任务 SHALL 支持多人参与，不保留主负责人字段；任务和任务正文内的完成情况 SHALL 通过审核后的事件留痕。列表 SHALL 不返回独立完成情况或进度备注字段，关键变更 SHALL 审核后生效。

#### Scenario: Valid multi-participant dispatch
- **WHEN** 有派发资格的用户提交名称、开始时间、截止时间、标签和多个有效参与人
- **THEN** 服务端创建待审核任务，保留参与人集合、标签颜色和幂等结果，未审核前旧任务状态继续生效

#### Scenario: Duplicate or unauthorized dispatch
- **WHEN** 重放相同幂等请求、使用相同键提交不同内容或无资格用户直接调用
- **THEN** 相同内容返回同一结果，不同内容返回冲突，无资格请求返回权限拒绝

#### Scenario: Invalid deadline
- **WHEN** 截止时间早于开始时间、缺少分钟或不在组织允许范围内
- **THEN** 请求返回字段级错误，不创建任务或审核记录

#### Scenario: Delete task
- **WHEN** 有权限用户请求删除已创建任务
- **THEN** 系统复用现有审核链创建删除申请，审核通过后任务转为归档/不可用，历史事件和评论仍可审计

### Requirement: Dashboard and logs privacy

服务端 SHALL 提供最多十条置顶重点、本人私人备注、每日唯一草稿/提交/直接修改/已读评语，禁止上级读取草稿与备注。时间区间 SHALL 以上海业务日期、周一起算。移动端 SHALL 只暴露日报入口；日报不使用版本控制、候选版本或审核链，任务版本控制和审核由任务规则单独保证。

#### Scenario: Superior views employee
- **WHEN** 范围内上级查看员工日志
- **THEN** 只返回已提交版本，私人草稿及备注不返回，并支持部门、人员和日期范围过滤

#### Scenario: Daily-only navigation
- **WHEN** Android 用户打开日志功能入口
- **THEN** 只能创建、编辑和查看日报，周报/月报入口和对应接口不会被普通移动端使用

### Requirement: Notifications and analytics

事务 outbox SHALL 最终投递站内消息并去重提醒，SSE 支持序号重放，统计和 CSV 导出 SHALL 共享详情范围及说明分母。消息分类 SHALL 不再提供独立“日志”分类，但评论、审核和任务相关通知 SHALL 保留并能跳转到对应详情。

#### Scenario: Comment notification
- **WHEN** 用户在任务或日志发表评论或回复
- **THEN** 被提及或被回复的授权用户收到评论通知，消息中心不把该通知归入已删除的日志分类

#### Scenario: Cross scope export
- **WHEN** 员工导出统计和日志
- **THEN** 结果只包含本人授权数据，不能通过 ownerId、departmentId 或人员参数越权

## ADDED Requirements

### Requirement: 前端 Mock 日志交互验收

本轮 SHALL 先用 MockRepository 完成日报草稿、提交、24h 内直接修改、锁定及公开评论回复演示，不以此替代真实服务端验收。首次提交 SHALL 固定 submittedAt，后续修改不得重置窗口；恰好 24h SHALL 拒绝编辑。下属日志 SHALL 按最新批注展示部门日志时间线、姓名/内容搜索、同排部门日期控件、作者头像姓名。

#### Scenario: 提交和直接修改
- **WHEN** 作者点击草稿并提交，在首次提交后 24h 内再次修改
- **THEN** 直接保存当前日志且无需审批，首次提交时间保持不变

#### Scenario: 超时及他人修改
- **WHEN** 恰好达到 24h、超过 24h，或其他用户尝试修改
- **THEN** Mock 写入拒绝，详情按钮锁定变灰，正文保持可读

#### Scenario: 公开评论回复
- **WHEN** 有访问权限用户提交非空评论或回复
- **THEN** 显示作者头像、姓名、时间和回复关系；空评论被拒绝，不提供编辑删除评论入口

### Requirement: Shared tags and tag governance

任务和日志 SHALL 共用标签；每条记录最多绑定一个标签。标签 SHALL 具有分类、名称和预设颜色，只有创始人可创建、修改或停用标签，其他角色只能选择有效标签。

#### Scenario: Select existing tag
- **WHEN** 普通用户创建或编辑任务、日志并打开标签选择器
- **THEN** 只能看到其数据范围内的有效分类标签及颜色，记录保存后返回同一颜色

#### Scenario: Unauthorized tag edit
- **WHEN** 非创始人尝试创建、改色、改分类或停用标签
- **THEN** 服务端拒绝请求，已有记录和标签颜色保持不变

#### Scenario: Invalid tag category
- **WHEN** 请求引用不存在、停用或无数据范围授权的标签
- **THEN** 返回明确业务错误，不写入任务或日志

### Requirement: Public comments and replies

任务和日志 SHALL 支持公开评论与回复。评论响应 SHALL 包含作者、头像、创建时间、内容和可选 `parentCommentId`；评论创建后 SHALL 不允许编辑或删除。可见评论必须服从任务、日志和组织数据范围。

#### Scenario: Add comment and reply
- **WHEN** 授权用户在任务或已提交日志上提交评论或回复
- **THEN** 服务端保存评论、作者和时间，回复关联父评论并产生通知

#### Scenario: Comment mutation after creation
- **WHEN** 用户尝试修改或删除已有评论
- **THEN** 服务端返回不支持错误，原评论内容和审计记录不变

#### Scenario: Unauthorized comment read
- **WHEN** 用户请求不在其组织范围内的任务或日志评论
- **THEN** 返回权限拒绝，不泄露评论作者、内容或通知信息

### Requirement: Submitted log twenty-four-hour edit window

服务端 SHALL 以日志提交成功时间 `submitted_at` 为起点计算 24 小时窗口，并返回 `editableUntil`、`canEdit` 和服务端时间。窗口内日志作者可直接修改当前日报，不创建候选版本、不进入审核；达到或超过 24 小时后，编辑和撤回均拒绝。客户端时间不得改变判断结果。

#### Scenario: Direct edit within window
- **WHEN** 当前服务端时间早于 `submitted_at + 24h`
- **THEN** 日志作者可直接更新当前日报内容，服务端不创建版本、不生成审核申请，授权上级读取最新已提交内容

#### Scenario: Edit at boundary
- **WHEN** 当前服务端时间大于或等于 `submitted_at + 24h`
- **THEN** 编辑和撤回请求均被拒绝，返回窗口已关闭错误，已提交内容继续可读

#### Scenario: Client clock skew
- **WHEN** 客户端本地时间与服务端时间不同
- **THEN** 服务端仍按 `submitted_at` 和自身时钟判定，客户端仅展示服务端返回状态

### Requirement: Department-grouped subordinate logs

下属日志接口 SHALL 支持部门筛选、日期筛选、搜索关键字和部门分组返回，并在服务端先执行组织范围校验。返回结果 SHALL 不包含待确认员工、私人草稿或无权限部门数据。

#### Scenario: Filtered subordinate logs
- **WHEN** 管理者提交授权部门、业务日期范围和搜索关键字
- **THEN** 返回按部门分组的已提交日志，结果只包含匹配条件和授权范围内的记录

#### Scenario: Invalid department filter
- **WHEN** 用户提交不属于其数据范围的部门标识
- **THEN** 服务端返回权限拒绝或空结果，不泄露部门是否存在

### Requirement: Administrator-only Web access

Web 工作台及其后端接口 SHALL 仅允许管理员角色访问。普通用户、待确认员工和失效会话 SHALL 被拒绝；Android 普通用户仍可访问其授权移动端功能。权限校验不得只依赖前端隐藏菜单。

#### Scenario: Administrator Web access
- **WHEN** 有效管理员访问 Web 工作台或调用其接口
- **THEN** 请求通过，并按管理员组织范围返回数据

#### Scenario: Ordinary user Web access
- **WHEN** 普通员工或待确认员工访问 Web 工作台或直接调用接口
- **THEN** 返回明确的权限拒绝状态，前端显示无权限页，不返回业务数据

#### Scenario: Android unaffected
- **WHEN** 普通员工使用 Android 访问导图、视图、日志、AI 地图或我的
- **THEN** 继续按其移动端授权范围提供功能，不因 Web 门禁被错误拒绝

### Requirement: Mobile review and version presentation

移动端 SHALL 隐藏任务版本号、版本历史和历史查看入口，但服务端 SHALL 保留任务版本号、并发校验、审核链和审计记录。任务新增、修改和删除均 SHALL 进入既有审核机制，申请人不得审核自己的变更；日报不适用本要求的版本和审核机制。

#### Scenario: Mobile task detail view
- **WHEN** 用户打开任务或日志详情
- **THEN** 任务页面显示当前生效内容、审核状态和必要的操作结果，不显示任务版本历史列表或版本编号；日志页面不显示版本或审核状态

#### Scenario: Self review
- **WHEN** 申请人尝试审核自己创建的任务、删除或日志修订
- **THEN** 服务端拒绝自审，旧生效内容保持不变并记录拒绝原因
