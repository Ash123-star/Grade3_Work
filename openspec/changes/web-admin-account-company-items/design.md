## Context

2026-10-23实施调整：用户明确只需两个主页面（账号、公司事项），审核记录改为页内抽屉；旧AI入口仅保留`/legacy`直接地址，不在主导航显示。新增管理接口统一为`/api/admin/workspace/management/*`，对应`/api/management/*`路由与独立管理应用层；账号、事项、options、reviews沿用本文权限与候选原则，不再改动通用people/reviews查询语义。当前批次实现两页和必需契约，Issue/生产/PR等外部事项保留真实阻塞记录。

本段记录实施前基线，当前实施与验证见 `docs/web-admin-management-validation.md`。调查依据：`web/package.json`、`web/src/App.vue`、`server/.../Security.java`、organization 的 Controller/Application/Repository/Policy、review Controller 及 dashboard Controller/ReviewedRevisionApplication。

- Web 已有 Vue 3、Vite、TypeScript、Vue Flow、Playwright，页面集中在 App.vue，使用 sessionStorage 保存会话；当前没有通用管理路由或组件库。
- 登录已有 ADMIN 检查、首次改密；`/api/admin/workspace/*` 在服务端校验实时身份后按白名单转发。当前白名单尚不含账号、公司事项、审核管理路径，不能仅添加前端菜单。
- `/organization/people` 是业务选人接口，默认排除 DISABLED，搜索姓名/部门，字段缺少完整编辑上下文，不能承担完整账号管理。
- `/organization/users/{id}/revisions` 已支持组织/角色/状态候选，包含汇报循环、团队归属及最后一个有效管理员保护。`MEMBERSHIP` 是员工本人申请，不能伪造员工身份由管理员提交。
- 公司事项已有读取与候选创建，Controller 仍直接执行部分 SQL，查询排除归档；最终审核应用已锁公司并检查最多十项置顶。新增管理逻辑应分层，不复制现有 Controller SQL。
- 主规格沿用候选版本、独立复核、跨端一致；活动 week6 变更约束独立 Web 仅 ADMIN。`initial-product/analytics-web` 历史规划默认导图且面向更宽业务范围，本批仅将管理子入口默认设为账号管理，不覆盖未来完整门户要求；实施时同步基线说明。

## Goals / Non-Goals

**Goals:** 管理员用统一管理台完成账号、公司重要事项与相关审核闭环；真实服务端限制权限和版本；美观且支持键盘、缩放、失败恢复。验收范围对应规格 US-01 至 US-06。

**Non-Goals:** 不新增业务分析、任务/日志编辑、AI、重置他人密码、账号硬删除、批量操作、组织树编辑器；不更改 Android 导航或首页只读规则；不额外接入云服务。部门/团队/直属上级仅从已有组织中选择。

## Decisions

### 1. 延续工程，按管理模块拆分

| 路线 | 收益与代价 | 选择 |
| --- | --- | --- |
| 现有 Vue 3 + Element Plus | 复用构建与部署，组件覆盖表格、表单、抽屉、分页、步骤条，需统一主题 | 推荐 |
| 切换 React / 另建管理站 | 可用管理模板多，但重建认证、构建和部署，割裂现有功能 | 不采用 |
| 继续原生手写全部控件 | 依赖少，但校验、焦点、弹窗、表格重复开发较多 | 不采用 |

引入 `element-plus`、`@element-plus/icons-vue`、`vue-router`、`pinia`，安装时核对与当前 Vue/TS/Vite 的官方兼容范围，锁定 lockfile。组件和图标按实际使用导入，先不用自动导入插件、拖拽库、富文本库或图表库。依赖来源仅官方/GitHub，记录许可证与版本。已有 Vue Flow 随旧页面按路由加载，避免带入管理首屏。

实施结构：`web/src/admin/AdminApp.vue`、`AccountsView.vue`、`CompanyItemsView.vue`、`ReviewDrawer.vue`、`router.ts`、`session.ts`、`api.ts`、`admin.css`。Pinia 仅保存会话；抽屉表单和候选内容不长期持久化。共享请求层处理 auth/me、错误码、traceId、取消与响应代次，避免过期响应覆盖新筛选或退出后重新填充数据。

主路由只有 `/admin/accounts`、`/admin/company-items`；`/` 默认指向账号管理，登录成功后恢复受允许的管理深链。审核记录通过各页抽屉访问，没有第三个主页面。原 AI 办事、分析、任务审计仅保留 `/legacy` 兼容路由，迁移旧用例，不加入主导航、不默认触发 AI 请求。

### 2. 清晰的轻量管理视觉

左侧约 224px 导航，顶部面包屑、公司和当前管理员，中心查询工具栏+列表，右侧 520–640px 详情/编辑抽屉；较窄窗口导航折叠、抽屉全宽。账号默认页，无虚构统计数字或装饰报表。

复用基线色：底色 `#FFF9F0`、薄荷绿 `#75C9B7`、珊瑚橙 `#FF9D87`、正文 `#263238`；浅色作为背景，按钮文字/焦点色另选足够对比度的深色。统一 8px 间距尺度、16px 卡片圆角、轻阴影、表格斑马纹/悬浮反馈。状态同时用文字与图标，待审与生效明显区分。

