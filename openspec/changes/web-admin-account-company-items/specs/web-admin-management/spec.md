## ADDED Requirements

### Requirement: Administrator management entry
US-01，优先级 P0；作为管理员，我希望通过独立 Web 管理入口维护公司基础信息。范围为登录、首次改密、路由、会话恢复和退出。系统 SHALL 仅允许当前公司 ACTIVE ADMIN 进入管理端，默认进入账号管理，刷新深链前通过服务端重新确认身份；FOUNDER MUST NOT 自动获得权限，待确认账号 MUST NOT 读取管理数据。现有 AI/任务审计入口 SHALL 保持可达但不在本批新增能力范围内。

#### Scenario: Login and restore management route
- **WHEN** 有效管理员登录或刷新公司事项管理深链，且已完成首次改密
- **THEN** 显示对应管理页面与当前公司/身份，默认入口为账号管理，后台不因进入管理页自动触发 AI 分析

#### Scenario: Password change required
- **WHEN** 初始化管理员尚需首次改密
- **THEN** 仅展示改密流程，不加载管理数据，改密成功后清理旧会话并要求重新登录

#### Scenario: Non administrator and revoked session
- **WHEN** 未登录、PENDING、仅FOUNDER、非ADMIN、被撤权或已停用账号直接访问管理查询/写入
- **THEN** 服务端按会话无效返回401、身份/状态不允许返回403；Web清空受限内容、取消在途请求并提示重新登录或无权限，晚到响应不得恢复旧数据

### Requirement: Scoped account directory
US-02，优先级 P0；作为管理员，我希望查找本公司账号并看到可维护的完整信息。范围为账号列表、详情和组织选择。系统 SHALL 在服务端按本公司、姓名/登录账号关键词、状态、部门进行过滤与分页，默认包含 PENDING、ACTIVE、DISABLED；搜索最多100字，cursor为非负整数，limit为1–100，响应为items/total/nextCursor。详情 SHALL 返回组织、直属上级、角色、状态、派发资格、version及关联待审申请；账号/手机号只读，companyReviewer只读。系统 MUST NOT 返回密码、密码哈希、token、私人备注或未提交草稿。

#### Scenario: Filter disabled accounts
- **WHEN** 管理员组合关键词、部门及DISABLED筛选并翻页
- **THEN** 只返回本公司匹配账号及对应total，详情包含编辑所需版本；不改变Android普通选人接口排除停用账号的行为

#### Scenario: Cross company identifier and invalid pagination
- **WHEN** 管理员访问其他公司账号ID、使用范围外部门筛选或提交超长关键词/非法分页
- **THEN** 对象详情与不存在ID一致返回404，范围外部门返回空列表，非法输入返回400且不泄露范围外数据

### Requirement: Reviewed account maintenance
US-03，优先级 P0；作为管理员，我希望确认员工归属并维护账号组织和权限。范围为姓名、部门、团队、直属上级、角色、派发资格与ACTIVE/DISABLED状态。系统 SHALL 使用version和必填reason创建候选，正式账号数据在独立审核通过前保持原值。待确认员工归属 SHALL 优先使用其已有MEMBERSHIP申请；没有申请时管理员以自身身份提交明确部门与EMPLOYEE角色的USER候选，MUST NOT 伪造员工身份、注册管理员或在归属确认中默认提权。

#### Scenario: Activate pending employee
- **WHEN** 管理员确认待确认员工的有效部门并由当前独立复核人按审核链通过
- **THEN** 员工变为ACTIVE EMPLOYEE，组织信息与版本同步更新，Android与Web后续读取遵循同一新范围，并可查到前后值、操作者、理由和审核链

#### Scenario: Change role transfer or disable
- **WHEN** 管理员提交调岗、角色、派发资格或停用修改并完成独立审核
- **THEN** 审核前旧值仍生效，审核后旧会话的下一次请求应用新角色/组织范围，停用会话返回401

#### Scenario: Invalid organization or last administrator
- **WHEN** 修改包含无效角色、跨公司部门、团队与部门不匹配、汇报循环、缺少管理角色对应组织、空理由，或停用/降级最后一名有效管理员
- **THEN** 服务端拒绝且不改变正式账号，页面定位错误并保留可修正输入，不能只靠前端隐藏选项

#### Scenario: Conflicting account revisions
- **WHEN** 另一候选已先行修改同一账号，旧候选尝试最终生效
- **THEN** 返回409，审核和业务事务回滚，不覆盖新版本，页面显示冲突并允许刷新对照后重新申请

### Requirement: Company important item maintenance
US-04，优先级 P0；作为管理员，我希望维护公司十大重要事项并预览发布效果。范围为查询、详情、新增、编辑、置顶/取消置顶、排序、归档与只读预览。系统 SHALL 对本公司事项提供关键词、归档筛选及分页，title为1–200字、纯文本text不超过20000字、position为0–10000整数、reason为1–2000字且非空白。系统 SHALL 将完整内容及version提交为候选，新建version为0；仅审核通过后更新正式数据。系统 SHALL 最多允许10条未归档置顶事项，不足10项不补造数据，历史总条数不受10条限制；归档只做逻辑归档并保留历史。编辑区 SHALL 区分生效与待审预览，不提供直接发布或硬删除。

