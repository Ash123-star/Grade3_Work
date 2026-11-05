# Tasks

## 2026-11-05当前验收目标

用户确认恢复同页可展开部门→团队→人员树，替代下方3.5及2026-11-03历史记录中的分页式交互；历史勾选只证明当时批次，不证明本次目标。统一验收见 [B01–B05](../../../docs/app-requirements-acceptance.md)。

- [x] 6.1 将人员选择改为同页树展开/收起，搜索展示完整路径并保持选中集合；稳定ID多选确认/取消、同名、跨团队、失败、token/epoch失效、小屏键盘回归25项通过。证据见[统一验证入口](../../../docs/backend-validation.md)。
- [ ] 6.2 在最终合并代码及真实HTTP APK执行B01–B05，核对多标签保存/回显、前后端校验及迁移兼容，证据关联现有Issue。

- [ ] 6.3 按已确认原型优化参与人选择（头像+姓名、无文件夹图标、已选管理），人员展示复用原记录条并增加同页部门/团队展开；保持接口、资格、分页与会话隔离。
- [ ] 6.4 集中验证目录展开/收起、搜索、同名/跨团队多选、确认/取消、失败/重试、未知状态及小屏大字体/键盘；构建并安装真实HTTP APK，记录实际证据和剩余限制。

## 1. 协作与契约准备

- [ ] 1.1 在 Issue/看板记录成员 B 的组织目录与场景数据范围，并与成员 C、E 确认多标签字段、迁移编号和职责边界；验证为协作记录包含 Issue/Sprint 编号或明确待关联原因。
- [ ] 1.2 盘点现有 `/api/organization`、`/api/organization/people` 和任务标签请求/响应，写出 `participants`、`labelIds`、`labels` 与旧 `labelId` 的兼容/冲突规则；验证为接口文档评审可复现零/一/多标签样例。

## 2. 组织人员选择数据（成员 B）

- [ ] 2.1 在 `module/organization` 的应用层和仓储层补齐选择器所需的组织路径与可选资格投影，保持 Controller 仅做 HTTP 映射；验证为组织服务单元测试覆盖部门、团队、人员和搜索命中路径。
- [ ] 2.2 在服务端统一校验待确认、停用、跨公司、范围外和重复人员，保证人员不能作为任务参与人部分写入；验证为异常/权限测试返回明确错误且数据库无新增关联。
- [x] 2.3 为组织目录增加 PostgreSQL/Redis 集成测试，覆盖创始人、管理员、主管和员工不同范围及伪造人员 ID；验证为受影响集成测试实际退出码为 0。

## 3. 多标签任务契约（成员 B；接口文档与成员 E 协作）

- [x] 3.1 由成员 B 在确认最新 Flyway 版本后新增标签关联集合迁移，保留旧单标签关联并建立 `(task_id,label_id)` 去重约束；验证为空库与升级库迁移均通过且不修改 V21。
- [x] 3.2 由成员 B 更新任务创建、修订审核生效、详情和列表投影，使标签支持零/一/多并在单事务中校验/替换；验证为任务模块单元测试覆盖有效、重复、停用、跨公司和版本冲突输入。
- [ ] 3.3 由成员 E 同步 SpringDoc、`docs/openapi.json` 与 `docs/backend-interface.md`，明确跨端字段、错误、幂等和旧 `labelId` 兼容窗口；验证为生成接口文档与运行时契约一致。
- [ ] 3.4 由成员 B 仅绑定现有表单/选择器的数据和搜索展开状态，不修改布局、颜色、字体、导航或组件风格；验证为 Flutter 定向契约测试覆盖零/一/多标签和选中回显。
- [x] 3.5 按用户明确要求将组织选择器改为分页式（部门页 → 团队页 → 人员页，支持返回上一级），搜索命中时按部门/团队节点展开人员并展示组织路径、节点可点入对应分支；删除标签选择面板的“标签可不选，也可选择多个”说明，并用名称前红色 `*` 替代“必填/选填”文字（不增加顶部说明行）；验证为 `workflows_test`、`attachment_assignment_http_test`、`ai_http_workflow_test`、`layout_test` 定向测试与 `flutter analyze` 覆盖。

## 4. 多创始人场景数据（成员 B）

