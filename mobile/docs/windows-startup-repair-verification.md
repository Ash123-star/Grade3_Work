# Windows Android Studio 启动依赖修复验收（2026-10-13）

关联本地Issue/OpenSpec `flutter-windows-pub-cache-repair`。本次只验证用户日志中的两处直接阻塞，不等于整个Android产品运行验收。

## 1. 中文路径与插件元数据

首个日志错误：`/C:/Users/%E5%BF%B5/...`无法读取新增Flutter依赖，随后Drift/cryptography/path_provider/flutter_secure_storage类型均未定义。实际文件存在。脚本 `scripts/repair-flutter-pub-cache.ps1` 将发布包复制到`D:\FlutterPubCache`，排除损坏的临时build/.dart_tool/.gradle目录，复制锁定hash信息，由官方`pub get --offline --enforce-lockfile`重新生成。

实际退出码0，重复执行退出码0；97个package_config包目录均存在且ASCII。用户PUB_CACHE已设为`D:\FlutterPubCache`，旧缓存保留；脚本内部锁文件SHA256前后一致。Android插件元数据包含flutter_secure_storage、path_provider_android及JNI，Java生成登记包含FlutterSecureStoragePlugin/JNI。path_provider新版使用JNI链，不能要求不存在的旧Java插件类。非ASCII缓存目录负向检查明确拒绝，环境保持不变。脚本为UTF-8 BOM以兼容Windows PowerShell5.1中文。

## 2. SQLite原生下载超时

第二个用户日志为sqlite3-3.5.1钩子访问GitHub release下载超时。原链接curl连接超时退出28；同仓库官方Release API可达，API按octet-stream返回同官方二进制，无非官方镜像、SDK修改、版本降级或系统SQLite替代。

`scripts/prepare-flutter-sqlite.ps1`下载包内固定版本，验证package内SHA256后写`.native-cache`（忽略）并预热默认hooks_runner共享缓存。三架构实际校验：

| Android ABI | SHA256 | 钩子结果 |
|---|---|---|
| x64 | 949965f0eba976f707ae364cdcb42c342b5f0626081f8d7f0378fb7b52848772 | success / exit0 |
| arm64 | 0c2d3bfc8c87abceb21ed72a4bb49964121c5fe1a8ef3848d83ba907d01b6161 | success / exit0 |
| arm | a42fa9d0f5c006d30b000d4904bc497705191c5d7330b178618546004295bb49 | success / exit0 |

已直接执行用户日志对应hook.dill --config=input.json，x64返回success；同输入仅调整architecture/out_file后arm64/arm也返回success exit0。无Gradle/APK任务。缓存重复预热无需网络exit0；人为损坏的ia32本地文件SHA256不符明确拒绝，未写官方hook缓存。执行flutter clean后再次运行预热脚本。

## 3. 客户端验收及限制

修复后整批统一分析exit0，全量Mock **211项exit0**，16文件正式HTTP契约 **181项exit0**（含当前已完成AI关系图批次）；日志graph-final-analyze/mock/http.log在本机忽略。测试编译证明当前客户端导入/存储/页面代码可编译，未执行APK构建。规范校验最终结果见对应任务及验收记录。

模拟器中现有前台App的安装时间早于本次修复，因此不作为新版启动通过证据；旧安装观察图已在目录整理时删除。当前Android Studio需要完全退出再打开以继承用户环境，然后重新运行UI Demo。完整模拟器Gradle安装/运行、设备Keystore/SQLite仍待验证，tasks3.1未勾选；混合HCJ工作区不自动提交/推送。原始过程日志已清理，命令与结果记录保留；后续日志统一放`.diagnostics/`。
