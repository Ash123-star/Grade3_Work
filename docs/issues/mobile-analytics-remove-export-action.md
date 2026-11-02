# 移除工作统计顶部导出入口

- 优先级P2，范围仅工作统计右上角导出下载按钮，用户明确要求删除。
- 演示AnalyticsPage与真实接口ServerAnalyticsPage均删除PageFrame导出actions；清理真实页面不再使用的go_router导入。
- 不改统计数据、筛选、权限和其他导出页面；保留既有混合改动，不提交推送。属于小范围可逆UI删除，不新增能力。
- 验收：两种数据模式工作统计均无顶部导出按钮，标题和返回保持；未运行测试、构建或设备验收。
- 静态证据：mobile目录执行 `D:/flutter/bin/cache/dart-sdk/bin/dart.exe analyze lib/features/common/demo_pages.dart lib/features/dashboard/server_analytics_page.dart`，No issues found，退出码0；`git diff --check`退出码0。差异仅删除两个顶部actions及未使用导入。
