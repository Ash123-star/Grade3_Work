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
额外生成的 web/ 用于浏览器预览同一套 Flutter UI，不是方案中的 Vue Web 产品。

```powershell
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 5175
```

## 结构与接入

lib/core 管理配置、权限快照、状态和错误；lib/data 定义模型、Repository、HTTP 适配器和演示实现；lib/features 包含五栏页面、业务表单和详情；lib/shared 提供布局与日期选择；packages/cute_ui 是通过 path 依赖引入的本地卡通组件包。

设置页面的“演示环境”可切换五角色、空数据、超时和无权限场景。角色切换只存在于演示模式，不是生产角色授予功能。演示业务变更仅保留在当前 Repository 生命周期，日志草稿按用户和业务日期保存在设备上。

真实模式通过 `--dart-define=USE_MOCK=false --dart-define=API_BASE_URL=https://example.com/api` 启用，不会在 HTTP 失败时回退为虚假成功。请先按 docs/API_CONTRACT.md 对齐接口。鉴权、组织范围、审批路由和 AI 安全由服务端负责，客户端 guard 仅用于交互限制。

## 素材

OpenMoji 通过 flutter_svg 从本地 assets 加载。作者、来源和 CC BY-SA 4.0 许可见 packages/cute_ui/ATTRIBUTION.md。Material Icons 用于常规工具按钮。
