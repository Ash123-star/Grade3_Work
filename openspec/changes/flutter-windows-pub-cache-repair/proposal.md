## Why
Android Studio启动在compileFlutterBuildDebug失败：Flutter读取中文用户Pub缓存的URI编码路径失败，新增依赖随后全部报类型未定义。现有生成插件登记还漏安全存储/path_provider插件。依赖文件实际存在，不能通过删除加密功能处理。

## What Changes
- 提供可重复执行的Windows依赖修复脚本，迁移当前锁定包到ASCII Pub缓存，使用Flutter官方pub get重新生成包/插件配置。
- 本机更新用户PUB_CACHE以避免IDE重启后复发，保留原缓存与锁定版本，记录IDE重启步骤及验证边界。
- 后续启动暴露SQLite原生库GitHub下载超时；增加官方Release API预下载、包内SHA256验证和原生钩子缓存预热，不改SQLite版本/功能。

## Capabilities
### New Capabilities
- `flutter-windows-dependency-bootstrap`: 中文Windows账号可在英文缓存恢复Flutter包与Android插件登记。

### Modified Capabilities

## Impact
仅开发环境脚本、README、Issue和OpenSpec；生成文件忽略，不修改Flutter SDK、业务权限/API/数据库或依赖版本。不构建APK，实际Android启动需用户IDE验证。
