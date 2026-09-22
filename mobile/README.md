# 潘多拉 Flutter 安卓前端

本工程实现 Android UI 框架和演示交互。默认使用 MockRepository，不连接公司数据库，不调用 DeepSeek，不发送短信或上传附件。

## 运行

需要 Flutter 3.38.7 / Dart 3.10.7 或兼容版本、Android SDK、JDK 17。依赖已通过 pubspec.lock 固定。

```powershell
flutter pub get
flutter run -d <android-device>
flutter analyze
flutter test
flutter build apk --debug
```

本机 Flutter 位于 D:\flutter，未加入 PATH 时可使用 D:\flutter\bin\flutter.bat。

### Android Studio 跨盘同步

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

lib/core 管理配置、权限快照、状态和错误；lib/data 定义模型、Repository、HTTP 适配器和演示实现；lib/features 包含五栏页面、业务表单和详情；lib/shared 提供布局与日期选择；packages/cute_ui 是通过 path 依赖引入的本地卡通组件包。

设置页面的“演示环境”可切换五角色、空数据、超时和无权限场景。角色切换只存在于演示模式，不是生产角色授予功能。演示业务变更保留在本次 App 运行期间，切换角色或账号不会清空（重启 App 恢复样例），日志草稿按用户和业务日期保存在设备上。

真实模式通过 `--dart-define=USE_MOCK=false --dart-define=API_BASE_URL=https://example.com/api` 启用，不会在 HTTP 失败时回退为虚假成功。请先按 docs/API_CONTRACT.md 对齐接口。鉴权、组织范围、审批路由和 AI 安全由服务端负责，客户端 guard 仅用于交互限制。

## 素材

OpenMoji 通过 flutter_svg 从本地 assets 加载。作者、来源和 CC BY-SA 4.0 许可见 packages/cute_ui/ATTRIBUTION.md。Material Icons 用于常规工具按钮。


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

2026-09-22 最新布局：首页四块各预览前三条；月历大格内事件标签可点击，周视图七日横轴可左右上下滚动，日视图按24小时等比例排布。未设置时段的记录独立显示。静态检查、15项测试及debug APK构建通过，Pixel虚拟机已重启并安装。截图见docs/screenshots。

日志页：我的日志按具体日期填写提交；管理者可切换下属日志，组合人员与日期查询。日志日期独立于视图页日期和周期。

日志列表默认展示全部日期的记录；日期筛选可清除恢复全部。下属日志可组合人员与日期筛选。未选日期时编辑入口对应今天。
