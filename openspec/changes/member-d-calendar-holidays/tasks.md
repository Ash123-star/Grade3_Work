## 1. 实现
- [x] 1.1 实现服务端节假日查询、校验、缓存更新和降级
- [x] 1.2 实现任务行及相邻月份交互（早期五行折叠由完整行要求替代）
- [x] 1.3 接入节假日星标与状态提示
## 2. 验收
- [x] 2.1 测试0/5/6/多条、跨月跨年、长名称及失败
- [x] 2.2 后端、Flutter、OpenSpec验收并记录结果

## 验收证据
- 节假日真实 GitHub 来源经 Java 服务和 HTTP 映射成功：output/member-d/holiday-live-test.log，8项通过。
- 全部 Flutter 顶层测试经 scripts/test-flutter.ps1 分模式执行：output/flutter-regression/http.log 49项通过；mock.log 292项通过、3项真实服务 opt-in 跳过。
- 后端全仓：output/member-d/backend-final-all.log，452项、0失败、0错误、1项真实来源 opt-in 跳过（已另行验证）。
- OpenAPI字典初始化、补充真实参与数据的性能专项和真实来源测试共10项通过；最终全仓退出码0。Flutter analyze无问题，OpenSpec严格校验46项通过。未提交/推送；Issue/PR交付与真实手机/SSE验收仍待处理。
- 真实手机、正式部署服务/SSE全链路不在上述测试证据内，不能报告完成。

## 交付跟踪
关联 Issue #60。2026-11-03发布前后端10项、Flutter月历22项复测通过。旧展示库V12校验冲突、真实浏览器/手机/SSE验收及与C的PR #59月历兼容合并仍待处理，详见 docs/member-d-calendar.md。
