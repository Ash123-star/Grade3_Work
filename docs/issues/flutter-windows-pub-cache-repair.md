# 本地Issue：中文Windows账号Flutter依赖路径导致Android Studio启动失败

2026-10-13本地修复验收：ASCII Pub缓存与插件元数据已恢复，97包目录完整、用户环境设置/锁文件不变/重复与负向检查通过。用户随后日志暴露SQLite官方release网络超时，已从同官方Release API下载三Android ABI、核对包内SHA256、预热默认缓存；原失败钩子与x64/arm64/arm直接执行success exit0，损坏本地文件拒绝。分析/211Mock/181formalHTTP exit0；详见mobile/docs/windows-startup-repair-verification.md。未构建APK，旧模拟器安装不作为新版本证据，用户重启IDE再运行与混合工作区远程交付继续未完成。

优先级P0；关联OpenSpec flutter-windows-pub-cache-repair tasks2.1/2.2。首错为中文用户缓存URI `%E5%BF%B5`读取失败，继发Drift/cryptography/flutter_secure_storage/path_provider类型错误；实际依赖文件存在，生成Android插件登记漏新增插件。范围为本机依赖恢复与可重复脚本，保留所有业务功能、旧缓存和锁定版本，不构建APK。验收：ASCII实际包路径完整、插件登记包含安全存储/path_provider、锁文件不变、负向无效路径与编译证据；用户真实IDE运行和混合工作区远程交付保留未完成。
> 2026-10-13 交付更新：用户明确授权将全部当前修改提交并推送 HCJ；远程 Issue [#8](https://github.com/Ash123-star/Grade3_Work/issues/8) 已创建。以下混合工作区/gh 阻塞描述为历史记录，现采用 GitHub 官方 API 交付。真实服务与设备待验收项继续保留。
