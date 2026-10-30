# 验证记录（2026-10-30，本机 Windows）

- 基线：GitHub main `91908a7`；隔离工作树已有用户修改 `mobile/android/gradle.properties` 和未跟踪验收文档，均保留。
- `openspec.cmd validate --all --strict`：退出 0，42/42 通过。
- 直接调用 Dart SDK 的 `dart.exe analyze lib test/task_interval_http_test.dart`：退出 0；6 条既有弃用 info，0 error、0 warning。所改 8 个文件定向分析也退出 0。
- Flutter 定向测试：`task_interval_http_test.dart`、`task_display_test.dart`、`review_single_level_test.dart` 共 12 项，退出 0。新增 HTTP 捕获测试确认任务创建发送选中标签 ID 和幂等键，审批发送 `expectedVersion: 0`。
- `mvn.cmd -B -f server/pom.xml -DskipTests package`：退出 0，后端打包成功；此前定向 Maven 测试停在 Mockito 执行，未得到退出码，已中止，不计为通过。
- 用户启动 Docker 后，本机隔离后端场景 `scripts/verify-scenario-runtime.py` 退出 0，128/128 检查通过；包含真实任务创建、幂等重放、直属审核、自审拒绝和过期版本拒绝。日志在 `output/integration-20261030/hotfix-2e2e7d9d/`。
- Flutter `HttpRepository` 对另一个本机隔离后端的写入测试退出 0：当前可用标签创建任务、`expectedVersion: 0` 审批、失效标签拒绝、任务事件姓名和日志评论姓名均通过。日志在 `output/integration-20261030/hotfix-final-f6235ca9/`；测试源码在忽略目录 `mobile/.diagnostics/hotfix_local_write_test.dart`。
- 两次隔离测试使用随机容器、端口和密码，运行后容器已清理；未向云端写入测试数据。
- 手机已装 APK 与 main 对应关系未知；未安装新 APK，五项均需手机实测。创建/审批应特别检查当前角色、标签及直属审核关系。

## 未完成与风险

1. 重新构建、安装 APK，在手机上逐项复测五个问题；记录 APK 的 Git SHA。真实 HTTP 客户端测试不等于已安装手机页面验收。
2. 既有 Maven 定向测试未取得明确结论，不应把后端打包成功视作后端单元测试通过；隔离 HTTP 场景已通过。
