# 本地记忆分支整合记录

日期：2026-10-15。整合 `8b597d4` 与主分支 `0aada7e`，原分支及 stash 保留。

## 合并取舍

- 保留主分支 Flutter 团团页面、路由、安全存储、任务日报接口与 GET 重试/SSE 能力。旧版四象限页面不覆盖新版首页，旧版截图仅作历史资料。
- 长期记忆页面迁入 `features/ai_map/long_term_memory_page.dart`，从真实模式 AI 地图工具栏进入 `/ai/memory`；原 AI 作业与人工确认流程保留。
- 服务端记忆模块改用现有 AI/审核应用服务；模型调用直接注入配置与公共依赖，避免访问其他模块私有字段。
- 新增记忆迁移使用 V10/V11，不修改主线 V1–V9；补齐 MEMORY、TASK_REASSIGN、TASK_RESCHEDULE 审核类型约束。
- 后端验证使用 clean verify，避免跨分支后旧 class 与旧迁移资源残留。
- 本次与旧实验库的迁移版本不兼容。已执行实验 V4/V5 记忆迁移的库不可直接启动新版，须备份后通过独立库安排数据迁移，不可改写 Flyway 历史。

## 验证

- `powershell -ExecutionPolicy Bypass -File scripts/test-backend.ps1 -DockerMaven`：Docker Maven 3.9.9 / Java 21，真实 PostgreSQL/Redis/Neo4j 隔离环境，90 项测试全部通过（18 项全链路、18 项任务集成、54 项单元），0 失败、0 错误、0 跳过；V1–V11 迁移成功。DeepSeek 使用模拟供应商。
- Flutter 全项目 Dart 静态分析通过；AI 记忆状态、API 重试和现有 AI HTTP 工作流定向 30 项通过。
- Web TypeScript 检查与 Vite 构建通过；Playwright 桌面/手机受控测试 4 项通过，2 项真实账号测试因未提供账号跳过。
- OpenSpec 严格校验 26 项通过。旧记录中的验证日期与限制仍适用于原始版本，不代表生产部署。
- 5 查询/6 证据的小样本复测：文本加图谱 Recall@5 为 1.0，中位耗时 140ms、样本最大值 236ms；仅为本地合成测试，不外推生产准确率。
- 初次回归发现旧构建资源残留、审核类型约束缺失及人员夹具计数过期；clean 构建、追加约束和精确人员 ID 集合断言修复后，全仓通过。

## 限制

- 未执行真实 Android 设备、真实业务 DeepSeek 效果及生产部署验收。
- 本次未合并 `lyb` 认证组织分支；历史 UI 原型及截图不作为当前版本视觉验收证据。