事项页主列表支持生效/归档筛选；侧面预览当前已发布的首页前十项（按 pinned 降序、position、id），编辑候选预览明确标注“待审核”。排序用数字位置输入和预览，不用拖拽隐式提交；每次保存是一个明确候选，不承诺整表原子重排。可选少量本地 OpenMoji 空状态插图，使用时保留作者、来源、版本、CC BY-SA 4.0 与修改声明。

### 3. 权限和账号管理

比较“前端隐藏按钮”“另建管理员身份系统”“复用当前 ADMIN+组织范围”：选择第三种。所有管理查询和写入在应用层再次校验 ACTIVE ADMIN、本公司，不能只依赖转发过滤器。公共 Android 接口保持原有角色权限，不全局把公司事项业务改为 ADMIN-only。

auth/me 校验通过前不拉管理数据；首次改密先完成既有改密流程。待确认、非 ADMIN、被撤销角色和停用会话均不展示管理内容；401 清理敏感缓存并要求重登，403 区分首次改密/待确认/无管理权限，停止管理请求，保留可理解的原因。

账号编辑字段限定 name、departmentId、teamId、managerId、role、status、dispatchEnabled；companyReviewer 在本批只读，避免将审核职责配置混入账号基础维护。登录名/手机号只读，密码/哈希/token/私人内容不返回。待确认员工默认确认 EMPLOYEE 与有效部门，优先审核其已提交 MEMBERSHIP；尚无申请时管理员以自身身份创建 USER 候选 `status=ACTIVE, role=EMPLOYEE` 并选定有效部门，不伪造员工申请人。存在待审归属时展示关联申请，禁止引导同时提交冲突确认。

### 4. 契约补齐，不复用缺字段的选人接口

比较扩展 `/organization/people` 与新增 ADMIN 查询：选择新增，避免改变 Android 选人排除停用账号的语义。管理转发前缀为 `/api/admin/workspace/management`，直接业务路由为 `/api/management`；auth 登录/改密/退出沿用 `/api/auth/*`。以下为管理前缀后的路径。

| 方法与路径 | 请求与结果 | 实施方式 |
| --- | --- | --- |
| GET `/accounts`、`/accounts/{id}` | search（姓名/登录账号，≤100字）、status、departmentId、cursor≥0、limit 1–100；默认含所有状态；详情提供完整编辑字段、version、关联待审 ID | 新增 ADMIN-only 查询；不输出密码或多余私人字段 |
| GET `/options` | 本公司部门、团队和有效管理者 | 专用查询，不改变公共组织选人接口 |
| POST `/accounts/{id}/revisions` | 既有字段白名单、version、reason；返回 review ID/status | 复用组织应用；ACTIVE 确认和其他修改仍审核后生效 |
| GET `/items`、`/items/{id}` | search≤100字、archived=false/true/all、cursor、limit；字段 id/title/text/pinned/archived/position/version，列表含正式前十预览及置顶容量 | 新增 ADMIN-only 查询，规范化 body.text，不修改公共列表形状 |
| POST `/items/revisions` | id（新增省略）、version（新增0）、title、text、pinned、archived、position、reason | 复用候选契约，新增逻辑下沉 dashboard 应用/领域/基础设施；提交完整内容避免遗漏字段归零 |
| GET `/reviews`、`/reviews/{id}` | category=accounts/items、cursor、limit；本人申请/分配审核范围 | 本页仅 USER/MEMBERSHIP/COMPANY_ITEM，不因 ADMIN 变成全公司任意审批人；状态/对象过滤仍为未完成规划 |
| POST `/reviews/{id}/decision`、`/reviews/{id}/reroute` | 既有 approve/reason 或空重路由请求 | 仅当前独立审核人决定；重路由仍只允许申请人且无已处理步骤 |
| 审计查询（未完成规划） | 原规划的管理审计对象过滤尚未实现 | 本批抽屉显示审核申请/决定历史；不将其称为完整审计查询 |

分页统一保留 `items,total,nextCursor`，nextCursor 沿用字符串数字偏移，终页由 total 判断；筛选变化重置 cursor。所有新接口注释/文档覆盖用途、权限、字段、错误、版本、幂等。

错误沿用现有统一 `{code,message,traceId}` 与 HTTP：400 无效输入/置顶上限，401 会话无效，403 越权/自审，404 本公司对象不存在（跨公司 ID 同样404），409 版本或审核状态冲突。标题1–200字、正文≤20000字、理由1–2000字，空白标题/理由拒绝，position 为0–10000整数；新增校验同步两端契约，旧数据超限先列为兼容风险，不静默截断。正文为纯文本，Vue 插值输出，不用 v-html。

候选与审核决定接口当前不提供幂等键，本批不增加泛用幂等平台：提交期间禁用按钮，禁止网络层自动重放 POST；结果不明先刷新本人申请核对，不能声称恰好一次。多个候选最终以业务 version 防止重复生效。

