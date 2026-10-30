# 实现和部署记录

日期：2026-10-30；Issue #49；分支 chore/annual-scenario-dataset。

源码已接入：公司任务卡片与完整列表共用个人参与任务接口，记录含本人派发且参与任务；日志使用正文摘要标题；任务/日志/审核/审计姓名不回退账号或ID；人员接口按权限聚合实时任务数量和上海当日日志状态，页面字段缺失显示未知。恢复视图任务管理入口，主月历默认本人参与，显式成员月历保持指定成员。

规划阶段OpenSpec严格校验45项通过；之后用户要求立即提交部署、不要测试。本批未运行自动化测试、分析器、移动端编译或设备验证；回归测试源码已更新但未执行。后端仅在云端执行部署所需的跳过测试打包。OpenSpec实现任务保持未勾，不能报告已验收。

此前五个年度数据库修复文件单独提交，包含已经在云端失败回滚后修正的年度V1 manager别名，不修改正式V1–V23。云端年度初始化开关保持关闭，不重新生成/清空数据。

云端部署于2026-10-30完成：源码提交113e30b；隔离目录按该提交打包，Maven使用-Dmaven.test.skip=true，退出码0、BUILD SUCCESS，未编译或运行测试。13:54:49（Asia/Shanghai）日志记录Started Application；14:09复核systemd为active/running，PID 772425、NRestarts=0，8080由该进程监听。Flyway启动校验23项迁移通过，public版本23，无需迁移。上述仅为部署运行证据，不代表功能验收通过。

云端备份目录/root/workpanel-deploy-20261030.D649S2保留旧JAR、数据库备份、原配置和工作区差异；云端原有CI工作流及Dockerfile改动已保留，旧脚本改动另存stash及patch。PR #50为本批草稿PR，尚未合并main。部署记录后续提交仅修改文档，运行JAR对应113e30b。

手机APK不会因后端重启自动更新。PR #48 评审中的驳回表单expectedVersion遗漏仍独立待修复，本批未更改。

2026-10-30后续修复，Issue #51：审核详情改用中文业务快照和状态说明，服务端仅投影已授权快照内同公司引用的当前名称；补齐历史派发通知和生产通知类型中文/路由映射、已读网络失败不阻断合法详情；审批卡片占满列表可用宽度。规划OpenSpec严格校验45项通过。按用户要求未执行编译、自动化测试、HTTP或设备验收；仅人工阅读差异，以上实现均未验收。本批未部署云端、未重新生成APK，原运行JAR仍为113e30b。数据库无迁移。

2026-10-30后续交互修复，Issue #52：短时提示使用根Overlay并区分成功/信息/警告/错误；表单、详情、通知及组织操作错误通过PageFrame悬浮层显示，不加入底部操作栏或编辑区布局；可关闭并重新展开，保留恢复动作。团队名称追加服务端team_name并归一化客户端映射，统计筛选优先组织树名称，移除ID兜底；公司重点实心圆。月历取消六字符及单日宽度上限，按每周任务段宽度显示并预留右侧10dp，超出省略，每周续接首日重复标题。规划OpenSpec严格校验45项通过；未运行编译、测试、HTTP或设备验收，未部署/打包APK；任务维持未验证。接口无数据库迁移。

回归断言源码已同步：月历移除六字符/单格截断预期，补充完整跨周名称和右侧10dp边界预期；提示用例改为Overlay替换与关闭预期。未执行这些用例。


## 2026-10-30 统一编译与回归（Issue #49/#51/#52，替代此前暂不测试约束）

本轮回归修复：通知保留服务端业务标题，仅转换协议代码；短时提示的计时器随组件销毁释放；组织配置恢复动作置于悬浮提示内；月历恢复溢出计数并在账号权限变化时清空已打开的记录、停止无权限查询；新日志编辑器兼容恢复本账号旧修订草稿并保留版本冲突保护。新增审核快照与通知展示断言，更新已读失败导航、中心弹层及修订草稿断言。

