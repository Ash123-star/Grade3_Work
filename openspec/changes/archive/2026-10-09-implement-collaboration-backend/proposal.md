## Why

现有 Flutter 是演示端，缺少方案.md 所需的真实持久化、权限和业务闭环。建设双端共用的 Spring Boot 后端，使客户端能通过同一契约接入真实业务。

## What Changes

- 新增 Spring Boot 3、PostgreSQL/Flyway、Redis 后端及 Docker 部署。
- 实现注册登录、强制改密、五角色范围、组织候选变更和独立复核。
- 实现四象限、私人备注、日志草稿提交修订、任务流转及幂等派发。
- 实现事务 outbox、通知 SSE、日期范围统计和 CSV 导出。
- 实现 DeepSeek 异步任务、流式建议、取消重试、用量限制与来源地图。
- 交付 OpenAPI、环境变量、初始化及集成测试；不将移动端联网或 Web 页面建设算作本次后端交付。

## Capabilities

### New Capabilities

- `collaboration-backend`: 企业协作服务的认证、范围、审核、业务、通知、统计、AI 和运行验收。

### Modified Capabilities

无。

## Impact

新增 server/、deploy/backend/、docs/backend.md 和后端自动化验证。保留 initial-product 的跨端待办及已有 postgres-redis-infrastructure 变更，不覆盖其他工作。
