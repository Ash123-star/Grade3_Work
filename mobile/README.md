# 潘多拉 Flutter 安卓前端

本工程实现 Android UI 框架和真实后端接入。默认使用后端 HTTP Repository；需要离线演示时显式传入 `--dart-define=USE_MOCK=true`。客户端不直接连接数据库、不调用 DeepSeek，不保存 API Key。

设计、接口与验收请从[文档索引](docs/README.md)进入。命令过程日志可放 `.diagnostics/`（Git忽略）；本批自动测试截图统一写入仓库 `output/flutter-evidence/`（Git忽略），不要再写入工程根目录；历史日志已整理，验收结论与截图保留在 `docs/`。

## 运行

2026-10-15 整合：真实模式 AI 地图工具栏的“长期记忆与发展分析”入口打开 `/ai/memory`，保留原有 AI 作业、建议编辑和人工确认流程。后端需要执行 V10/V11 记忆迁移，整合与验收边界见 `../docs/local-memory-integration.md`。

### UI 演示与真实后端启动（2026-10-12）

Android Studio 打开 `mobile/` 后，运行配置选择 **UI Demo**（`.run/UI Demo.run.xml`），用于评审本轮界面，无需注册或启动后端。或者在现有 `main.dart` 配置的 Additional run args 填写 `--dart-define=USE_MOCK=true`。**必须停止后重新运行，Hot Reload 不会修改 dart-define。**

```powershell
D:\flutter\bin\flutter.bat run --dart-define=USE_MOCK=true
```

生成可安装的 Mock APK 必须在构建时传入同一个编译期参数；仅在 Android Studio 的运行配置中切换后端地址不会改变 `AppConfig.mock`：

```powershell
D:\flutter\bin\flutter.bat build apk --release --dart-define=USE_MOCK=true
```

产物位于 `build/app/outputs/flutter-apk/app-release.apk`。当前交付副本为 `build/app/outputs/flutter-apk/pandora-mock-release.apk`。安装后不需要连接真实后端，数据来自本地 Mock Repository；Hot Reload 不会改变已编译 APK 的模式。

真实联调默认访问云端 `http://39.96.84.51/api`（80端口），使用真实后端。Android发布包仅为该IP允许HTTP；debug包保留本地联调支持。可用 `API_BASE_URL` 覆盖地址，修改后须重新运行或构建。

```powershell
D:\flutter\bin\flutter.bat run --dart-define=USE_MOCK=false
# 本地模拟器联调
D:\flutter\bin\flutter.bat run --dart-define=USE_MOCK=false --dart-define=API_BASE_URL=http://10.0.2.2:8080/api
```

真实注册加载 `/auth/departments`，提交部门 ID；密码至少 12 字符，注册后为待确认员工，不会直接进入业务页面。Mock 不等于创建真实账号。云端IP测试地址按指定HTTP白名单访问；HTTPS部署可用API_BASE_URL覆盖。

需要 Flutter 3.38.7 / Dart 3.10.7 或兼容版本、Android SDK、JDK 17。依赖已通过 pubspec.lock 固定。

```powershell
flutter pub get
flutter run -d <android-device>
flutter analyze
flutter test --dart-define=USE_MOCK=true
```

本机 Flutter 位于 D:\flutter，未加入 PATH 时可使用 D:\flutter\bin\flutter.bat。

### Windows 中文账号依赖与 SQLite 下载修复

若日志先报 `/C:/Users/%E5%BF%B5/...` 包文件不存在，使用下面脚本迁移到英文 Pub 缓存并由官方 `pub get` 重新生成包/插件配置。默认离线使用现有锁文件，缺包时加 `-Online`。成功后用户级 `PUB_CACHE` 更新为 `D:\FlutterPubCache`，**完全退出并重新打开 Android Studio** 后再运行，已有IDE不会自动继承环境。旧缓存保留，未升级依赖。

```powershell
powershell -ExecutionPolicy Bypass -File scripts/repair-flutter-pub-cache.ps1 -FlutterSdk D:/flutter -CachePath D:/FlutterPubCache
powershell -ExecutionPolicy Bypass -File scripts/prepare-flutter-sqlite.ps1
```

