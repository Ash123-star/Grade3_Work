# 设计

## 目标边界

本次只做 Flutter 客户端内部结构迁移。Mock 数据必须继续通过与未来真实后端相同的 `Repository` 接口提供；本次不实现 token、接口重试、OpenAPI 生成、后端字段适配或真实联调。

## 目录与依赖

```text
routing -> features -> core / data / shared
theme   -> app shell
data.repositories -> data.models / core.errors
features -> data.repositories (Repository interface only)
```

`routing` 只负责路由和五栏壳层，`features` 按业务域承载页面，`core` 承载应用配置和 Riverpod 状态，`data` 承载模型与可替换数据源，`shared` 承载布局和状态组件，`theme` 负责应用主题组装。

## 迁移策略

先移动文件并修正 import，再拆分明显的大职责文件；迁移阶段保持现有路由路径、Mock 数据字段、页面行为和测试语义。任何后端契约变化另行建立变更，不在本次重构中混入。

## 验证

- `openspec.cmd validate --all --strict`
- `flutter analyze`（工作目录 `mobile`）
- `flutter test`（工作目录 `mobile`）
- 现有布局测试覆盖小屏、大屏、放大字体和所有路由。