#### Scenario: Create edit and archive through review
- **WHEN** 管理员提交合法新增、正文编辑、position调整、置顶修改或归档候选，独立审核通过
- **THEN** 仅对应事项更新正式值和版本并记录审计；归档项从公开有效列表移除，仍可在管理归档查询查看，未通过前公共读取保持原内容

#### Scenario: Pin capacity and concurrent approvals
- **WHEN** 已有10条未归档置顶事项时再次置顶，或两条候选并发竞争最后一个置顶名额
- **THEN** 服务端最终生效事务在公司锁内检查容量，超限请求返回PIN_LIMIT且不写入任何部分审核/业务数据，最终有效置顶数量不超过10

#### Scenario: Invalid item and version conflict
- **WHEN** 标题/理由空白、文本过长、position小数/越界、布尔字段类型错误，或以旧version申请最终生效
- **THEN** 分别以400或409拒绝，正式记录保持不变，界面明确标出字段错误或版本冲突，不自动覆盖

#### Scenario: Shared published content
- **WHEN** 公司事项审核生效后，管理员刷新Web预览，已激活员工刷新Android公司首页/列表
- **THEN** 双端基于同一公共契约读取已发布值，首页以pinned降序、position、id取前10条未归档事项；不足10条置顶时可补入其他未归档事项，Android首页仍只读，私人备注不出现在管理响应中

### Requirement: Independent review and management history
US-05，优先级 P0；作为管理员，我希望知道管理修改何时生效，并处理分配给我的复核。范围为USER、MEMBERSHIP、COMPANY_ITEM三类本人申请、分配审核和相应管理审计。系统 SHALL 在服务端按类型/状态/目标与分页过滤，维持现有本人申请或分配给本人范围；详情展示生效/候选前后值、理由、业务版本、审核步骤与结论。仅当前独立审核人 SHALL 提交决定，申请人 MUST NOT 自审；驳回理由必填，无独立审核人时 SHALL 保持待审并说明。管理审计 SHALL 限本公司相应对象且不可修改删除。

#### Scenario: Review decision and history
- **WHEN** 独立审核人在有权步骤通过或填写理由驳回
- **THEN** 通过按既有审核链推进，最终通过才事务更新业务、审计与outbox；驳回不影响正式值，管理员可按目标追溯历史

#### Scenario: Self review unassigned review or no reviewer
- **WHEN** 申请人自审、未分配管理员决定、查看范围外申请，或缺少独立复核人
- **THEN** 未授权操作被拒绝；无复核人的候选保持待审，不能自动通过，重路由仍受原申请人及尚无已处理步骤规则约束

#### Scenario: Repeated decision and uncertain request result
- **WHEN** 对终态申请再次决定或提交候选/决定后网络中断无法确认结果
- **THEN** 重复决定返回409且无重复生效，Web不自动重放POST，而是保留输入并提示刷新本人申请/详情核对结果

### Requirement: Polished accessible management experience
US-06，优先级 P0；作为管理员，我希望在清晰美观的页面中完成维护并能从失败中恢复。范围为登录及账号管理、公司十大重要事项两个独立主页面，相关审核记录置于各页抽屉，AI地图不出现在主导航。Web SHALL 使用统一组件库的侧栏、工具栏、表格、分页、表单、抽屉和步骤条，采用奶油白底、薄荷绿/珊瑚橙点缀、深色正文、圆角卡片和统一间距。Web SHALL 提供加载、空数据、筛选无结果、请求失败重试、提交中、无权限及冲突状态，禁止使用虚构生产数据填充页面。正文 SHALL 以纯文本安全渲染，颜色之外提供文字状态，正文对比度至少4.5:1。

#### Scenario: Desktop and narrow window
- **WHEN** 在1440×900、1024×768或768×1024浏览管理页，或将浏览器缩放到200%
- **THEN** 操作区、筛选和错误提示可到达，窄屏导航折叠/抽屉全宽，宽表格局部滚动而不遮挡提交按钮，不用插图占据主要数据空间

#### Scenario: Keyboard and assistive feedback
- **WHEN** 用户通过键盘打开抽屉、触发表单错误并关闭抽屉
- **THEN** 焦点进入抽屉、错误关联字段、加载/成功消息可播报，关闭后焦点回到触发按钮，关键操作不要求鼠标悬浮或拖拽

#### Scenario: Request failure and stale response
- **WHEN** 后端返回失败、列表请求乱序或用户在请求中退出
- **THEN** 页面显示可重试错误及可用traceId，保留未提交编辑但不伪称保存成功，旧响应不能覆盖新筛选结果或退出后的空状态，日志不包含密码/token/私人内容

#### Scenario: Dependencies and assets
- **WHEN** 构建发布使用组件库、图标或OpenMoji插图
- **THEN** 依赖有锁文件及官方/GitHub来源与许可证记录，按需加载；OpenMoji从本地加载并保留CC BY-SA 4.0署名、版本、来源及修改说明，不使用百炼或外部图片热链
