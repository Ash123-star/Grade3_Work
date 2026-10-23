# Proposal

## 2026-10-19 柴犬品牌装饰接入批次

优先级 P0，负责人 A/mobile。修复 dog 子目录资源声明并按原图内容修复跨网格切片。所有页面/区块标题左侧使用柴犬头像；月历星期栏七格使用不同表情、今天格使用另一张头像；导图四卡以四张不同头像替换入口图标，并在保留原外框的卡片内叠加柴犬背景；所有页面继续使用原卡通背景。柴犬不替代真实用户头像、不编码业务状态，任务管理入口保留。关联本地 Issue：`docs/issues/dog-brand-ui-integration.md`；远程编号及 Sprint 待关联，不创建远程 Issue/PR。本批按用户要求停止 Flutter 测试、分析、构建与设备验收，运行态效果保持未验证。

## 2026-10-19 approved mobile control refresh

This implementation batch completes the approved Flutter front-end design using MockRepository data: a compact social-feed comment stream, colored tag capsules, custom calendar and time-wheel selectors, simplified task-management filters, and a blank daily-log creation route. It does not claim real backend integration or alter server authorization, daily uniqueness, or the 24-hour edit rule.

## 2026-10-20 mobile visual and demo-data correction

Update the “我的” feature icons to the original cartoon PNGs, move month-view task bars slightly lower while keeping them above each date cell's vertical midpoint, make the registration entry bold and warm-colored, and remove green styling from interactive controls while retaining semantic success colors. Ensure the mock organization tree, account selector, tasks, logs, and comments use at least 10 distinct demo accounts with realistic, role-appropriate and non-identical content. Keep the five product-defined authorization roles; this batch adds demo identities, not permission types. User declined Flutter tests, analysis, builds, and device verification; implementation tasks remain unchecked until later acceptance evidence exists.

Add a warm filled-circle marker before each record in the four dashboard tiles, with fixed vertical spacing between records regardless of record count. Remove redundant top app-bar titles from the five bottom-navigation pages while preserving meaningful in-page headings and controls.

Refresh the member workspace identity card from the jarring pale-blue color to the app's warm-white palette. Redesign the login and employee-registration pages as a polished, production-style mobile authentication flow while preserving current auth fields, server contracts, validation, pending-account restrictions, and honest SMS availability messaging.

Refine the authentication composition using the supplied reference's graphic-led hero/foreground-form hierarchy, an editorial serif hero phrase, compact existing-feature rail, and clearer company-account context. Remove the current three-line product/welcome headline. Keep visual density useful and do not introduce unsupported third-party login, SMS, or password-recovery actions.

## 本轮范围（2026-10-17）

用户追加九张当前页面批注并明确批准先交付 Flutter + Mock 前端。该批次不以服务端缺失为实施阻塞，不修改真实 HTTP 契约、后端、Web 或数据库；原有后端任务继续保留未完成。导图公司任务列表与“我的→任务管理”分离，后者查看本人及授权下属全部任务。逐图要求与验证证据见 `mobile/docs/week5-ui-adjustment.md`。

## Why

甲方基于当前 Android 前端截图指出了首页、视图、任务、日志、评论、人员、素材和 Web 入口的系统性偏差。现有页面仍暴露旧字段和旧入口，部分交互与服务端规则不一致，导致真实后端联调时无法按截图完成演示。本变更冻结 24 项设计要求，建立从视觉资源、页面行为到接口权限和验收证据的统一改造边界。

## What Changes

- 2026-10-18 追加：日、周、月视图只查询任务，删除日志合并及类型提示；月历每天最多三条预览，跨日色带保持固定轨道，整月无需纵向滚动，日期滚轮可取消或确认。
- **BREAKING** 首页移除新增任务入口、日期行和时间视图入口；新增任务入口只保留在视图页，并按权限显示。
- **BREAKING** 任务表单改为开始时间、日期/小时/分钟截止时间、标签、参与人集合；移除分组、主负责人、协作人和独立进度备注。
- 任务和日志共用分类标签及预设颜色；记录颜色必须读取标签颜色，标签编辑仅创始人可用。
- 创建、修改、删除任务统一进入现有审核链；删除采用归档/不可用语义，不做物理删除。
- 任务和日志提供公开评论及回复，评论显示作者、头像和时间，评论不可编辑或删除。
- 日志产品入口只保留日报；已提交日志从服务端 `submitted_at` 起 24 小时内可编辑，超过窗口后编辑和撤回均拒绝。
- 下属日志改为部门分组，并提供搜索、部门和日期筛选；消息中心移除日志分类但保留评论通知。
- “我的”增加独立人员展示页；Web 端仅管理员可访问，普通用户收到明确拒绝。
- 所有页面替换为重新制作的卡通小柴犬素材，标题、卡片、按钮、标签和空状态统一采用批准的视觉规范；月视图七列完整显示且无需横向滑动。
- 移动端隐藏任务版本和历史概念，任务后端继续保留版本并发控制、审核和审计留痕；日报不使用版本控制，也不进入审核。

## Capabilities

### New Capabilities

- `mobile-personnel-view`: 在“我的”下提供按组织范围展示人员、部门和工作状态的独立只读页面。

### Modified Capabilities

- `dashboard-quadrant-layout`: 调整首页/视图入口、月视图、记录颜色、演示数据和全局素材行为。
- `collaboration-backend`: 调整任务字段、标签、参与人、评论、日志 24 小时窗口、下属日志筛选、审核删除和 Web 管理员门禁契约。

## Impact

- Flutter：`mobile/lib/features/dashboard`、`calendar`、`common`、`settings`、`routing`、`data/repositories`、公共主题和素材目录。
- Spring Boot：任务、日志、评论、标签、组织查询、通知和 Web 权限模块；数据库仅新增 V14+ Flyway 迁移，不修改 V1–V13。
- 契约：同步 SpringDoc、`docs/openapi.json`、`docs/backend-interface.md`，新增字段包括 `startAt`、`participantIds`、`tagId`、`tagColor`、`submittedAt`、`editableUntil`、`canEdit` 和评论回复关系。
- 验收：增加真实 PostgreSQL/Redis、真实 HTTP、Flutter Android 和 Web 管理员门禁的正向、异常、越权和非功能证据；Mock 或静态检查不能单独作为完成依据。
- 关联 Issue/Sprint：编号待项目看板创建后补录；所有 OpenSpec task 先保持未完成，直到有可复现证据。