- [x] 4.1 在当前年度 `db/scenario-annual2026` 新增下一版本的增量场景迁移，创建至少两名可区分的 ACTIVE FOUNDER、角色记录和最小标签/任务关联数据；验证为场景迁移执行后账户、角色和关联查询结果正确。
- [x] 4.2 为场景初始化增加前缀冲突和非场景库保护测试；验证为重复或错误目标库安全失败且既有业务数据不变。
- [ ] 4.3 增加多创始人目录、标签维护和任务申请的集成测试，只断言当前既有审核规则且不修改 `ReviewApplicationService` 策略；验证为两名创始人分别通过现有权限路径，管理员成员确认规则保持不变。

## 5. 集中验收与交付

- [ ] 5.1 执行受影响的后端单元和集成测试，以及 `powershell -ExecutionPolicy Bypass -File scripts/test-backend.ps1 -DockerMaven`；验证为记录实际命令、环境、退出码和失败项，未通过项不勾选。
- [ ] 5.2 执行 Flutter 定向契约测试和 `openspec.cmd validate --all --strict`；验证为记录测试结果、严格校验结果及未验证的真实设备/跨端范围。
- [ ] 5.3 整理迁移说明、验收步骤、协作边界和风险，准备 PR 描述；验证为 PR 内容可追溯至本 change、Issue 与实际验证证据，未经用户确认不得推送或合并。

## 验证记录与阻塞

当前新增阻塞：2026-11-05年度场景V1因日期滚动选入无上级创始人而插入空reviewer，完整后端回归2项错误，详见Issue #73；不修改已发布迁移或用测试夹具掩盖。下方2026-11-02通过为当日历史。

- 2026-11-02：已对成员 B 新增/修改的 Java 源文件执行 Java 21 静态编译检查，并通过 `openspec.cmd validate member-b-organization-selector-founders --strict`。这不是集成测试通过证据。
- 2026-11-02：在独立、自动清理的 Docker PostgreSQL/Redis/Neo4j 环境执行 Maven `clean test` 定向验收：`OrganizationIntegrationTest` 9/9、`AnnualScenarioMultiFounderMigrationTest` 3/3、`MemberBEndToEndTest` 1/1 通过。
- 2026-11-02：全仓 `scripts/test-backend.ps1 -DockerMaven` 已实际运行但 447 项中 72 失败、10 错误，主要集中在既有 `BackendIntegrationTest` 会话失效、`WorkIntegrationTest` AI 配置/限流及一个任务时间线断言；未将全仓验收任务勾选为通过。
- 2026-11-02：新增 `V24__task_multi_label_links.sql`，将既有单任务标签主键前向升级为 `(task_id,label_id)`。在新建、自动清理的本机 Docker PostgreSQL/Redis/Neo4j 容器中执行 `TaskDispatchIntegrationTest`，退出码为 0；覆盖零/多标签、重复标签去重、停用标签拒绝及原任务审核生效链路。
- 2026-11-02：`dart analyze lib/shared/task_label_selector.dart lib/features/common/form_page.dart lib/data/repositories/repository.dart lib/data/models/task_display.dart` 退出码为 0。Flutter widget 定向测试尚未取得可复现结束输出，故 3.4 与 5.2 保持未勾选。
- 2026-11-03：完成派发页 3.5（分页式组织目录 + 红色 `*` 必填标识）。`flutter test test/workflows_test.dart` 7/7、`test/ai_http_workflow_test.dart` 19/19、`test/layout_test.dart` 全部通过；`test/attachment_assignment_http_test.dart` 中组织目录分页与派发 UI 两个用例通过。该文件的 `task download route and feedback attachment boundary remain explicit` 仍失败（断言 `附件关联暂不可用`，但当前反馈表单已支持附件），与本次改动无关且 HEAD 同样存在。
- 2026-11-03：`flutter analyze --no-pub` 退出码 1，仅 8 条既有 info（TickerMode/`use_super_parameters`），未新增 error 或 warning。`test/task_label_selector_test.dart` 首例在 UI 选择完成后卡在直接调用 `repository.execute`（Dio 假异步），其余用例通过；卡点与 2026-11-02 记录的 widget 测试无法结束一致，未改动该用例的既有契约。
- 2026-11-03：分页式选择器与红色 `*` 标识的定向回归再次通过：`workflows_test` 7/7、`ai_http_workflow_test` 19/19、`layout_test` 全部通过；`attachment_assignment_http_test` 中 `organization picker pages through department, team and person and searches path` 与 `dispatch UI preserves uploaded IDs and unique participants from actual member choices` 均通过。`flutter analyze --no-pub` 仍仅 8 条既有 info。
- 2026-11-03：搜索命中改为按部门/团队节点展开并显示组织路径，节点可点入对应分支；`organization picker pages through department, team and person and searches path` 覆盖搜索结果分组、路径展示与节点跳转，退出码为 0。