在仓库根目录执行。第二个脚本解决 sqlite3 原生库 GitHub Release 默认下载地址超时：从同项目官方 Release API 获取锁定版本的 Android x64/arm64/arm 二进制，逐项核对包内 SHA-256，然后预热默认构建钩子缓存。不会换成系统 SQLite、降级版本或改第三方源码。有效副本保存在忽略目录 `.native-cache/`，再次执行无需联网；**执行 `flutter clean` 后重新运行第二个脚本**。也可传 `-Architectures x64` 仅准备当前模拟器；`-LocalAssetDirectory <目录>`支持已下载的原版文件，校验失败拒绝安装。脚本本身不构建APK。

### 跨盘同步说明

Windows 上项目与 Pub 缓存位于不同盘符时，AGP 的 `generateDebugUnitTestConfig` 可能报 `this and base files have different roots`。`android/build.gradle.kts` 已将跨盘插件的构建输出放到插件目录下的 `build/pandora-<项目路径哈希>/`，避免相对路径跨盘，并隔离不同应用的构建产物。同盘插件及应用仍使用项目的 `build/`。修改后在 Android Studio 执行 **Sync Project with Gradle Files**。

可在 `android/` 目录验证原先失败的任务：

```powershell
.\gradlew.bat :flutter_plugin_android_lifecycle:generateDebugUnitTestConfig :shared_preferences_android:generateDebugUnitTestConfig
```

额外生成的 web/ 用于浏览器预览同一套 Flutter UI，不是方案中的 Vue Web 产品。

```powershell
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 5175
```

## 结构与接入

`lib/core` 管理配置、错误和 Riverpod 状态；`lib/routing` 管理 GoRouter 和五栏导航；`lib/theme` 负责应用主题组装；`lib/data/models` 定义模型，`lib/data/repositories` 提供可替换的 HTTP/Mock 数据源；`lib/features` 按认证、导图、视图、日志、AI 地图、我的和公共业务页面组织；`lib/shared` 提供布局与状态组件；`packages/cute_ui` 是通过 path 依赖引入的本地卡通组件包。页面和测试均使用新目录下的正式模块路径，旧顶层兼容导出已移除。

设置页面的“演示环境”可切换五角色、空数据、超时和无权限场景。角色切换只存在于演示模式，不是生产角色授予功能。演示业务变更保留在本次 App 运行期间，切换角色或账号不会清空（重启 App 恢复样例），日志草稿按用户和业务日期保存在设备上。

真实模式通过 `--dart-define=USE_MOCK=false --dart-define=API_BASE_URL=https://example.com/api` 启用，不会在 HTTP 失败时回退为虚假成功。请先按 docs/API_CONTRACT.md 对齐接口。鉴权、组织范围、审批路由和 AI 安全由服务端负责，客户端 guard 仅用于交互限制。

## 当前 UI 设计基线（2026-10-13）

当前 mobile 视觉采用暖白画布、分组表面、细边线和留白；柴犬只作少量品牌装饰，不代表用户身份或业务状态。真实用户头像、任务状态、权限、成功、失败和加载均保留各自语义。素材记录见 `assets/licenses/generated-ui-sources.json` 与 OpenSpec `frontend-requirements-adjustment`；实际资源包与设备显示仍以统一验收为准。

2026-10-13 已依 [阶段 3 设计](docs/stage-3-page-layout-and-interaction-design.md) 重建五个主页、连续日志编辑、任务时间线和审批对比布局，同时重排辅助表单、成员、设置和状态页，补齐验收成果、转派旧值、本人时间线与只读日志版本。正式附件、AI、管理/统计和安全草稿/会话恢复客户端已接现有契约；[实际 Flutter 八屏截图](docs/evidence/stage3-rebuild/stage3-rebuild-contact-sheet.png)、[组件与六姿态](docs/evidence/stage3-rebuild/41-sunny-component-states.png) 与[验收记录](docs/stage-3-verification.md)属于上一轮阳光纸张/动漫橙主题实现，不能证明团团记账新视觉已完成。团团记账风格目前处于设计基线和素材生成阶段，后续需按新文档重新迁移组件和页面。帮助反馈/退回补充/精细AI范围缺少现有服务端契约，真实服务/数据库/设备尚未联调，不能视为线上能力完成。

## 素材与许可

OpenMoji 通过 flutter_svg 从本地 assets 加载。作者、来源和 CC BY-SA 4.0 许可见 packages/cute_ui/ATTRIBUTION.md。Material Icons 用于常规工具按钮。

