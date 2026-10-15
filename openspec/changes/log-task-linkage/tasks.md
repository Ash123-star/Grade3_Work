## 1. 数据迁移

- [ ] 1.1 新增 `V9__log_task_linkage_index.sql`，创建 `daily_logs_submitted_owner_date_id` 部分索引；在已应用 V1–V8 的数据库上验证 Flyway 成功且 `log_tasks` 数据不变

## 2. 查询和关联实现

- [ ] 2.1 实现 `LogQueryService`，收敛普通和下属日志列表的范围、草稿私密、ownerId、日期和分页规则；`LogController` 只委托
- [ ] 2.2 扩展 `LogTaskLinks`：保存草稿和修订申请前校验每个 `taskIds` 的读取范围；验证成功后同事务同步去重关联
- [ ] 2.3 在 `LOG` 候选修订审核生效时使用申请人身份重新校验关联，权限变化时不更新正文、版本或关联

## 3. 测试与契约

- [ ] 3.1 更新 `LogApi`、OpenAPI 与接口注释，说明下属入口、草稿私密、ownerId 错误和任务关联权限
- [ ] 3.2 编写 `LogQueryServiceTest` 和 `LogTaskLinksTest`，覆盖组织范围、草稿隐藏、员工拒绝、外部/范围外任务关联和失败不写入
- [ ] 3.3 扩展集成测试：下属入口仅提交日志、草稿隐藏、`log_tasks` 去重与范围外任务失败、审核生效前后关联一致

## 4. 交付校验

- [ ] 4.1 运行 `powershell -ExecutionPolicy Bypass -File scripts/test-backend.ps1`（资源受限时 `-DockerMaven`），记录实际测试结果
- [x] 4.2 在仓库根目录运行 `openspec.cmd validate --all --strict`，确认本变更通过（2026-10-15：14 项通过）
