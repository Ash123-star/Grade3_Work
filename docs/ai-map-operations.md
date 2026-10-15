# AI 地图长期记忆运维

本手册适用于当前 Spring Boot + PostgreSQL 16 + Redis 7 + Neo4j 5.26 Community 实现。三个数据库运行在同一个 `data` 容器，数据分别持久化；PostgreSQL 是记忆、关系、删除排除规则和作业状态的权威来源，Neo4j 是按公司重建的投影。正式接入前须配置管理员、域名、HTTPS、备份保留和供应商数据处理策略；本地预览不等于生产上线。

## 部署与检查

1. 按 `docs/backend.md` 配置 `deploy/backend/.env`，至少包括数据库密码、Neo4j 密码、管理员初始化项和服务端 `DEEPSEEK_API_KEY`。密钥只放在服务端私有环境，不写进客户端或仓库。
2. 用 `scripts/start-backend.ps1` 启动。首次启动检查 data 容器联合健康、Flyway V1–V5、API 健康与 `/api/openapi`。正式环境使用 `-Https`，域名和证书按 `docs/backend.md` 验收。
3. 用具有权限的账号确认 `GET /api/ai-memories/knowledge-status`、发展分析及证据接口只返回当前范围；用普通员工确认组织和他人私人数据被拒绝。客户端不得直连数据库或 DeepSeek。

当前配置入口见 `server/src/main/resources/application.yml`。`JOBS_ENABLED=false` 可暂停后台作业，`AI_MEMORY_EXTRACT_ENABLED=false` 可暂停自动提取；`NEO4J_URI` 为空时图谱通道不可用，分析只使用授权文本证据。`AI_DAILY_TOKENS`、`AI_MAX_TOKENS` 和 `AI_TIMEOUT_SECONDS` 控制模型预算与超时。修改配置后需重启服务；不要把尚未实现的 `AI_RAG_*` 开关当成运行参数。

## 监控与处置

监控 data 容器健康、三进程重启、PostgreSQL/Neo4j 卷空间、API 5xx、DeepSeek 超时及用量。按公司观察 `knowledge_index_state.state`、`building_version`、`updated_at`，`knowledge_index_jobs` 的 `QUEUED/FAILED`，`knowledge_rebuild_jobs` 的进度，`memory_projection_state.state/updated_at`，`memory_forget_jobs` 的 `PENDING`，以及发展作业的 `FAILED/STALE`。监控查询只聚合状态、数量和延迟，不记录记忆正文、提示词或密钥。

索引失败时先查受控错误与数据库健康，由管理员调用 `POST /api/ai-memories/index-jobs/{id}/retry`；全量重建调用 `POST /api/ai-memories/index-rebuild`（带 `Idempotency-Key`），轮询 `GET /api/ai-memories/index-rebuild/{id}` 至 `SUCCEEDED`，并检查 `knowledge_index_state` 已切换到新 `active_version`。重建期间旧有效版本仍可用，失效和删除内容始终不能返回。图投影按公司周期性从 PostgreSQL 全量重建；确认 `memory_projection_state` 为 `READY` 且投影修订与权威数据一致后才视为图可用。图故障时文本 RAG 降级，返回降级原因；无有效证据时只报告信息不足。供应商故障时保留有效记忆与历史结果，不发布未经校验的新分析。

## 备份与离线恢复

定期运行 `powershell -ExecutionPolicy Bypass -File scripts/backup-backend.ps1`，会生成 PostgreSQL 自定义格式备份和独立的 `ai-forget-journal-*.sql`。每次遗忘后、以及两次完整备份之间，另运行 `scripts/backup-backend.ps1 -JournalOnly` 并把最新账本保存在与旧备份分离的受控位置。定期验证账本可读取并覆盖备份之后的所有遗忘事件；如果账本缺失，不得直接开放旧备份的检索流量。备份、账本和 `.env` 都按敏感数据保护，分别制定保留期。

恢复时保持目标库及其 API **离线**，不要覆盖现有业务库：

1. 在隔离新库恢复 PostgreSQL 自定义格式备份，核对 Flyway 版本、公司和关键表行数。Neo4j 与 Redis 不作为权威备份恢复来源。
2. 将比该备份更新、覆盖所有后续遗忘的独立账本导入新库。账本只包含 `memory_exclusions` 的幂等插入；重复导入允许。
3. 在新库执行 `deploy/backend/replay-ai-forget.sql`。它清空排除来源的派生记忆正文及版本内容、删除旧切片、标记关系和分析失效、排队图墓碑；可重复执行且不会重复增加已删除记忆的版本。原始业务记录按业务保留策略处理，不由此脚本删除。
4. 使用指向恢复库的隔离 API，触发管理员索引重建，并等待 `knowledge_index_state` 和 `knowledge_rebuild_jobs` 完成；等待 `memory_projection_state` 为 `READY`，逐项核对删除记忆、片段、关系和历史分析不可见。只有完成权限与遗忘抽查后才切换应用流量。

隔离演练入口为 `scripts/verify-ai-memory-restore.ps1 -Container <workpanel-it-data-...>`，只接受隔离测试容器；它从遗忘前备份恢复，导出并重放遗忘账本，验证索引切换、图墓碑及重复重放幂等。生产恢复需由操作者按上面步骤逐项核对，不能把演练脚本指向生产容器。

## 降级与回滚

Neo4j 故障时保持 PostgreSQL 权威数据与文本检索，修复连接后等待全量投影 `READY`。DeepSeek 故障或预算耗尽时暂停新分析，保留日志、任务、记忆管理和当前仍授权的历史结果。索引构建失败时不切换 `active_version`，修复失败作业后重试；不要手工把失败版本标为就绪。

应用回滚必须兼容当前 Flyway V1–V5，已执行的迁移不倒改；不兼容的结构问题用下一版迁移修复。回滚期间可暂停后台作业与自动提取，先保持遗忘阻断，再核对旧应用能否安全读取新数据。恢复到旧 PostgreSQL 备份属于数据恢复，必须先重放独立遗忘账本，不能用应用版本回退代替遗忘处理。
