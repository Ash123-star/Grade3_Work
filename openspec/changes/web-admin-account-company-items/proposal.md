## Why

当前独立 `web/` 已有管理员登录、AI 地图/办事入口和任务审计，但缺少集中维护账号和公司十大重要事项的页面。首期建设一个美观、操作清晰的轻量管理端，让管理员通过真实后端完成管理与独立审核闭环，避免为了少量维护操作搭建完整协作门户。

## What Changes

- P0：在现有 Vue 3 / TypeScript / Vite 工程新增管理布局、路由与登录恢复，默认进入账号管理；沿用仅 ACTIVE ADMIN 可进入的规则，FOUNDER 不自动获得入口。
- P0：账号列表、搜索、状态/部门筛选、分页、详情；确认待确认员工的归属，申请修改姓名、部门、团队、直属上级、角色、派发资格及启用/停用状态。关键修改均提交候选版本，禁止直接覆盖。
- P0：公司十大重要事项列表与预览、新增、编辑、置顶/取消置顶、排序、归档；“十大”指最多置顶 10 项，允许不足 10 项，不限制历史总数，不自动补假数据。审核通过后才在 Android 与 Web 的正式读取中生效。
- P0：按2026-10-23用户最新要求，仅提供账号管理、公司十大重要事项两个主页面；相关审核和变更记录置于各页抽屉，展示前后值、理由、审核链、当前生效版本与候选状态；禁止自审，驳回必须填写原因。AI地图不再作为首页或主导航，旧功能仅保留直接兼容地址。
- P0：采用 Element Plus 组件、Vue Router、Pinia 与 Element Plus 图标，使用奶油白、薄荷绿、珊瑚橙主题、清晰表格、圆角卡片和右侧抽屉；完整覆盖加载、空、失败、冲突、无权限状态及键盘操作。
- 非目标：本批不新增账号硬删除、管理员直接创建高权限账号、修改手机号/登录名、重置他人密码、批量导入导出、组织结构编辑器、任务派发、日报、报表或 AI 能力。已有 AI/审计入口保留兼容入口，不作为本批开发或验收成果；“等修改”暂限定为上述两类对象及必要审核。

## Capabilities

### New Capabilities

- `web-admin-management`: 管理端入口与视觉布局、账号维护、公司事项维护及限定范围的审核闭环，复用现有业务权限、候选版本和审计契约。

### Modified Capabilities

无。沿用 `collaboration-backend` 的认证、组织隔离、候选审核与跨端契约；不修改 `dashboard-quadrant-layout` 的 Android 只读首页约束。与活动变更 `member-b-week6-permissions` 的 ADMIN 工作台规则一致，不扩展其任务审计范围；与 `ai-work-assistant` 的 Web P1 工作区保持独立验收。`initial-product` 的完整 Web 规划仍作为后续范围，不视为本批全部交付。

## Impact

- 前端：主要影响 `web/src/App.vue`、`main.ts`、`style.css`、新增管理页面/组件/路由/状态/类型化 API 模块，以及 `web/package.json`、锁文件和 Playwright 用例；保留现有功能的可达性。
- 后端：复用 auth、organization、dashboard、review；补充公司内 ADMIN 账号分页查询、事项归档查询、管理读取字段与限定审核过滤等必要契约，新增管理适配点遵循现有 `/api/admin/workspace` 鉴权入口。公司事项写入和生效校验下沉应用/领域层。
- 数据：复用 users、dashboard_items、review_requests、review_steps、audit_records；仅确有字段或索引缺口时新增 server Flyway 迁移，不更改已发布迁移或另建身份体系。
- 文档：实施时同步 `方案.md` 的首期 Web 范围说明、运行时 SpringDoc、`docs/openapi.json`、`docs/backend-interface.md`、部署与验收报告；提案不代表功能已实现。
- 负责人：Web/契约 E，auth/organization/review B，公司事项与公共平台对接 E 协调现有负责人；具体人员、Issue、Sprint、估算均待关联，不编造编号。实施任务 1.1 完成追溯后进入业务编码。
- 验收目标：真实数据库下完成“员工归属确认→独立审核→有效权限变化”和“公司事项修改→独立审核→双端正式内容更新”两条链路；验证跨公司拒绝、自审拒绝、版本冲突、第 11 项置顶拒绝，以及安全与无障碍两项非功能要求。仅 Mock、构建或静态检查通过不算交付。
