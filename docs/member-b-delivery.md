# 成员 B 分批交付记录

依据：MVP 分工优先，PRD 为参考；OpenSpec `member-b-backend-readiness`；分支 `lyb`。

## 追溯

- 认证：[Issue #3](https://github.com/Ash123-star/Grade3_Work/issues/3)，任务 2.1–2.6；映射 initial-product 2.1、2.4。
- 组织：[Issue #4](https://github.com/Ash123-star/Grade3_Work/issues/4)，任务 3.1–3.5；映射 initial-product 2.2、2.4。
- 审核：[Issue #5](https://github.com/Ash123-star/Grade3_Work/issues/5)，任务 4.1–4.6；映射 initial-product 2.3、2.4。
- 各批与 architecture-modularization 的实际应用路径接入、api-contract-unification 的文档一致性关联；未验证旧任务不重复勾选。
- GitHub Issue 已建立；实际 Sprint/看板待组内关联，未建立里程碑不虚构 Sprint 编号。

## 实施前基线（2026-10-11）

Java 21.0.12、Maven 3.9.11、PostgreSQL 16、Redis 7，Windows 11 / Docker Desktop Linux engine。
此前 `scripts/test-backend.ps1 -DockerMaven`：10 个集成测试，9 通过、1 失败、0 错误/跳过。
失败为 scopedTasksIdempotencyAndLifecycle：转交 reviewer 返回 400 INVALID_OWNER，预期 200；目标不在团队，待 C/E 核对夹具及范围，不能削弱校验。
原始证据在忽略目录 `output/backend-environment-test.log`；现有迁移 V1–V4；实际数据库为 server Flyway 模型。

## 契约与协作边界

认证 HTTP 路径和请求/成功响应保持现有格式；IP 限流仍由既有 Limiter 执行。登录新增持久锁定，锁定仍使用 INVALID_CREDENTIALS/401；验证正确密码后停用返回 ACCOUNT_DISABLED/403。这项错误扩展需 E 在客户端展示和汇总契约中核对。
auth 应用接口属于 B；当前 ActorContext 不含凭证，注销调用需在 auth 应用接口显式传入当前 token，不修改共享 Actor/ActorContext。所有调用点必须通过编译及集成测试。
公共 Security/Actor/Db/Business/OpenApi 不在本批修改；过滤器缺陷由 E 协作。对应接口 JavaDoc 与本模块接口说明随实现更新，OpenAPI 汇总和客户端接入仍待 E 验证。

当前记录为实施基线，不是功能完成或与 E 已确认的证明。各批验证结果后续追加。

## 第一批认证验证（2026-10-11）

- 新增 AuthPolicyTest 3 项、AuthIntegrationTest 8 项，最终定向 11 项全部通过，0 失败/错误/跳过。包含 V4→V5 升级、五次失败持久锁定、并发错误、到期、清理、注册拒绝/原子性、待确认、改密、注销、停用及调岗会话。
- 定向命令为 output/test-member-b-auth.ps1 -DockerMaven（复用仓库容器启动方式，仅按 Auth*Test 选择测试）；原始证据 output/member-b-auth-final.log。该次 verify 测试通过后曾因旧 API 占用 JAR 打包失败；核实停止旧进程后 Java 21 Maven package 成功，证据 output/member-b-auth-package.log。
- 第一轮全套 20 项，19 通过、1 失败、0 错误/跳过；仅为原有任务转交失败，证据 output/member-b-auth-test.log。
- 用户明确“保持公共测试原样，记录阻塞交给 E”。未修改 BackendIntegrationTest，不降低生产权限校验。全套回归任务 5.4 仍未完成。
- 本地 API 改用 output/local-api-runtime.jar 运行副本，避免占用 server/target 的构建产物；开发库 V4→V5 升级由启动 Flyway 执行。
- 运行时 OpenAPI 证据另存 output/member-b-auth-openapi.json。公共 docs/openapi.json 被原有集成测试自动生成覆盖，恢复请求未获允许，暂保留为未提交生成差异，交 E 核对；不将其混入 B 代码提交。
- E 契约确认、公共快照和真实客户端接入尚未完成，因此任务 1.2、2.6 保持未完成，不声称认证双端联调完成。

## 第二、三批及联合验收（2026-10-11）

- 最终执行 `powershell -ExecutionPolicy Bypass -File output/test-member-b-all.ps1 -DockerMaven`：33 项通过，0 失败、0 错误、0 跳过；Maven clean verify 与可执行 JAR 打包成功。脚本从仓库测试脚本派生，使用相同隔离 PostgreSQL/Redis、Maven 容器与资源上限，仅选择 B 自有测试。原始证据 output/member-b-delivery-final.log。
- 认证：8 集成 + 3 单元；组织：8 集成 + 2 单元；审核：8 集成 + 2 单元；完整端到端 1；性能参考 1。公共 BackendIntegrationTest 未修改、未加入此次定向选择；此前全套已知失败仍阻塞最终全套验收。
- 最终环境：Docker Maven 3.9.9 / Java 21.0.7、PostgreSQL 16.15、Redis 7；测试 JVM 2 可用处理器、最大堆约 371 MiB，Maven 容器 1 GiB/2 CPU，Windows 11 主机 16 GB 内存。宿主安装的 Java 21.0.12 / Maven 3.9.11 与容器版本不同，不混称。
- 组织：五角色和公司/部门/团队隔离，113 人树完整性与分页，关系/环/最后管理员并发，归属确认、角色职责、策略、部门团队候选、通过/驳回及旧会话范围；调岗后历史任务/日志仍存在。
- 审核：独立层级、策略可配置、缺失公司独立人、非法输入/自审/越权/空原因、终态重试、并发一次写入、版本冲突和组织变化回滚、旧职责快照拒绝。B 的审核 Controller 已分离；应用服务中历史跨模块 SQL 尚待模块接口替换，不能报告完整分层完成。
- 完整链路通过真实 HTTP 登录、首次改密、注册、待确认拒绝、独立归属确认、组织候选、自审拒绝、审核生效及注销；同时核对数据库版本与两次应用审计。
- 安全证据覆盖角色注入、跨公司/部门/团队、待确认、自审、停用旧会话、调岗旧会话、注销旧 token、首次改密绕过、密码错误锁定、敏感字段泄漏，以及旧审核资格快照。真实 Android/其他端联调未验证，5.2 保持未完成。
- 性能：1000 合成员工（含其他夹具共 1008 人）、10 万日志/1 万任务与主负责人记录，10 次预热、20 并发、100 样本（每端点50）。最终组织树 P95 656.8 ms、审核列表 P95 266.0 ms，满足 B 关键请求参考目标≤2秒；报告及原始样本 output/member-b-performance.json。此证据不包括首页、AI、任务/日志读写或生产规模多次运行，首页指标仍由 E 协作。
- 初次联合构建曾因 Controller 移包后的旧 class 缓存导致 Spring Bean 冲突，clean 构建后消除；新增端到端断言曾漏算归属确认审计，修正为两次业务应用各一条审计。最终结果为上述 33 项通过，不以早期失败日志冒充最终通过。

## 阻塞与交接

- E：公共测试转交夹具/规则核对；公共 OpenAPI 快照和 auth/organization 契约确认；实际 Flutter 联调与首页性能；Sprint/看板仍按用户要求待关联。
- C/E：提供 TASK/LOG 及 dashboard 审核最终应用边界，参与同一事务。ReviewedRevisionApplication 仅为 B 提供的待接入接口，不是已完成应用实现。
- D/E：核对实际 outbox 投递、重试与端到端消息。当前验证涵盖 B 事务写入，不等于通知投递全部完成。
- 本地交接材料 output/交给E与C的协作清单.md；未发送给其他成员。Issue/PR 上记录对应未完成范围，暂不归档或合并。
- 用户随后明确“先不要推送到 GitHub 远端”：本次只做本地提交，不推送、不创建 PR、不继续更新远端 Issue。#3/#4/#5 是此前已经建立的 Issue，保持现状；任务 5.6 未完成。完整分层、C/E 契约确认、全套回归及客户端联调仍未完成，不将三批描述为已全部交付。
