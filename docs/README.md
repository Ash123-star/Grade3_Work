# 仓库文档入口

需求从 [方案](../方案.md) 开始，开发前读 [AGENTS.md](../AGENTS.md) 与 [协作流程](development-workflow.md)。当前任务范围和验收条件维护在 [OpenSpec](../openspec/changes/)，不根据文件名中的“交付”或历史通过数量判断功能完成。

| 主题 | 入口 |
| --- | --- |
| 客户端运行、页面设计和接口接入 | [mobile/README](../mobile/README.md)、[移动端文档索引](../mobile/docs/README.md) |
| 后端运行、配置和架构 | [backend](backend.md)、[模块架构](backend-architecture.md) |
| 接口与数据库 | [后端接口](backend-interface.md)、[OpenAPI](openapi.json)、[数据库结构](database-schema.md) |
| 当前接口接入缺口与待验收 | [P0 实现状态](mobile-p0-implementation-status.md)、[剩余接口状态](mobile-remaining-api-implementation-status.md)、[缺口清单](backend-interface-gaps.md) |
| 最近联调与未解决失败 | [2026-10-30 联调](frontend-backend-integration-validation-2026-10-30.md)、[2026-10-29 合并限制](premerge-verification-2026-10-29.md) |
| 数据库契约核对 | [2026-10-29 记录](database-contract-verification-2026-10-29.md) |
| 云端维护、回滚与年度场景库 | [systemd 部署](cloud-systemd-deployment.md)、[年度场景重建](annual-scenario-rebuild.md)、[本机场景种子](local-scenario-data.md) |
| AI 服务接入与运维 | [办事 API](ai-work-assistant-api.md)、[办事部署](ai-work-assistant-deployment.md)、[AI 地图运维](ai-map-operations.md) |
| 数据基础设施独立模型 | [数据基础设施](data-infrastructure.md)；不得与 server Flyway 业务模型混用 |
| 脚本用途 | [scripts/README](../scripts/README.md) |
| 分工与 OpenSpec 用法 | [MVP 分工](mvp-team-division.md)、[OpenSpec 指南](openspec-guide.md) |

认证、组织、审核及专项安全/性能文档保留在本目录，历史验证只适用于其记录的提交和环境。最近联调仍记录 Flutter 33 项失败、后端 49 项失败与 1 项错误，不能用较早的通过记录覆盖这些待处理问题；本次清理未重跑测试。

已被替代的阶段交付/合并记录、旧 UI 原型和截图从工作树删除，可通过 Git 历史恢复。未完成 OpenSpec、迁移、测试源码、许可证、备份/恢复工具以及现有交接文档保留。新增文档应更新现有主题文件与本索引，避免按会话或每轮修改重复建立“最终交付”文档；过程日志和截图写入被忽略的 `output/`。
