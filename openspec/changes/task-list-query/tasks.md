## 1. OpenSpec 与数据迁移

- [ ] 1.1 新增 `V7__task_list_query_index.sql`，创建 `tasks_company_deadline_id(company_id, deadline, id)`；在已应用 V1–V6 的数据库上验证 Flyway 成功且任务数据不变

## 2. 查询实现

- [ ] 2.1 实现 `TaskQueryService`、查询参数和值对象及专用 `TaskListView`；只选择和返回白名单字段，不将 `tasks.body`、`phase` 或详情 DTO 用于列表；使既有 `detail=false` 聚合列表复用安全投影
- [ ] 2.2 将 `TaskController.list` 改为只处理 HTTP 参数和身份上下文并委托查询服务；保留现有分页上限、标题搜索和日期范围语义
- [ ] 2.3 对 `ownerId`、组织范围、跨公司隔离、非法日期/分页参数实现统一错误语义；无权限时不返回数据

## 3. 契约与单元测试

- [ ] 3.1 更新 `TaskApi` 与 OpenAPI，记录列表字段白名单、筛选参数、分页、权限和错误；验证 `/api/openapi` 中存在 `TaskListItem`
- [ ] 3.2 编写 `TaskQueryServiceTest`：员工参与范围、上级组织范围、管理员公司范围、跨公司隐藏、越权 `ownerId`、日期/标题/分页以及字段白名单

## 4. 集成测试

- [ ] 4.1 扩展 `TaskDispatchIntegrationTest` 或新增任务查询集成测试：创建不同状态、不同参与关系、不同组织和不同公司的任务，验证列表仅包含可见任务且无完成、阶段或替代状态字段
- [ ] 4.2 验证范围外同公司 `ownerId` 返回 403、其他公司 `ownerId` 返回 404、非法参数返回 400，且响应不含任务数据
- [ ] 4.3 验证多页稳定顺序与 `total` 仅统计可见任务；对同一用户调用详情接口仍保持既有 404 范围语义

## 5. 交付校验

- [ ] 5.1 运行 `powershell -ExecutionPolicy Bypass -File scripts/test-backend.ps1`（资源受限时 `-DockerMaven`），记录任务单元与集成测试实际结果
- [x] 5.2 在仓库根目录运行 `openspec.cmd validate --all --strict`，确认本变更通过（2026-10-15：14 项通过）
