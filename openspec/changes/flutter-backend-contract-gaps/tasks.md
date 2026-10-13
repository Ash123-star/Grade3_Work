# Tasks

## 1. Contract discovery and ownership

- [ ] 1.1 为 API-GAP-01 至 API-GAP-05 建立 Issue 负责人和优先级，逐项确认角色、数据范围、状态、错误、幂等和验收矩阵，并检查 `docs/backend-interface-gaps.md` 与运行时 OpenAPI 一致
- [ ] 1.2 比较现有路由扩展与独立资源两条契约路线，形成评审结论；验证不再需要的 `/feedback` 通用请求在 Flutter 正式模式中被阻断

## 2. Feedback and task lifecycle

- [ ] 2.1 定案意见反馈查询/提交/处理进度/附件契约，更新后端模块、OpenAPI、接口文档和 Flutter 映射；用集成测试验证正常、无效、越权、分页和附件边界
- [ ] 2.2 定案任务退回补充事件或资源，更新状态机、版本、通知 outbox、审计和统计投影；用 PostgreSQL/Redis 集成测试验证非法阶段、缺少原因、越权、冲突和重复请求

## 3. Diary and AI contracts

- [ ] 3.1 实现已提交日报阅读人员清单查询，限制组织范围和最小字段；用集成测试验证分页、无记录、草稿拒绝、越权和账号隔离
- [ ] 3.2 定案并实现 AI 范围筛选，服务端与 Actor 权限取交集并在来源读取/编辑/确认时重验；用脱敏、越权和范围变化测试验证不扩大输入
- [ ] 3.3 为 AI 确认增加 job/output 版本前置条件并与幂等任务创建放入同一事务；用并发、过期版本、同键重放和同键异载荷测试验证最多创建一个任务

## 4. Cross-client integration and acceptance

- [ ] 4.1 同步 SpringDoc/OpenAPI、`docs/openapi.json`、`mobile/docs/API_CONTRACT.md`、Flutter Repository 和 Web 适配边界；验证双端请求字段和错误模型一致
- [ ] 4.2 运行后端脚本、Flutter 正式契约测试、权限/异常/并发验收和 `openspec.cmd validate --all --strict`；只在取得真实证据后勾选对应任务

## Workflow follow-up

- 由小组完成接口负责人分配后，再使用 `openspec-apply-change` 实施本变更。
- 后端与客户端实现、真实集成验收和非作者审阅完成后，再归档本变更。
