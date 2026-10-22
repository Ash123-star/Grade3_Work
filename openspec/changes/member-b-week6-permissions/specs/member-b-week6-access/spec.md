## Purpose

为第六周真实企业协作演示定义成员 B 负责的日志操作时间窗口、按部门读取下属日报、创始人标签维护以及独立管理员工作台访问规则，确保双端展示与服务端权限一致且保留既有审核和审计能力。

## ADDED Requirements

### Requirement: Role change session revocation and denied access audit
系统 SHALL 在角色变更审核生效事务内撤销目标全部旧会话；管理命名空间401/403 SHALL 持久记录时间、方法、固定入口类别、状态、traceId及可确认身份，不记录令牌、密码、查询串和正文。

#### Scenario: Applied role change
- **WHEN** 独立审核正式改变用户角色
- **THEN** 旧会话在普通及管理接口均返回401，新登录遵守新角色权限；驳回不撤销

#### Scenario: Anonymous and forbidden access
- **WHEN** 匿名或无管理员权限用户访问管理命名空间
- **THEN** 分别返回401或403并留下脱敏审计，写审计异常不能放行请求

### Requirement: HCJ client integration
客户端 SHALL 复用已发布日志修订接口，明确审核后生效；回复字段转换保持身份和关系；所有草稿也 SHALL 尊重服务端canEdit=false。

#### Scenario: Submitted revision
- **WHEN** 用户在窗口内填写修订内容和理由
- **THEN** 客户端发送revisions而非直接修改，提示审核后生效

#### Scenario: Withdrawn expired draft
- **WHEN** 服务端返回撤回草稿canEdit=false
- **THEN** 客户端禁止编辑，不因草稿状态绕过窗口

### Requirement: Public immutable log comments
P1，系统 SHALL 允许所有已有日志读取权限的人评论和回复已提交日志，公开范围沿用日志权限；超过24小时仍可评论，评论 MUST NOT 被编辑或删除。

#### Scenario: Comment and reply
- **WHEN** 有权限用户追加1至2000字评论或回复同一日志的评论
- **THEN** 事务写入不可变评论，返回作者和时间，通知日志作者及仍有权限的被回复人并去重

#### Scenario: Invalid or inaccessible comment
- **WHEN** 请求访问草稿或范围外日志、回复其他日志评论、提交空白或过长内容
- **THEN** 拒绝请求且不新增评论或通知，不泄露目标正文

### Requirement: Read only task audit workspace
P1，独立工作台 SHALL 为当前ADMIN提供本公司任务审计分页展示，覆盖任务事件、审核申请、决定和生效，保留前后值、操作者、时间与理由。

#### Scenario: Browse task audit
- **WHEN** 管理员打开任务审计并按可选任务ID翻页
- **THEN** 只返回公司内匹配事件，页面呈现数据、空、加载或失败状态且无修改删除操作

#### Scenario: Unauthorized audit
- **WHEN** 非ADMIN访问或管理员查询其他公司任务ID
- **THEN** 分别拒绝403或返回空列表，不泄露其他公司记录

### Requirement: First submission edit window
P0，日志本人和管理员的已提交修订 SHALL 在首次 submitted_at 后不足 24 小时申请；草稿首次提交前可编辑；撤回重提不得重置窗口，所有时间由服务端判定。响应 SHALL 提供 submittedAt、editableUntil、canEdit、canWithdraw。

#### Scenario: Before deadline
- **WHEN** 本人在提交后 23 小时 59 分提交有效修订
- **THEN** 创建审核申请，原值审核前不变，申请可在窗口外完成独立审核

#### Scenario: Expired or exact boundary
- **WHEN** 到达或超过 24 小时后请求修改、撤回或撤回后的草稿写入
- **THEN** 返回 409 LOG_EDIT_WINDOW_EXPIRED，管理员及修改手机时间均不能绕过

#### Scenario: Resubmission
- **WHEN** 本人在窗口内撤回并重新提交
- **THEN** 保留首次 submitted_at，旧候选无法通过旧 version 覆盖新状态

### Requirement: Department subordinate query
P1，管理者 SHALL 按部门、日期、关键词查询授权范围的已提交下属日志，返回当前页 groups 及兼容 items 分页；草稿及范围外内容 MUST NOT 返回。

#### Scenario: Grouped query
- **WHEN** 管理者组合部门日期关键词查询
- **THEN** 返回匹配且授权的日志、当前作者及部门信息，total 仅统计匹配授权日志

#### Scenario: Invalid or unauthorized query
- **WHEN** 员工访问下属入口、关键词超过 100 字或选择范围外部门
- **THEN** 分别拒绝 403、拒绝 400、返回与未知部门一致的空结果，不泄露草稿或部门存在性

### Requirement: Founder tag management
P0，系统 SHALL 仅允许有效创始人维护标签分类、颜色、状态；其他用户只能选择授权范围内已有标签，关联记录与审计不得因停用被删除。

#### Scenario: Authorized management and selection
- **WHEN** 创始人维护公司范围内标签且员工选择可见的有效标签
- **THEN** 操作成功且任务日志使用同一标签定义

#### Scenario: Forged tag access
- **WHEN** 非创始人直接写标签或用户绑定不可见标签
- **THEN** 服务端拒绝，不改变标签或业务关联

### Requirement: Administrator workspace
P0，独立 web/ 与管理接口 SHALL 仅允许当前 ADMIN；FOUNDER 不自动获得权限；Android 普通业务及 Flutter Web 联调入口保持原权限。

#### Scenario: Admin access
- **WHEN** 有效管理员进入独立工作台
- **THEN** 页面和管理接口可用并保持原业务数据范围

#### Scenario: Revoked or unauthorized session
- **WHEN** 未登录、普通员工、创始人或被撤销 ADMIN 的旧会话访问管理接口
- **THEN** 未登录返回 401，非管理员返回 403；停用后返回 401，Web 清理受限内容且不再继续加载
