# Tasks

本阶段以 MVP 分工为准，PRD 为参考。负责人 B；工作分支 lyb。Issue：认证 #3、组织 #4、审核 #5；Sprint 按用户要求保留待关联。任务依据实际证据更新，提案文件齐全不等于代码已交付。

批次顺序：准备 → 第一批认证 → 第二批组织 → 第三批审核 → 综合验收。每批开始前报告分支、工作区、允许修改文件和验收方式；各批测试及文档随实现完成，不拖到末尾。

## 1. 追溯与实施准备

- [x] 1.1 在平台建立认证、组织、审核三个 MVP Issue，关联本 change、任务及负责人；Sprint 按用户明确指示保留待关联，不创建虚构编号；以真实 Issue #3/#4/#5 和 docs/member-b-delivery.md 追溯记录验收。
- [ ] 1.2 与 E 确定既有 API、身份适配、错误码及共享设施协作边界，并映射 initial-product 2.1–2.4、architecture-modularization 等任务；以契约记录和任务映射验收，不重复勾选未验证旧任务。
- [x] 1.3 固定本次实施前的接口/数据库/测试基线，记录 Java 21、PostgreSQL/Redis 环境和当前 9/10 回归；以无密钥的基线报告与测试原始证据验收（docs/member-b-delivery.md；output/backend-environment-test.log）。

## 2. 第一批：认证闭环

- [x] 2.1 将注册调用接入 auth 应用服务与 repository，落实员工待确认、唯一账号/手机号及部门有效性；以正常注册、非法手机号、重复注册、角色注入和无部分写入单元/HTTP 集成测试验收（AuthPolicyTest、AuthIntegrationTest）。
- [x] 2.2 新增下一可用 Flyway 版本的登录防护状态表及清理策略，不修改历史迁移；以空库初始化、已有库升级、唯一键并发及清理保留期测试验收，并记录迁移说明（V5；AuthIntegrationTest；docs/member-b-auth.md）。
- [x] 2.3 实现五次失败锁十分钟、成功清零、统一凭证失败提示和停用拒绝，失败事务提交后再返回错误；以可注入时钟的阈值/到期/锁定不续期单元测试和多请求真实数据库测试验收（authClock；AuthPolicyTest、AuthIntegrationTest）。
- [x] 2.4 接入改密应用用例并保护首次改密限制，验证旧密码、新旧相同、密码长度及敏感字段保护；以正确改密、无效输入和改密前业务拒绝 HTTP 测试验收，公共过滤器问题交 E 协作（AuthIntegrationTest）。
- [x] 2.5 接入注销与当前身份查询，验证旧 token 立即失效、停用/调岗后下一请求使用当前状态；以真实会话集成测试验收，保留重复注销的现有 HTTP 未认证契约（AuthIntegrationTest）。
- [ ] 2.6 补齐认证接口 JavaDoc/schema、权限/参数/错误/版本/幂等说明和本批验证报告，与 E 同步运行时文档和快照；以接口文档与实际响应一致、无密码/token 摘要泄漏验收。

认证文档与运行时说明已完成，E 的快照/客户端核对仍待确认，2.6 未全部完成。证据见 docs/member-b-auth.md、docs/member-b-delivery.md。

## 3. 第二批：组织闭环

- [ ] 3.1 将组织树、部门、人员读取接入应用服务和带范围条件的 repository；以五角色、跨公司/部门/团队、待确认与超过 100 人结果完整性测试验收；分页契约先与 E 确认。
- [x] 3.2 提取角色、账号状态、团队部门一致性、负责人及汇报关系规则；以正常关系、缺失实体、跨公司、非法角色和汇报环单元测试验收，禁止 Controller 编写 SQL（OrganizationPolicyTest、OrganizationIntegrationTest）。
- [x] 3.3 接入归属确认、调岗、停用、复核职责和策略的现有候选申请入口；以提交后旧值不变、申请合法性和独立审核后范围生效的集成测试验收，保留当前分开申请语义（OrganizationIntegrationTest、MemberBEndToEndTest）。
- [x] 3.4 在最终应用时重新验证组织约束，序列化最后有效管理员保护并检查版本；以并发停用/调岗、最后管理员和等待审核期间组织变化测试验收（OrganizationIntegrationTest、ReviewIntegrationTest）。
- [x] 3.5 更新组织接口说明、权限矩阵和本批验证报告，记录 MVP 与参考 PRD 差异；以实际授权响应一致、历史任务/日志未被删除和文档交叉核对验收（docs/member-b-organization.md；OrganizationIntegrationTest）。

