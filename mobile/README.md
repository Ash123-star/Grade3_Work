# 潘多拉 Flutter 客户端

Flutter 工程位于本目录。默认使用 HTTP Repository，离线演示需显式传入 `USE_MOCK=true`。Mock、接口夹具或历史截图均不能证明真实服务链路完成。当前设计、契约与待验收项从 [文档索引](docs/README.md) 进入。

## 运行

使用支持 `pubspec.yaml` 中 Dart `^3.10.7` 的 Flutter SDK、Android SDK 和 JDK 17；依赖版本以 `pubspec.lock` 为准。在本目录执行：

```powershell
flutter pub get
flutter run --dart-define=USE_MOCK=true
# 本地 Android 模拟器连接后端
flutter run --dart-define=USE_MOCK=false --dart-define=API_BASE_URL=http://10.0.2.2:8080/api
```

未覆盖 `API_BASE_URL` 时使用 `lib/core/config.dart` 中的地址。切换 `dart-define` 必须停止后重新运行；Hot Reload 不会更新编译期参数。真实注册只创建待确认员工；客户端不直接连接数据库，不保存或调用 DeepSeek API Key。

需要浏览器预览时可运行 `flutter run -d web-server --web-hostname 127.0.0.1 --web-port 5175`；独立 Web 管理端位于仓库 `web/`。

## Windows 依赖修复

中文账号导致 Pub 缓存 URI 错误时，在仓库根目录执行：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/repair-flutter-pub-cache.ps1 -FlutterSdk D:/flutter -CachePath D:/FlutterPubCache
powershell -ExecutionPolicy Bypass -File scripts/prepare-flutter-sqlite.ps1
```

首个脚本默认离线使用锁文件，缺包时加 `-Online`，完成后重启 IDE。SQLite 脚本从官方 Release 获取锁定版本并校验 SHA-256，缓存位于被忽略的 `.native-cache/`；`flutter clean` 后重新执行，可用 `-Architectures x64` 或 `-LocalAssetDirectory <目录>`。脚本不构建 APK。

跨盘插件构建目录由 `android/build.gradle.kts` 管理；修改配置后执行 Android Studio 的 Gradle Sync。

## 代码与素材

`lib/core` 管理配置和状态，`routing` 管理路由，`data` 管理模型及 HTTP/Mock 数据源，`features` 按业务组织页面，`shared` 和 `theme` 管理公共组件与主题；`packages/cute_ui` 是本地组件依赖。导航顺序为导图、视图、日志、AI地图、我的，默认导图。

运行素材在 `assets/generated_ui`、`assets/phosphor`、`assets/companions` 等目录；打包入口见 `pubspec.yaml`。`assets/new`、`assets/dog` 是当前加工脚本所需原图，`tool/` 保留其生成工具及桌面图标工具。来源和许可证见 `assets/licenses/` 及 [OpenMoji 署名](packages/cute_ui/ATTRIBUTION.md)，不得删除仍使用素材的署名。

## 验证与产物

后续开发按 [仓库流程](../docs/development-workflow.md) 集中验收，常用命令为 `flutter analyze` 和 `flutter test --dart-define=USE_MOCK=true`。真实服务专项需按各自测试文件的环境要求显式启用，不可对业务数据库盲目运行写入测试。

截图、命令日志、临时原型和诊断结果统一放仓库根目录 `output/`（Git 忽略），或本地 `.diagnostics/`。仓库只保留必要的结论、命令、环境、退出码和未解决问题；旧截图和阶段交付记录从 Git 历史查询。最新联调结果见 [2026-10-30 记录](../docs/frontend-backend-integration-validation-2026-10-30.md)，其中失败和待验收项仍需处理。本次仓库清理没有执行功能测试。
