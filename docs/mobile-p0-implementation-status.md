# 移动端 P0 接口实现记录

日期：2026-10-29；分支：HCJ；关联 `mobile-page-experience-refresh`。

本记录描述当前源码接入状态，不代表编译、测试、迁移、HTTP联调或部署通过。用户要求所有功能接口实现后再统一测试；本轮没有执行测试、分析、编译、构建、服务启动、OpenSpec校验或数据库迁移。既有测试文件改动予以保留，未运行或据此勾选任务。

## 本轮实现与契约矩阵

所有路径均以 `/api` 为前缀，认证使用现有会话，错误为 `{code,message,traceId}`。只读接口无幂等键和写入版本要求；分页沿用非负 offset `cursor` 与 `limit=1..100`，排序以唯一ID收尾。空 `nextCursor` 表示统计明细结束。

| 链路 | 请求 | 响应/行为 | 权限与异常 |
| --- | --- | --- | --- |
| 任务卡片 | GET `/tasks/received-card`；cursor/limit/search | items/total/nextCursor；phase、参与人、标签、最早真实DISPATCHED的dispatchAt；缺失时间为null并排最后；验收/归档/撤回历史保留 | 现有任务范围，不新增仅当前接收人的范围限制；无效分页/关键词400 |
| 任务日历 | GET `/tasks`；from/to或date/period；participantId，ownerId兼容别名 | 任务区间与左闭右开查询范围相交；无start_at以deadline作为点；反向区间不命中 | 别名冲突、时间条件混用/不成对/反向400；参与人越权403/404；普通任务列表继续隐藏阶段/完成字段 |
| 日志范围 | GET `/logs`、`/logs/subordinates`；from/to或date/period，ownerId；下属支持departmentId/search | 服务端组合过滤；列表/详情统一已有组织范围或真实祖先关系；下属仅在职成员已提交记录；普通列表保留原范围内历史成员已提交日志 | 草稿仅本人；from/to须为上海自然日零点；无效400、越权403/404 |
| 月份状态 | GET `/logs/subordinates/calendar`；ownerId/month=YYYY-MM | ownerId/month/employmentStartDate/days/logIds；完整自然月SUBMITTED/MISSING/FUTURE/UNKNOWN；logIds为已提交日号到ID | 管理入口、同公司授权成员；未知入职日不猜填，失权拒绝 |
| 正文直改 | PUT `/logs/{id}/content`；work/version | 原始submitted_at不变、版本增长、历史/审计/outbox同事务；旧LOG待审候选失效 | ACTIVE作者、已提交、首次提交未满24h；过期LOG_EDIT_WINDOW_EXPIRED，非已提交LOG_NOT_SUBMITTED，旧版本VERSION_CONFLICT，非作者403 |
| 首次提交及旧接口 | POST `/logs/{id}/submit`；version | 仅上海今天、昨天、前天首次提交；旧revisions/withdraw明确返回DIRECT_CONTENT_REQUIRED | 超三日FIRST_SUBMISSION_WINDOW；旧LOG审核handler不可应用，V22将存量待审LOG标记SUPERSEDED |
| 资料读写 | GET `/profiles/{id}`；PUT `/profiles/me`，选填资料字段/version | 顶层phone/email/gender/age权威列；JSONB merge简介/头像；返回入职日、部门/团队；缺席字段不变，选填null清空 | 本人写；本人、真实祖先、已有全局范围读；保护字段400，重复PHONE_CONFLICT，旧版本409，头像须本人上传 |
| 统计汇总 | GET `/analytics`；date/period/groupBy/departmentId/teamId/ownerId | 真实阶段事件数量、分组、自然日趋势、当前阶段分布、带分子/分母的率 | 同一AnalyticsQuery/Repository源；非法筛选400、越权403；不返回待阅日志指标或私人字段 |
| 统计明细 | GET `/analytics/details`；同上+metric/groupId/bucket/cursor/limit | 同一事实来源计数与分页；日期桶按上海自然日，明细不包含日志正文 | metric白名单：dispatched/received/feedback/accepted/overdue/diarySubmitted/onTimeAcceptance及实际phase代码或中文标签；非法400 |
| CSV | GET `/analytics/export`；相同筛选+resource=logs/tasks | UTF-8 BOM；任务按真实派发日、日志按业务日；稳定排序；10000条上限，超限不截断；公式前缀/引号转义 | 同一授权来源，非法resource400，超限EXPORT_TOO_LARGE |
| 单级审核 | POST `/reviews/{id}/decision`；approve/reason/expectedVersion | DIRECT_MANAGER单次决定即应用；MEMBERSHIP采用ADMIN_MEMBERSHIP；fresh Actor与当前关系复核；审计/outbox同事务 | 自审拒绝；驳回需理由；旧申请/目标版本409；失效审核人不能读或决定；无有效审核人保持PENDING |
| 历史申请继续 | POST `/reviews/{id}/reroute`；无body字段要求 | 申请人替代旧待审步骤、保留已决历史；当前有效创始人明确继续非MEMBERSHIP申请时按原业务权限/版本免审应用，重复已免审返回原结果 | 非申请人403，其他终态409；迁移不执行候选；成员确认仍管理员 |

## 统计口径

