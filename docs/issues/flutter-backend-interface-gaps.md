# 本地 Issue：补齐 Flutter 产品所需的后端契约缺口

- 背景：Flutter 正式客户端已接入仓库现有 Controller/OpenAPI 契约，但原产品需求仍包括若干后端尚未提供或能力不足的操作。客户端当前对未支持操作明确拒绝/禁用；Mock 演示不计作服务端完成。
- 优先级：Must 项（AI 授权范围、AI 确认原子版本）先进入架构评审；Should 项（意见反馈、任务退回补充、日志阅读人员清单）进入产品后续批次。实际排期由小组 Backlog 确认。
- 范围：逐项完成契约分析、权限/状态/错误/分页/幂等/并发设计、OpenSpec、后端实现、OpenAPI 同步、Flutter 接入和集成验收。
- 验收：每项有正向、异常/无效输入、越权、并发或一致性（适用时）验收；真实 Controller + PostgreSQL 集成测试通过；Flutter 正式模式使用定案契约；文档与运行时 OpenAPI 一致。
- 非目标：本登记不决定具体新路径、字段、数据表或 UI 行为细节，不代表接口已实现。
- 关联 OpenSpec：`flutter-stage3-layout-rebuild` 3.6、`flutter-backend-contract-integration` 2.1；具体实现前为每个变更建立专属 OpenSpec change。
- 缺口明细：`docs/backend-interface-gaps.md` 中 API-GAP-01 至 API-GAP-05。
