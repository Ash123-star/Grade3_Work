## Context
P0缺陷：用户启动日志首个错误为file:///C:/Users/%E5%BF%B5/...依赖读取失败。磁盘中文目录文件存在，但生成插件元数据缺flutter_secure_storage/path_provider_android。HCJ混合历史改动，不提交推送。

## Goals / Non-Goals
目标：在现有锁文件下恢复有效包路径及新增Android插件登记，可重复执行且不删除旧缓存/业务数据。
非目标：升级SDK/依赖、更改加密草稿、构建APK或声称设备运行通过。

## Decisions
比较逐条改生成URI（下次pub get覆盖且漏插件）与使用ASCII Pub缓存并官方重新生成（选择，版本兼容，可回滚，不修改SDK）。脚本从当前package_config已解码URI复制现有包到缓存对应hosted目录；配置文件缺失时由pub联网恢复。只复制受控Pub缓存文件，不删除/移动旧内容。默认缓存为FlutterSDK所在盘的FlutterPubCache，拒绝非ASCII路径及已占用文件路径。使用当前进程PUB_CACHE完成pub get --offline --enforce-lockfile；缺缓存以明确失败提示正常联网pub get，不盲目重复命令。成功后配置用户PUB_CACHE，用户需重启IDE以继承环境。保留原环境值记录在本地忽略日志；不输出密钥。

## Risks / Trade-offs
额外缓存磁盘空间；用户级环境对其他Flutter项目也生效，均可使用同一缓存。已有IDE不会继承新用户环境，需要重启。不存在可证明Android运行的无APK替代，验收只覆盖导入/插件/客户端编译；运行留待用户。

## Acceptance
P0员工开发者：脚本成功后所有package_config包路径存在/无百分号中文路径，Android安全存储/path_provider登记存在，pubspec.lock前后hash一致，分析与Dart测试编译通过；异常非ASCII缓存路径本地拒绝，不修改环境或文件，离线缺包明确失败。NFR可靠性重复运行、保留旧缓存；可维护性仅官方生成不手改SDK。测试本轮完整修复后统一执行，禁止APK。

## SQLite native download recovery
路径修复后用户日志确认第二故障：sqlite3-3.5.1默认GitHub browser_download_url连接超时。API api.github.com可达并能按application/octet-stream下载同官方release资产；x64 SHA256与包内完全一致。比较使用Android系统SQLite（符号/API编译选项不一致，可能破坏Drift功能）、降级2.x加新libs依赖（迁移成本，违反现有锁定版本）与预下载官方原库（选择，不改变程序）。独立脚本按package_config真实sqlite版本解析package内asset_hashes，默认x64/arm64/arm三架构，从GitHub官方Release API下载并验证hash后才缓存；支持用户提供匹配原版的本地文件，损坏文件拒绝进入官方hook缓存。持久副本在mobile/.native-cache（忽略），每次预热复制到官方按hash命名的共享hooks_runner目录；flutter clean后运行脚本恢复，不改SDK/第三方源码/生产配置。缓存有效时无需联网，下载失败保留旧缓存且明确失败。验收：下载/哈希一致、原用户输入hook返回success exit0、三架构直接hook验证、重复离线运行及损坏本地文件失败、版本不变；不构建APK，IDE完整链仍未验证。