- 任务指标每种类型按任务最早实际DISPATCHED/RECEIVED/FEEDBACK/ACCEPTED事件计数，缺事件不从phase补造；任务组织分组/筛选采用当前负责人归属，延续现有统计模型。阶段分布表示所选区间真实派发任务的**当前**阶段，不宣称历史组织或历史阶段快照。
- 按期验收率分母是区间内首次实际验收任务；分子要求最新REVISED之后存在有效验收且不晚于当前deadline。逾期按区间内当前deadline已到且未按时有效验收的任务，排除WITHDRAWN。当前截止时间或修订变化会影响这些现时口径，不能宣称冻结的历史快照。
- 日报按已提交business_date计数。分母累加当前授权在职成员可信入职日起至今天的区间自然人数日；存在未知入职日时denominatorKnown=false、rate=null，不假造历史员工日期。已停用成员的既有授权历史日志仍可见，其历史在职范围不足时同样不能推断完整率。
- 无任何事实时图表数组为空；存在事实时趋势补齐区间自然日的零计数。零分母或未知分母的rate为null。
- summary、details和export共享授权和筛选。tasks CSV对应dispatched对象集合，logs CSV对应diarySubmitted对象集合；其他指标通过details读取，不能拿不同指标总数要求CSV数量相等。

## 数据库与兼容性

V22为当前未跟踪、未发布的迁移文件，只在server Flyway路径维护。新增用户资料/入职日列、约束与索引、审核模式/来源、SUPERSEDED状态及每申请唯一PENDING步骤。只清理成功转存的合法JSON重复值，非法/冲突旧值保留；phone保持唯一、允许NULL，新注册仍按现行契约要求手机号。老员工入职日保持NULL，新确认员工在确认生效事务写上海日期。

迁移保留已决审核步骤，将旧待审步骤替代；历史LOG候选失效；其他待审按当前直属关系、MEMBERSHIP按管理员路由，无有效人则保持待审；通知用稳定outbox去重键。迁移不自动批准或应用历史创始人候选。发布前需备份，实际升级/回滚方案必须在统一验收时确认；不得回滚已应用V22后修改旧迁移。

## 最后统一验收待办

1. 按当前全部差异补齐/更新测试夹具，特别是旧多级审核、缺expectedVersion、旧LOG修订/撤回、任务from/to互斥等过时假设；不得削弱新产品规则。
2. 运行后端标准脚本、真实PostgreSQL V21→V22升级/HTTP集成、受影响Flutter测试和分析、必要构建与设备流程，记录明确命令/环境/退出码及安全/可靠性证据。
3. 启动真实服务后从 `/api/openapi` 生成 `docs/openapi.json`；当前文件保留旧快照，未手工伪造。对照新增路由、schema、错误、管理员别名及移动端YAML。
4. 最后执行OpenSpec strict与差异检查，再按证据更新task。全部功能仍为“代码已接入、未验证”，无功能任务勾选。
5. 保留既有 `mobile/handoff.md`、未跟踪CLAUDE.md和其他模型的测试/计划改动；混合工作区归属未确认前不提交、推送或创建PR。本记录不覆盖旧交接文档。

本P0批次原先未包含P1。2026-10-29用户随后授权补齐剩余接口并取消意见反馈；评论/退回/AI/团队目录等最新状态见 `docs/mobile-remaining-api-implementation-status.md`。原17点UI/设备历史失败仍待最终验收，不因接口接入而宣称解决。

## 续接源码核对修正

- 审核列表与详情统一保留当前仍有权限的已决历史，SUPERSEDED步骤不授予读取权限。
- 月状态与logIds使用同一次已提交查询；日志/资料递归上级授权共享拒绝循环链的条件，仍保留既有合法组织范围。
- 统计明细结束游标在Flutter转换为null；LOG_UPDATED通知支持返回日志详情；草稿接口遇到已提交记录明确引导content接口。
- 趋势和分组补齐diaryDenominatorKnown及率字段，运行时schema与YAML同步；OpenSpec、Issue及旧缺口文档标明本批未验证，并修正MEMBERSHIP例外及性别自由文本规则。
- 日报统计页面在分母不可信时展示资料不足原因，不把部分人数日当作完整应提交数；年龄迁移支持完整PostgreSQL整数存储范围，超范围旧值保留而不转换。

以上均为源码实现记录，无新增运行或测试证据。

## 2026-10-29 数据库与统一验收更新（取代此前本批未执行验收的状态）

用户已授权最终编译测试，且明确无需同步其他实际开发数据库。独立本地 PostgreSQL 已执行 server Flyway V1–V23；升级、资料列、历史数据保留、确认回执约束及核心 HTTP 契约得到运行验证。V22/V23 满足当前实现的数据存储需要，无需新增重复字段。最终后端定向 41 项通过、移动端定向 35 项通过，后端打包、Flutter analyze、正式接口模式 Android APK、Web build 均退出 0；运行服务已重新导出 docs/openapi.json。

整体仍未验收通过：最终 Flutter 全量 281 通过、3 跳过、44 失败；后端此前全量 425 项中139失败、21错误，修复后只重跑受影响定向组，不能外推全量通过。另保留设备、部署镜像数据库版本、真实供应商及 OpenAPI 展示警告等待验证。具体命令、日志、缺陷修复和剩余动作以 `docs/database-contract-verification-2026-10-29.md` 为最新依据。HCJ 工作区混合改动未提交/推送。