原创橙橙角色来源、六姿态用途和修改记录见[人物资产记录](docs/sunny-companion-assets.md)；人物采用项目自有矢量绘制，不冒充员工头像。


## UI 演示顺序（2026-09-22）

底部从左到右为：导图、视图、日志、AI地图、我的，默认导图。

1. 导图查看四大板块；从“时间视图”进入日、周、月安排，月历带圆点的日期有工作记录。
2. 默认团队长林小满派发任务，主负责人选择陈一诺。我的 → 设置切换员工（陈一诺），打开任务接收并提交成果。
3. 设置切回团队长，验收或退回补充；验收后归档。同一任务和通知在切换身份后保留。
4. 日志填写、查看正文、关联任务及评语；下属日志可选择成员并进入个人面板。
5. 员工修订日报，管理者在审批中心逐级复核；本人不可自审，正式正文在全部通过后更新。
6. AI 地图分为发展分析、堵点风险、行动规划，不再使用日周月筛选。管理者可切换个人发展与公司走向；建议可加入个人演示清单，支持编辑、完成与移除撤销。分析为预设样例，清单按账号隔离且仅本次运行保留，不会自动派发正式任务。
7. 我的 → 工作统计查看指标、部门分布、近七日趋势与筛选明细。
8. 我的 → 帮助与反馈查看说明、新手引导、提交反馈及待处理状态。

演示可在设置选择五种角色及三个账号。附件显示本地所选文件名；AI、反馈处理、导出不连接外部服务。审批角色用于演示，不代表生产审批授权。Android Studio 打开 mobile/android。

2026-09-22 最新布局：首页四块各预览前三条；月历大格内事件标签可点击，周视图七日横轴可左右上下滚动，日视图按24小时等比例排布。未设置时段的记录独立显示。页面已按新架构迁移；本轮命令行测试和 APK 构建未取得退出结果，不能据此报告为通过。截图见docs/screenshots。

日志页：我的日志按具体日期填写提交；管理者可切换下属日志，组合人员与日期查询。日志日期独立于视图页日期和周期。

日志列表默认展示全部日期的记录；日期筛选可清除恢复全部。下属日志可组合人员与日期筛选。未选日期时编辑入口对应今天。

## 当前正式页面接入（2026-10-13）

团团记账气质 UI 基线与阶段3业务布局共同指导后续开发；上一轮阳光纸张/动漫橙实现及验收记录见docs/stage-3-verification.md，不能证明新视觉已完成，历史演示记录也不能证明正式服务完成。正式AI支持既有作业创建/SSE/状态/取消/重试、来源阅读、人工草稿编辑、显式任务确认、地图/用量；范围由服务端身份决定，未配置供应商显示明确错误，基础业务不依赖AI。附件上传/下载和头像使用真实受控ID/字节，CSV使用已有同步接口，均有客户端HTTP/UI验证；真实服务器、数据库和设备尚需联调。演示须显式USE_MOCK=true，固定建议不冒充正式结果。原生加密Drift草稿/精确旧稿迁移、安全会话与启动身份验证已编写并有本地测试，AndroidKeystore/原生SQLite仍待设备验收，见docs/secure-local-state-verification.md。浏览器不持久化安全材料，只保留当前运行会话；支持反馈仍缺服务器契约。不构建APK。

2026-10-13 原设计补齐task2.20：日历/日志/报告完整分页、上海日期、正式日报聚合与草稿区分、周日期和未设时段固定上下文及滚动恢复已验收。最新144Mock/116formalHTTP、分析exit0，46单页截图；详见[验收记录](docs/stage-3-verification.md)。尚未完成真实服务/设备及产品契约缺口，不代表整体交付完成。

原成员工作台补齐2.21：完整授权分页、紧凑概览、独立成员日期与下属日志导航、失权整页清理和公开正式日志过滤；帮助无结果搜索/能力说明已纠正。最新156Mock/129formalHTTP、分析exit0、49实际单页证据，见stage-3-verification.md。

阶段3 task2.22：完整授权通用列表/消息忙碌与失权账号保护；设置→草稿与同步已读取实际加密稿及服务器日志版本，支持只读对照、独立选日和原版本编辑。最终分析、171全量Mock/144正式HTTP及追加后17项定向通过；51张实际Flutter页面证据。全部产品未完成，真实服务/设备和远程交付缺口见docs/stage-3-completion-audit.md；不构建APK。
