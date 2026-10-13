## Why
用户选择 Forui、Untitled UI、Phosphor，希望导入精致软件组件和猫狗装饰，并保持动漫橙主题。
## What Changes
- 引入兼容当前 SDK 的 Forui 0.17.0，仅使用胶囊标签；颜色和字体由当前主题提供。
- 下载 Phosphor 官方 SVG 图标与许可证，应用于五栏导航和四象限入口。
- 增加原创橙猫和奶油犬矢量素材，应用于欢迎区、个人页装饰；保留业务正文清晰。
- 核对 Untitled UI 获取及使用边界；未取得的 Figma 原始文件明确列为未导入，使用自主布局参考其层级与间距。
## Capabilities
### New Capabilities
- `flutter-curated-ui-assets`: 动漫橙主题下的精选组件、图标及猫狗装饰。
### Modified Capabilities
## Impact
仅 mobile 资源、依赖、主题适配、UI和测试。后端、权限、日期、草稿、任务状态、导航顺序不变。关联本地 Issue docs/issues/flutter-curated-ui-assets.md。
## 本批需求调整（2026-10-13）
用户验收指出线性图标和原创动物装饰不足，要求网络卡通角色跨页面复用，以及明确卡片边框、周月报分区装饰。将图标与装饰主资源调整为GitHub公开卡通角色PNG，保留本地加载和现有文字、路由、权限。来源可免费下载不等于授予商业授权；如实记录来源即可，本批不阻塞于采购流程。

## 最终用户反馈
用户拒绝网络角色风格，恢复此前Phosphor/Material图标及原创猫狗与WorkBuddy，移除角色素材执行路径。保留边框阴影和报告分区。前述角色方案是撤回记录，不作为当前实施依据。