已获得明确退出码0的检查：
- `openspec.cmd validate --all --strict`：45项通过。
- `flutter analyze --no-pub`：无问题。
- `flutter test --no-pub --dart-define=USE_MOCK=true --reporter expanded test/calendar_agenda_test.dart test/calendar_agenda_visual_test.dart test/sunny_design_system_test.dart test/record_display_test.dart test/management_analytics_http_test.dart test/inbox_sync_contract_test.dart test/review_notification_display_test.dart`：58项通过。
- 隔离复制server源码后执行`mvn.cmd -B -f .diagnostics/backend-package/pom.xml -DskipTests package`：生产及测试源码编译、JAR打包成功，退出码0；该命令跳过测试执行，不能代替后端全量测试。
- `flutter build apk --debug --no-pub --dart-define=API_BASE_URL=http://39.96.84.51/api`：APK打包成功；手机需安装新APK才能获得界面变更。

未通过或未完成的检查：
- 移动端全量测试（USE_MOCK=true）：最后结果301通过、3跳过、27失败，停在task_label_selector_test的异步请求；中断执行退出码1。失败分布在AI文案/布局、人员工作区、旧页面及截图断言、日志与审核交互等；未逐项证明是旧用例还是功能缺陷，不报告全量通过。
- 本地规定的后端验证脚本因缺少data镜像失败，镜像拉取又遇Docker Hub网络超时。既有运行JAR被本地进程占用，因此不能原地重打包，改用隔离目录。
- 云端以b76891d源码、独立临时数据容器执行等效`mvn -B -f server/pom.xml clean verify`，不使用业务数据库。已观察到BackendIntegrationTest的6个断言失败和1个错误（审核版本、任务响应、AI数量/审核、转部门数据范围、首次日志提交日期窗口）；迁移升级及日志等其他已完成测试有通过记录。WorkIntegrationTest仍在执行时SSH会话停止返回，新SSH握手超时；缺少最终退出码，不能报告后端全量验证完成。测试目录记录于云端/root/workpanel-verify-current-path，恢复连接后需核查测试进程、结果与临时容器清理。

权限/隐私验证覆盖：审核投影不显示内部ID、通知401/403和旧账号响应不导航、月历切换账号清除旧记录；可靠性/易用性覆盖：提示替换关闭、已读失败仍打开合法详情、草稿冲突保留本机正文、月历跨周与大字号几何。以上仅为相应用例证据；真机、无障碍设备及全量真实服务链路仍未验收。PR保持草稿，禁止报告可合并。

本批不新增数据库迁移、不重建或重新播种业务数据库；云端原有CI/Dockerfile等改动保留。云端本轮拉取至b76891d，但运行服务最后确认仍为113e30b，新版JAR替换和重启尚待成功证据。

16:23前后复核：两次新SSH连接均在banner exchange阶段超时，已有SSH会话无响应；云端API直接与经本机代理访问均超时（HTTP000）。未执行服务停止或JAR替换，无法判断是网络还是主机资源问题，不能报告已重启。恢复连接后先检查负载和隔离验证进程，再安全清理本批测试容器并完成备份部署。


## 2026-10-30 17:00 云端更新完成（替代此前连接阻塞状态）

重新连接后确认主机可用，原后端运行；此前测试Java进程已不存在，未得到全量测试最终退出码。删除本批唯一遗留且已退出的临时验证容器workpanel-verify-1793346455，不操作业务数据容器。云端原有CI/Dockerfile及备份文件改动保持原状。

云端分支chore/annual-scenario-dataset已快进至4a1885f。按该提交git archive到/opt/Grade3_Work-build.mlcFMA隔离构建，低内存Maven `-DskipTests package`退出0，BUILD SUCCESS；没有重新执行全量测试。

备份目录/root/workpanel-deploy-20261030.2a05gg（0700）保存旧JAR、年度库pg_dump自定义格式备份、年度环境配置、systemd配置、源码提交及工作区差异。确认业务库仍为127.0.0.1:55432/workpanel_annual2026，场景初始化开关关闭；没有改连接、重置或播种数据。

替换JAR并重启collaboration-server成功，部署脚本退出0：16:59:54（Asia/Shanghai）日志Started Application，Flyway验证23迁移成功，public已是最新且无需迁移。服务PID9214，active/running，NRestarts=0；新JAR SHA256为10a33c0b1c15ff27d801cc2d060d78be3988ca2cf0eee0052a07b207a0606c3d。公网http://39.96.84.51/api/health于17:00返回HTTP200、status=UP。

本次仅确认新版部署与健康响应，不代表此前全量测试失败已解决。PR #50继续保持草稿且未合并main。后续仅部署文档提交不需要重建JAR，运行产物源码对应4a1885f。