白名单按精确资源模式扩展，避免放开整个 organization/dashboard/reviews 通配目录；同时验证直接访问新 ADMIN-only 查询的拒绝路径。公共安全修改由 E 协调 B，不能由 B 单独接管 Security/Actor/Db/Business/OpenApi。

### 5. 状态、事务和并发

界面将“当前生效值”和“候选值”分开。USER/MEMBERSHIP/COMPANY_ITEM 复用现有审核状态和步骤，不发明第二套状态机：待审核→通过生效或驳回；缺独立审核人持续待审，并展示原因和允许的重路由。通过必须是当前分配的独立审核人，管理员身份不绕过分层审核。

最终决定、审核记录、业务写入、审计及已有通知 outbox 在同一事务；任何校验失败全部回滚，不显示“通过”却未更新业务。通知沿用现有 outbox，不引入第二条即时推送。申请人与复核人角色/组织、目标 version 在最终应用时重新校验。账号停用/调岗/降权在下一次请求应用服务端新身份，不仅改变页面标签；保留最后一个 ACTIVE ADMIN 保护。

公司事项沿用公司行锁串行化置顶数量校验，提交候选可提前提示，上限必须在最终生效再检查；两个不同事项竞争第十个位置时最多一个成功，另一请求返回 PIN_LIMIT，不写部分数据。更新时 version 比较，旧候选不能覆盖新版本。归档是逻辑归档，保留历史；本期不提供删除、恢复按钮或无审计直接发布。首页依旧 pinned DESC、position、id 取前十条未归档记录，置顶不足十条时可出现其他未归档事项，与当前公共读取保持一致。

## Risks / Trade-offs

- [只有一名管理员/无独立复核人] → 允许真实待审并说明；真实验收前由既有引导方式配置独立复核账号，不新增自审后门。
- [现有组织候选存在冲突/并发申请] → 显示关联申请，最终 version 再校验；失败保留编辑输入供对照，不自动覆盖或重试写入。
- [新增 UI 库影响旧 AI 页面样式与体积] → 管理布局作用域主题、路由懒加载，验收现有入口回归；不同时重写 WorkBench。
- [遗留 Controller SQL 与读取字段不完整] → 仅重构本批涉及的公司事项调用链，补充管理 DTO，不进行无关全库重构。
- [事项 body 历史结构、文本长度不一致] → 读取兼容 body.text，保留原值；实施时对无个人信息测试副本检查历史结构，任何清洗需单独迁移说明。
- [用户需求中的“等”未列举更多对象] → 以提案明确的两类对象为首期；额外对象需单独变更范围。
- [Issue/Sprint/人员尚未分配、生产未验证] → 保留任务1.1与上线验收为未完成；不得以本提案或历史测试证明功能交付。

## Migration Plan

1. 建立 Issue/看板追溯，确认本提案范围、设计稿与接口，由 E/B 协调依赖；仅修改本批文件，保留当前已有用户改动。
2. 先补兼容后端查询/过滤与校验，再接入 Web 页面；预计复用现有表，无必需新业务表。仅当查询索引确有缺口时新增 Flyway 版本，记录升级与回滚；禁止修改旧迁移或 deploy/postgresql 模型。
3. 同步 OpenAPI、接口、基线、运行部署文档，完成整批后统一运行 Web 构建、E2E、后端脚本、严格规格校验，保存明确退出码/日志与截图。
4. 先部署兼容后端再部署 Web；生产前验证 HTTPS、同源 /api 代理、SPA 深链回退、初始化改密与独立审核账号，生产验收未完成不得宣称上线。
5. 可回滚 Web 构建并关闭新增入口；数据库前向迁移保留，不能靠回滚部署撤销已批准的角色/事项修改，业务回退必须新建候选并再次审核。保留审计/outbox。

## Validation Plan

统一验收执行 `npm --prefix web run build`、`npm --prefix web run test:e2e`、`powershell -ExecutionPolicy Bypass -File scripts/test-backend.ps1`（必要时 `-DockerMaven`）和 `openspec.cmd validate --all --strict`。新增纯规则单测覆盖文本/排序边界、权限、最后管理员保护；真实 PostgreSQL/Redis 集成验证最终版本/上限/事务回滚及会话范围。Playwright 至少两条真实后端链路覆盖账号确认和事项审批，Mock UI 测试仅作补充。

非功能至少两项：安全（跨公司 ID、直接接口、撤权后旧会话、XSS纯文本、无密码/私人内容泄露）和无障碍（键盘打开/关闭抽屉、焦点返回触发按钮、错误关联字段、状态播报、200%缩放、正文对比度≥4.5:1）。视觉截图覆盖1440×900、1024×768、768×1024，记录浏览器/Node/Java/数据库环境、两端读取证据与未验证项到 `docs/web-admin-management-validation.md`。

## Open Questions

- 实际 Issue、Sprint、人员与估算待登记；推荐按 E/B 模块职责拆子任务，不默认启动多代理。
- 测试/部署环境的独立复核账号准备方式待记录；缺失时仍可实现安全待审，但闭环验收保持未完成。
- 更多“等修改”对象和账号密码找回不属于本提案；未来新增需说明权限、数据和异常边界。
