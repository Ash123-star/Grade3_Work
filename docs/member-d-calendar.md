# 成员 D 月历与节假日

负责人：刘逸冰（本轮按 D 分工）；Sprint 待关联。OpenSpec：member-d-calendar-holidays。

## 接口
GET /api/calendar/holidays?year=2026：已确认登录用户可读；2007..2100，越界400 INVALID_YEAR，未登录401，待确认403。只读、幂等，无分页和写版本。返回 year、days（date/name/isOffDay）、papers（国务院来源）、status、fetchedAt。FRESH 为24小时内成功获取；STALE 为刷新失败但保留旧数据；UNAVAILABLE 为尚无可信数据。无数据绝不等同“无假期”。

## 数据更新与部署
来源：https://github.com/NateScarlet/holiday-cn ，MIT；通过固定 GitHub contents API（Accept: application/vnd.github.raw+json）获取，无客户端直连、无密钥、无新增迁移。数据保留公告链接，严格验证年份、日期、重复项和调休布尔值。内存缓存24小时后下次读取自动更新；失败5分钟冷却后重试；重启清空缓存。运行服务器需要可访问该固定来源。查询相邻年份处理公告覆盖上年12月情况。

## 界面
每日0..5条完整显示；6条及以上显示4条和+n，点日期或+n打开全量清单。保留跨周连续条；相邻月份可点击，按实际日期显示任务。节假日单独占标签行，不占任务五行；星标与调休上班文字、长按显示完整名称、不可拖动。小屏和文字放大通过月历内部滚动保持完整。真实客户端加载源失败不阻塞任务；Mock 明确标注未加载真实节假日，不伪造线上数据。

## 回归修复范围
- AI 工作执行：已失败依赖的恢复扫描同时收敛工作状态，避免步骤失败后工作长期停在执行中。
- 组织目录：参与人统计改为一次聚合，管理员/创始人的公司范围条件消除冗余子查询；受限角色保持原权限范围。
- OpenAPI：避开 springdoc 对 Schema 字典的普通 Jackson 克隆限制，在自定义阶段加入完整模式，不删除字段类型。
- Flutter：历史日志标题不再使用当前正文；AI 错误提示保留输入；月历选中日期、相邻日期、完整清单与节假日展示适配。
- 测试夹具同步 main 的参与人、直属上级审核、附件及 AI 确认契约，保留权限、幂等、版本和数据落库断言。

## 验收记录（2026-10-31）
- Flutter：scripts/test-flutter.ps1，正式 HTTP 模式49项通过，Mock模式292项通过、3项真实服务 opt-in 跳过；退出码均0。证据 output/flutter-regression。
- Flutter analyze：No issues found，证据 output/member-d/analyze-delivery.log。
- 真实节假日：GitHub 公共数据经 Java 服务和 MockMvc HTTP 映射读取成功；缓存、失效、数据异常、超限、跨年共8项通过。专项同时验证 OpenAPI 和性能，共10项通过，证据 backend-final-performance.log。
- 性能：1000名合成人员、10万日志、1万任务及真实参与关系，20并发、100样本；组织和审核列表 P95 均低于2000ms，证据 output/member-b-performance.json。此结果不代表全产品性能验收。
- 可靠性：上游不可用时保留最后有效缓存，无缓存时明确不可用且不阻塞任务；限定响应256KiB和完整请求6秒。
- 后端全仓：scripts/test-backend.ps1，452项、0失败、0错误、1项真实来源 opt-in 跳过（已另行通过）；BUILD SUCCESS，退出码0。证据 output/member-d/backend-final-all.log。
- OpenSpec严格校验46项通过、0失败；git diff --check通过。OpenAPI生成文档无既有路径或模型丢失，保留服务端现有ReceivedTaskCard字段说明。
- 全仓性能复测组织列表P95 213.91ms，审核列表123.24ms；运行环境Windows 11、JDK21、Docker PostgreSQL16/Redis/Neo4j。

## 交付与限制
真实手机、正式部署服务及 SSE 全链路仍需联调；上述3项 opt-in 跳过不能视为验收完成。第三方数据源需要服务器能访问 GitHub；保留国务院公告来源但不是官方托管 API。没有新增 Flyway 迁移。
本地保留 .idea、个人环境和既有备份；指标文件不擅自覆盖。关联 Issue #60；本轮交付仅包含功能、测试及契约文件，个人配置与指标文件排除。

## 发布前复核（2026-11-03）
后端节假日真实来源/OpenAPI/性能专项10项通过；Flutter月历22项通过，退出码均0，证据 output/member-d/pre-pr-backend.log 和 pre-pr-calendar.log。
旧展示库启动发现 V12 checksum mismatch，需先核对旧库来源再制定升级方案，禁止直接 Flyway repair；独立测试库可正常执行迁移。旧库直接启动、真实浏览器登录/节假日全链路和手机验收不计为通过。
与 C 的月历拖动 PR #59 存在文件重叠，合并时需保留双方功能并重新验收。
