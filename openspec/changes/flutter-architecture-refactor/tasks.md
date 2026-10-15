## 1. 设计与迁移

- [x] 1.1 建立 `routing`、`theme`、业务域和数据子目录
- [x] 1.2 迁移现有路由、页面、模型、Repository 和共享组件并修正 import
- [x] 1.3 保持 Mock/HTTP Repository 接口和现有页面行为

## 2. 验证

- [x] 2.1 运行 OpenSpec 严格校验
- [x] 2.2 运行 `flutter analyze`（统一验收已完成：无 error，仅保留 2 个 `curly_braces_in_flow_control_structures` lint 提示）
- [ ] 2.3 运行 `flutter test`（本轮未取得命令退出结果；用户已在本地启动应用进行运行验证）
- [x] 2.4 记录迁移后的页面和布局验收结果（用户已确认应用可运行；五栏入口和主要页面由运行态检查）
