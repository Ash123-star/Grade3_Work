# 管理员简易后台验收记录

## 2026-11-13整合验收（当前结论）

后台PR #89已纳入整合PR #83的本地历史，保留默认简易后台、原组织/权限/公司事项管理及AI深链。完整后端规定脚本退出0：556项中553通过、3外部条件跳过，0失败、0错误；新后台浏览器20通过，原管理/AI浏览器48通过、6真实服务条件跳过，Web类型检查/构建及OpenSpec49项严格校验均退出0。真实HTTP/PostgreSQL账号开通、首次改密、公司隔离、独立审核、版本冲突和事务回滚断言未放宽；运行时OpenAPI已同步9个管理操作的错误响应。

统一命令、环境、证据、APK及外部限制见 [后端验证入口](backend-validation.md)。本批证据在忽略目录 `output/pr-merge/`，不把接口夹具当作真实设备验收；本次未部署。用户已明确授权直接推送main并合并PR，本批据此执行，不伪造非作者审批。下文按日期保留首轮失败、Docker/认证及交付经过，旧“全量失败/未运行/未创建Issue”等陈述仅对应当时，不再作为当前阻塞。

## 2026-11-12交付准备

用户明确要求提交PR后，使用独立`codex/admin-simple-console`工作区提取后台改动，保留原工作区文件和运行服务；GitHub连接器此前403，本机已认证CLI成功创建[Issue #88](https://github.com/Ash123-star/Grade3_Work/issues/88)。以`zhw`为PR目标，避免带入该分支尚未进入main的3个其他主题提交。测试生成的非后台OpenAPI变化和检索指标不纳入提交；配套界面截图使用合成夹具，已放入docs/screenshots/admin-console。全量失败限制不变，草稿PR不合并。已推送提交`6bd80d7`并创建[草稿PR #89](https://github.com/Ash123-star/Grade3_Work/pull/89)，目标`zhw`，关联Issue #88；原工作区和运行服务保留。

## 本地浏览器403修复（2026-11-12）

真实浏览器从5173登录返回非JSON的403 `Invalid CORS request`：旧`stage.env`仅允许Flutter的5175。先前不带Origin的HTTP检查不能证明浏览器能登录。本次修复`scripts/start-stage-demo.ps1`，新配置包含localhost/127.0.0.1的5173及5175，旧配置加载后同样合并这些精确来源，不启用通配符，不改正式安全规则。

仅重启本次演示Java进程，保留原pandora-stage数据库；真实Chrome通过5173验证管理员登录、员工目录、公司事项、登出，未授权Origin仍返回403，验证脚本退出0。截图`output/admin-console/real-browser-connected.png`，一次性检查脚本在同一忽略目录，不含硬编码凭据。本地前后端继续运行供用户试用。此项定向修复不重复全量业务回归，原全量失败状态仍保留。

## Docker启动后的补充验收（2026-11-11）

本节优先于下文首轮Docker不可用及“集成测试未运行”的历史记录。用户启动Docker后，已在隔离数据容器运行仓库规定的完整后端验收。

- `AdminConsoleIntegrationTest`：6项，失败0、错误0、跳过0，耗时3.689秒；真实HTTP/PostgreSQL链路已运行。
- `EmployeeProvisioningTest`：4项，失败0、错误0、跳过0。
- 已验证：创建ACTIVE/EMPLOYEE→初始密码登录→改密前业务拒绝→改密撤销旧会话→新密码读取Android公共业务；重复账号/手机无部分写入、禁止角色注入、公司隔离、停用人员搜索；员工调岗/停用独立审核与会话撤销；公司事项审核后与Android读取一致、旧版本冲突、第十一条置顶失败整体回滚和申请仍待审。
- 安全非功能：真实服务端ADMIN/公司/首次改密边界已通过。可靠性非功能：重复创建无部分角色/审计写入、版本冲突和置顶限制事务回滚已通过。
- 从运行中的测试服务 `GET /api/openapi` 获取HTTP200，核对8个后台路径/9个操作，并用真实SpringDoc操作定义替换`docs/openapi.json`对应静态增量。原始运行时输出见`output/admin-console/openapi-runtime.json`，此前静态未验证标记已移除。
- 完整命令 `powershell -ExecutionPolicy Bypass -File scripts/test-backend.ps1` 最终退出1，耗时7分20秒；JUnit合计466项，52失败、1错误、0跳过，即413通过。失败分布：`BackendIntegrationTest` 7失败/1错误、`WorkIntegrationTest` 42失败、`MemberBEndToEndTest` 1失败、`MemberBPerformanceTest` 1失败、`TaskComponentsTest` 1失败。本次后台6项集成和4项输入单测全部通过，不代表整个项目全量通过。未修改这些其他模块来规避失败，也未完成独立基线对照，不能将所有失败直接定性为本次无关。
- 可确认的部分失败现象：旧日志测试固定业务日期触发`FIRST_SUBMISSION_WINDOW`；旧审核测试预期PENDING而当前返回APPROVED。其他AI、端到端、性能及任务组件失败保留原始JUnit和完整日志，需单独梳理，不改变正式业务规则迁就旧预期。
- 本轮最终 `openspec.cmd validate --all --strict` 48项通过、退出0，`git diff --check`退出0。前端源码本轮未改，沿用上一批20项UI及类型检查/构建的真实通过证据，没有重复完整前端验收。
- 本轮后端日志：`output/admin-console/backend-docker-ready.log`；专项JUnit XML：`server/target/surefire-reports/TEST-cn.workpanel.module.organization.AdminConsoleIntegrationTest.xml`及`TEST-cn.workpanel.module.organization.EmployeeProvisioningTest.xml`。

以下为首轮验收历史，保留失败与修复经过，不外推为当前环境状态。

日期：2026-11-11（Asia/Shanghai）。OpenSpec：`admin-simple-console`。分支：`zhw`。Issue尚未创建：首次自动审批拒绝；用户随后明确批准创建仅含功能/验收/OpenSpec信息的Issue，调用GitHub返回403 `Resource not accessible by integration`，当前阻塞为连接器仓库写权限。

## 本批实现

新增ADMIN管理API、员工开通规则与输入单元测试、真实HTTP集成用例；Vue默认入口切换为员工/账号、公司事项、修改记录。员工直接创建ACTIVE/EMPLOYEE，首次改密；关键修改保持独立审核。无新表或迁移。已有用户压缩包和项目副本保留，未纳入本次修改。未提交、推送或部署。

## 已获得的结果

| 验证 | 命令/环境 | 结果 |
| --- | --- | --- |
| 规划严格校验 | `openspec.cmd validate --all --strict` | 48项通过，退出0 |
| 最终严格校验 | `openspec.cmd validate --all --strict` | 最终48项通过，退出0；差异空白检查修正原接口文档末尾空行后退出0 |
| Web类型检查及生产构建 | web中 `npm.cmd run build`，Node24.14.0、Vite6.4.4 | 修复候选字段模板类型后退出0；JS90.46kB，gzip34.74kB |
| 浏览器UI | web中 `npm.cmd run test:e2e -- --output=../output/admin-console/playwright-final` | 20通过，退出0；桌面1440×1000、窄屏390×844，使用接口夹具 |
| 后端编译/测试编译及输入单测 | `mvn.cmd -B -o "-Dmaven.repo.local=C:/Users/21692/.m2/repository" -f server/pom.xml "-Dtest=EmployeeProvisioningTest" test`，Java21.0.11 | 使用本机缓存并获执行权限后4项通过，退出0；主代码和集成测试源码编译通过，但未运行数据库测试 |

浏览器覆盖：管理员目录、FOUNDER拒绝、账号创建字段白名单/密码清除、重复失败保留表单、不自动重试、员工候选版本/原因、事项文本转义和待审提示、无审核人/禁止本人自审按钮、非JSON403清理会话、空状态、首次改密。人工查看桌面员工目录和窄屏事项抽屉截图，未发现页面横向溢出。

证据位于本机忽略目录`output/admin-console/`：`desktop-employees.png`、`mobile-employees.png`、`desktop-priority.png`、`mobile-priority.png`、`playwright-final/`、`backend-unit-final.log`。单测JUnit XML在`server/target/surefire-reports`。截图为合成夹具，不是生产员工或真实数据库验收。

## 失败、修复和环境限制

- npm首次默认缓存不可写；第二次项目缓存日志表明下载EACCES，未盲目重跑。获网络执行权限后按锁文件安装69个包，退出0。
- 首轮Web构建因模板key类型比较失败；修复后构建通过。
- 首轮浏览器已执行20项，其中失权后错误提示被请求代次判断吞掉，已修复；其他部分失败是测试同时匹配加载和成功status，改用明确成功提示定位。首轮执行器在退出阶段滞留，停止该会话；获得浏览器进程执行权限后复验20通过，退出0，不抹去原始失败。
- Maven默认缓存指向不可写的`C:/.m2`；显式参数需整体引号。缓存路径修正后受依赖JAR访问限制，获权限后编译和4项单测通过，保留原日志。
- 后端规定命令 `powershell -ExecutionPolicy Bypass -File scripts/test-backend.ps1` 初次和获得Docker访问权限后均退出1；本机Docker Linux引擎命名管道不存在，常规路径未找到Docker Desktop应用，未创建测试数据库。见`backend-full.log`和`backend-full-final.log`。脚本finally清理错误覆盖了较早创建失败信息，不能当作业务测试失败或通过。
- `AdminConsoleIntegrationTest`尚未实际运行：员工创建→真实登录/改密、重复账号事务、公司隔离、审核生效、停用会话、旧版本冲突及第十一项置顶原子回滚均待Docker环境验证。不能以UI夹具或编译成功报告这些链路已完成验收。
- `docs/openapi.json`为静态契约增量，新增操作带`x-verification-status`；Controller注释供运行时SpringDoc生成。后端运行环境恢复后需重新导出真实OpenAPI并比对，当前不冒称运行时快照已验证。
- 仅交付本地代码、构建产物和云端说明；未启动可用的真实本地后端，未部署现有云端。

## 非功能与交付边界

安全：输入单测已验证角色/公司字段注入拒绝；浏览器验证非管理员入口、失权清理和文本转义。真实服务端角色/公司隔离仍待数据库集成验证。

可靠性：浏览器验证创建失败保留输入且无自动重试；数据库唯一约束、审核版本与跨表事务已有实现及集成用例，尚未实际执行验证。

未自动提交推送：工作区存在本次之外的用户未跟踪目录、归档和压缩包，依AGENTS.md混合工作区规则停止自动发布。GitHub Issue首次被自动审批拒绝，用户明确批准后正常调用仍返回403，未创建Issue，不虚构编号。任务按实际证据勾选，后端完整验收、运行时OpenAPI和远程交付保持未完成。
