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

## 今日任务选择（2026-11-17）

- [x] 日志正文下方展示本人参与且处于 RECEIVED 的任务，支持彩色胶囊多选；保留旧关联，完成任务不再作为新增候选。
- [x] 草稿、提交、24小时修改和历史版本保留 taskIds；服务端对新增关联执行参与人和生命周期校验，关联表与正文同事务。
- [x] 查看日志显示同色任务胶囊，删除日志页右上角下属日志入口；验证保存恢复、权限与异常场景。Issue #94 本轮证据见 docs/backend-validation.md；浏览器安全本地存储不支持，Android 实际草稿持久化仍待设备验收。
- [x] 提供本机真实后端浏览器供用户验收并根据反馈调整；用户于2026-11-17明确授权提交及创建PR。该授权不替代Android设备或最终浏览器完整链路验证。

- [x] 根据本机反馈改为黄色主题“关联任务”下拉多选，收起保持单行、展开可滚动选择；候选仅本人参与且RECEIVED，保留旧关联及草稿。组件4项、HTTP18项及后端34项专项通过，见docs/backend-validation.md。
- [ ] 最终下拉多选版本在浏览器完成保存与重新打开的完整链路，及Android实际加密草稿持久化验收。
