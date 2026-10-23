# PR #31 集成与 Android APK 验证

日期：2026-10-23（Asia/Shanghai）。关联 PR #31、Issue #30；OpenSpec 沿用本 PR 的四项移动端变更，不新增产品能力。

## 来源与集成范围

- 移动端来源：HCJ `c120c06ab954122fa224aac9c06aa45982f13a04`。
- 集成基线：main `413ad87f4177ca6a5902c357ca669a3a832a188e`。
- 在独立工作目录集成，原工作目录的未提交改动没有纳入提交或 APK。
- 唯一文本冲突位于 `form_page.dart` 的只读参与人展示：保留 PR #31 的 `taskParticipantNames`，同时保留 main 的日志修订申请提示。
- 修正五个回归测试文件：显式跨越手势识别距离、为路由动画推进首帧、任务夹具补充参与人字段、按全宽六字月历与自适应轨道验收、定位个人页纵向滚动容器。
- 月历测试仍验证可见轨道不越过日期格，并验证当天弹层完整呈现全部三条记录；没有以减少断言替代完整记录验收。
- 本次冲突处理与测试修复没有新增 API、数据库迁移或业务权限变更。

## 环境与依赖

- Windows / PowerShell；Flutter SDK `D:/flutter`；Android SDK `C:/Users/HY/AppData/Local/Android/sdk`；Android Build Tools 36.0.0。
- 使用仓库锁定依赖。离线恢复依赖后撤销仅由镜像地址变化产生的锁文件改动，不提交个人 SDK 路径、缓存或代理配置。
- 首次测试被 SQLite 官方下载连接超时阻塞；复用本机已缓存二进制并逐项核对锁定 sqlite3 3.5.1 包提供的 SHA-256，未修改第三方库源码。
- 构建日志保存在独立目录 `output/pr31-apk/`；交付副本保存在原工作目录 `output/pr31-apk/`，均被 Git 忽略。

## 已执行验证

| 验证 | 命令或范围 | 结果 |
| --- | --- | --- |
| OpenSpec | `openspec.cmd validate --all --strict` | 37 项通过，退出码 0 |
| Flutter 分析 | `flutter analyze --no-pub --no-fatal-infos` | No issues found，退出码 0 |
| 修改后的测试文件分析 | 对五个修改后的测试文件执行 `dart analyze` | No issues found，退出码 0 |
| Mock 全套 | `flutter test --no-pub --dart-define=USE_MOCK=true --concurrency=2 --reporter=expanded` | 313 项通过、2 项跳过，退出码 0 |
| 正式接口契约与组件 | 22 个文件，`USE_MOCK=false` | 200 项通过，退出码 0 |
| Android 真实接口调试包 | `flutter build apk --debug --no-pub --dart-define=USE_MOCK=false --dart-define=API_BASE_URL=http://10.0.2.2:8080/api` | 构建成功，111.3 秒，退出码 0 |
| Android 离线演示包 | `flutter build apk --release --no-pub --dart-define=USE_MOCK=true` | 构建成功，194.2 秒，退出码 0 |
| APK 签名与元数据 | `apksigner verify --verbose`、`aapt dump badging` | 两包退出码均为 0，v2 签名有效 |

正式接口契约集的可复现选择方式（从 `mobile/` 执行）：

```powershell
$contractTests = @(Get-ChildItem test -File | Where-Object {
    $_.Name -like '*http*test.dart' -or
    $_.Name -like '*contract_test.dart' -or
    $_.Name -in @('branch_pager_test.dart', 'sibling_pager_test.dart',
        'sibling_swipe_test.dart', 'task_display_test.dart',
        'secure_local_state_test.dart')
} | Sort-Object Name | ForEach-Object { 'test/' + $_.Name })
D:/flutter/bin/flutter.bat test --no-pub --dart-define=USE_MOCK=false --concurrency=2 --reporter=expanded @contractTests
```

两项跳过分别是需要显式开启环境开关的 `member_b_real_backend_test.dart` 与 `member_b_log_live_test.dart`，不算通过。本次没有用真实账号调用后端。

额外诊断：将全部测试不加区分地设为 `USE_MOCK=false` 时，包含依赖 Mock 默认登录态与演示仓库的测试，结果为 297 通过、22 失败、2 跳过；该诊断运行退出码 1，不报告为通过。失败涉及 AI 输入组件默认身份、日历弹层、演示导航及旧阶段演示工作流。它们在 Mock 全套中验证，正式接口行为由上列 22 文件单独验证；全部演示夹具的模式隔离仍是后续测试维护项。原始日志为 `tests-all-http-diagnostic.log`。

## 非功能与界面证据

- 可靠性：分页测试覆盖相邻页连续布局、停稳后单次路由提交、多指取消恢复、边界与内部横向滚动；真实接口契约覆盖失败重试、幂等及旧会话响应隔离。
- 安全与隐私：安全本地状态与认证契约测试覆盖加密草稿、账号隔离、权限失效及受保护数据清理。
- 已查看实际测试生成的 360dp 月历及 412dp/1.5 倍文字个人页截图；未据此宣称真机帧率或完整业务链路通过。

## 安装方式与限制

两包 applicationId 为 `cn.pandora.pandora_mobile`，版本 `0.1.0+1`，minSdk 24 / targetSdk 36，包含 arm64-v8a、armeabi-v7a、x86_64。

| 产物 | 字节数 | SHA-256 |
| --- | ---: | --- |
| `pandora-pr31-api-debug.apk` | 220492177 | `47E841EDF1DBDD776141D223305F17C9BF42153E22D48354339AEC43C464A114` |
| `pandora-pr31-demo-release.apk` | 120761679 | `EB30BD23747576E9A21DB9853CEF00C26C0828403DE444C555781A8F063ACF2C` |

- 真实接口调试包：`pandora-pr31-api-debug.apk`。后端默认地址是 Android 模拟器访问宿主机的 `http://10.0.2.2:8080/api`；实体手机需要按可达后端地址重新构建。
- 离线演示包：`pandora-pr31-demo-release.apk`。编译为 `USE_MOCK=true`，不代表真实企业数据或真实业务提交。
- 两包沿用相同 applicationId，安装时会互相覆盖；如遇签名不一致，不自动卸载或清除用户数据。
- 仓库 release 仍使用 debug 签名，供本地测试；没有配置或生成生产发布密钥。
- Release 构建保留 CupertinoIcons 字体未包含的告警；当前应用源码未显式引用 `CupertinoIcons`，没有为消除此告警增加依赖。日期选择器等组件的设备外观仍需核查。
- 本机 `adb devices` 未发现已连接设备。本次不含设备安装、冷启动、触控流畅度、系统开屏与真实业务链路验收。
- 用户已明确豁免本次非作者审阅与真机验收；补审阅、真实后端和真机验收仍需保留后续记录，Issue #30 不据打包成功关闭。
