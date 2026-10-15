## 1. 数据迁移

- [ ] 1.1 新增 `V8__daily_log_query_index.sql`，创建 `daily_logs_company_submitted_date_id`；在已应用 V1–V7 的数据库上验证 Flyway 成功且日报、版本、评语和已读数据不变

## 2. 日报应用层

- [ ] 2.1 实现 `LogWorkflowService`，将草稿、提交、详情、修订、历史、已读和评语业务规则从 `LogController` 收敛到 `module/log/application`
- [ ] 2.2 将 `LogController` 保持为 HTTP 映射、输入字段检查、认证和事务边界，并委托应用服务；保留路径和错误语义
- [ ] 2.3 保证草稿按本人和日期唯一、版本冲突不写入、提交与首个 `log_versions` 写入同一事务

## 3. 测试与契约

- [ ] 3.1 更新 `LogApi` 和 OpenAPI，记录草稿私密性、版本、提交、修订、已读及评语权限
- [ ] 3.2 编写 `LogApplicationServiceTest`，覆盖草稿覆盖/冲突、本人草稿可见、草稿越权 404、重复或旧版本提交、草稿评语拒绝
- [ ] 3.3 扩展后端集成测试，覆盖每日唯一、提交后可见、修订历史顺序、审核生效版本冲突、已读和评语

## 4. 交付校验

- [ ] 4.1 运行 `powershell -ExecutionPolicy Bypass -File scripts/test-backend.ps1`（资源受限时 `-DockerMaven`），记录实际测试结果
- [x] 4.2 在仓库根目录运行 `openspec.cmd validate --all --strict`，确认本变更通过（2026-10-15：14 项通过）
