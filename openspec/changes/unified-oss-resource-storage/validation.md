# OSS统一存储验收

日期：2026-11-11，Windows PowerShell，Flutter SDK `D:/flutter`、Java 21、Maven 3.9.9、Docker隔离PostgreSQL/Redis/Neo4j。Issue [#79](https://github.com/Ash123-star/Grade3_Work/issues/79)。

## 基线与保留边界

- 原工作区19db6f3及全部用户改动保留。原分支隔离源码后端409项中91失败、6错误；OSS整合后的旧基线420项仍为同一97项失败，无新增失败。此结果不代表新基线。
- `git fetch origin --prune`退出0。独立分支`feature/79-unified-oss-latest`从origin/main（3f9eb2d）快进至其后、与线上一致的aa70b35，保留额外4个消息缓存/条件请求提交。原目录没有执行覆盖性pull/reset。
- 新迁移V31保留已发布V22–V30；导出仍沿用新版AnalyticsQuery/Repository筛选，在一致快照结束后写OSS并重新鉴权；头像校验接入ProfileRepository。
- 用户随后要求提交当前代码并创建中文说明的PR。本批以草稿PR供审阅，保留未完成验收；不扩大修复既有问题，未归档或修改线上服务/数据库。
- 当前分支包含尚未合并的PR #77原始4个提交。面向main的完整差异必须说明这部分依赖；后续单独保存在本地的消息请求自等待补修不在本批OSS提交中，也未推送至#77。已复现的前置消息请求挂起风险仍需独立处理，不计为OSS测试通过。

## 验收结果

| 检查 | 命令及结果 |
| --- | --- |
| 完整后端 | `powershell -ExecutionPolicy Bypass -File scripts/test-backend.ps1`；外层只载入OSS环境并设置`OSS_REAL_ACCEPTANCE=true`。退出1，524项：520通过、1失败、2错误、1跳过，耗时11分26秒。BackendIntegrationTest 18/18、MobileDataContractIntegrationTest 5/5、TaskDispatchIntegrationTest 41/41通过；WorkIntegrationTest 221项中220通过，保留策略夹具遗漏size_bytes导致1项失败，已修正并通过下述定向复验。跳过项为HolidayControllerTest的真实外部来源测试 |
| 修正后定向验收 | 相同后端脚本加`-Tests "WorkIntegrationTest#retentionClearsPrivateEvidenceAndOldAuditDetailsButPreservesFormalFiles,OssStorageIntegrationTest,RealOssStorageIntegrationTest,StoragePolicyTest"`：退出0，12项全部通过，0失败/错误/跳过，JAR打包通过，耗时2分5秒；覆盖夹具修正、逐份读取历史文件的迁移内存改进及真实321项静态发布。本次没有重复运行全套，不将定向通过报告为全套退出0 |
| GitHub原代码隔离复现 | 从aa70b35用`git archive`导出server和测试运行所需文件，不含OSS改动；只复用支持Tests选择器的测试脚本运行AnnualScenarioMultiFounderMigrationTest。退出1，3项中1通过、2错误，均为V1__annual_workplace.sql生成改期审核时reviewer_id为空，与整合分支一致。日志`output/oss/github-baseline-annual.log`，原始Surefire在`output/oss/github-baseline/server/target/surefire-reports/`；未修改已发布年度迁移或放宽审核约束 |
| OSS后端与真实供应商 | 完整测试中的OssStorageIntegrationTest 6/6、StoragePolicyTest 3/3、RealOssStorageIntegrationTest 2/2通过。真实业务上传/鉴权下载、生成文件、历史迁移重放、数据库副本清除/恢复、删除后404，以及321项素材逐项上传/哈希读回通过；静态发布及网关抽样读取首轮74097毫秒、定向复验68802毫秒。测试对象清理无错误 |
| Flutter全项目分析 | `flutter analyze --no-pub`退出1；17处既有提示，3处未用import、14处花括号lint，位于未修改文件 |
| 本次Flutter源码分析 | `dart analyze lib/core/assets lib/main.dart lib/shared/curated_assets.dart test/oss_asset_bundle_test.dart`退出0，无问题 |
| Flutter相关测试 | `flutter test --no-pub test/oss_asset_bundle_test.dart test/attachment_assignment_http_test.dart`退出0，23项通过；覆盖依赖图像/字体、完整性、缓存/离线、私有路径隔离及原附件界面/HTTP链路 |
| Web | `npm run build`退出0，类型检查及Vite构建通过 |
| OpenSpec | `openspec.cmd validate --all --strict`退出0，47项通过、0失败 |
| 全量盘点 | `prepare-oss-assets.ps1`及`oss-resources.ps1 -Command inventory`退出0；321项、80583656字节，含依赖OpenMoji、Material/Forui图标字体、Inter、FontManifest及依赖许可证 |
| 真实OSS探针 | `oss-resources.ps1 -Command probe`退出0；随机verification对象写入/读回SHA-256一致、匿名403、删除成功 |

日志位于忽略目录`output/oss`：完整后端日志`backend-full-latest.log`和Surefire副本`acceptance-full-latest/`；定向复验`backend-acceptance.log`；其他检查为`flutter-analyze.log`、`oss-source-analyze.log`、`flutter-tests.log`、`web-build.log`、`inventory.log`。真实供应商测试只在显式`OSS_REAL_ACCEPTANCE=true`时运行，其全量清单及耗时写入`real-publication.json`。凭据只从原工作区忽略文件`deploy/backend/.env`读取，不复制到仓库或记录其值。真实测试使用独立数据库和随机前缀，结束后删除对象；不代表生产素材已激活或历史文件已迁移。

## 非功能与未完成项

- 安全/隐私：私有桶/对象、公开清单白名单、鉴权先于对象读取、私有路径不进公共缓存；生成文件每次校验来源和身份，禁止永久绑定。最小RAM策略尚未审计，操作成功不能证明没有额外权限。
- 可靠性：独立上传意图、长度/哈希校验、失败删除重试、原子发布、迁移重放/恢复、离线与损坏资源回退；完整数据库提交失败断点、删除与绑定竞争故障矩阵尚缺。
- 本机SDK产生的无关lockfile变化不作为依赖升级提交。双端实际网络渲染、冷启动/缓存指标、TalkBack、全部生产文件用途链路未完成；不以单元测试或网关HTTP读回代替。
- SSH只读确认`collaboration-server`运行于`/opt/Grade3_Work/server`，线上aa70b35、workpanel_annual2026数据库为V30；保留远程未提交部署改动。远程尚无OSS环境，`/api/assets/manifest`返回401。未上传环境文件、重启服务、执行生产V31/历史迁移或激活素材。
- 本轮授权提交并创建草稿PR，不代表验收完成或获准合并、部署、归档。任务勾选不代表整体功能完成。