3.1 的人员范围与113人查询已通过；E 的分页/客户端契约核对仍待确认，保持未完成。

## 4. 第三批：审核闭环

- [ ] 4.1 分离 review Controller、应用编排、领域决定和 repository，并接入实际调用路径；以同一入口正常审核测试和 Controller 无 SQL/核心规则检查验收。
- [x] 4.2 验证团队→部门→公司路由、任务可配置层级及独立公司复核，缺少独立人保持待审；以逐级流程、空缺审核人和策略自身独立审核单元/集成测试验收（ReviewIntegrationTest、OrganizationIntegrationTest）。
- [x] 4.3 实现或补齐当前审核人授权、自审禁止、空白驳回原因拒绝、终态不可重复处理；以正向通过/驳回及越权/无效决定 HTTP 测试验收（ReviewPolicyTest、ReviewIntegrationTest；额外验证已撤销职责的旧身份快照拒绝）。
- [x] 4.4 对审核决定加并发控制和最终业务版本校验，旧值保持到全部通过；以两候选竞争、重复决定、旧版本冲突和事务回滚数据库测试验收，不额外新增单条待审限制（ReviewIntegrationTest）。
- [ ] 4.5 与 C 建立 task/log 验证及应用接口、与 D/E 建立同事务审计/outbox 协作；替换 review 对其他模块的直接 SQL，以真实业务应用失败回滚、成功一次写入与事件不重复的跨模块集成测试验收；外部实现未就绪则保持未完成。
- [x] 4.6 更新审核接口、状态机、错误/版本/幂等说明及本批验证报告；以申请人/审核人/时间/前后值审计可追溯和契约一致验收（docs/member-b-review.md、docs/member-b-delivery.md；ReviewIntegrationTest）。

4.1 仅完成 Controller 分离、领域输入规则和列表 repository，完整应用分层仍有历史 SQL；4.5 缺 C/E 的业务应用实现，ReviewedRevisionApplication 尚未接入，两项均未完成。

## 5. 综合验收与提交

- [x] 5.1 执行注册→登录→归属申请→独立确认→组织候选修改→审核生效真实 HTTP/数据库链路，保存可复现步骤和脱敏响应；正向、越权、自审和冲突均有证据才完成（MemberBEndToEndTest、AuthIntegrationTest、ReviewIntegrationTest；output/member-b-delivery-final.log）。
- [ ] 5.2 完成设计列出的至少 12 类安全验收，与 E 联调 Android 和同契约入口；以无越权、无敏感泄漏且双端一致报告验收，未验证端单列。
- [x] 5.3 在记录硬件/数据规模/并发/预热/样本的环境测量关键组织和审核请求性能；参考 20 并发、10 万日志/1 万任务及 P95≤2 秒，以实际报告验收；小样本仅算诊断，首页指标由 E 协作（MemberBPerformanceTest；B 组织656.8ms、审核266.0ms；output/member-b-performance.json；首页未验证）。
- [ ] 5.4 与 C/E 核对并修复 scopedTasksIdempotencyAndLifecycle 的范围/夹具问题，执行 powershell -ExecutionPolicy Bypass -File scripts/test-backend.ps1（资源不足 -DockerMaven）；以全套通过且保留报告验收，不降低业务授权。

5.4 阻塞：用户要求公共测试保持原样、交 E 处理；不能以 B 的定向通过替代全套通过。
- [ ] 5.5 执行 openspec.cmd validate --all --strict，更新 Issue/看板、贡献记录和受影响旧 change 任务映射；以严格校验通过及证据链接验收，不提前归档。
- [ ] 5.6 检查 git diff --check 和工作区归属，按批次提交并推送 lyb、创建或更新 PR，包含 Issue、设计、迁移、验收及风险；以实际提交/远程分支/PR 链接验收，认证或网络阻塞如实记录。

5.6 按用户最新指示：只允许本地验收和分批提交，暂不推送到 GitHub，也不创建远程 PR；因此整个任务保持未完成。既有 Issue #3/#4/#5 已在此指示前创建，此后不更新远端。

## Workflow follow-up

- 功能实现、验证和非作者审阅完成后再考虑合并；规划阶段不自动合并。
- 经验收后同步主规格，核对实现一致性并归档，执行严格校验；不能用本次提案完成代替 initial-product 的功能完成。
