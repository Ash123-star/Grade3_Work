# 阶段 2：已选视觉参考与 Flutter 设计工具

更新：2026-10-12。方向已确定为阳光纸张、动漫橙、Q 版人物、圆润组件。本文替代旧等待选择及沿用薄荷绿建议；数值见 [新版规范](stage-2-sunny-paper-design-system-plan.md)，查阅证据见 [主题研究](stage-2-ui-theme-research.md)。

## 1. 当前参考组合

| 对象 | 使用程度 | 职责 |
|---|---|---|
| [Duolingo 官方导航设计](https://blog.duolingo.com/core-tabs-redesign/) | 已阅读文章及界面展示 | 一致组件、人物与工作内容共存 |
| [Finch](https://finchcare.com/) | 已观察公开品牌视觉 | 人物比例、温和语气、陪伴式表达 |
| [Headspace](https://www.headspace.com/)及[产品页](https://www.headspace.com/app) | 已观察配色/产品展示 | 鲜明暖色、圆形、浅底与彩色内容区 |
| [Material 3](https://m3.material.io/)及[Flutter](https://docs.flutter.dev/ui/design/material) | 既有技术依据；本轮未重新完整查阅 | ColorScheme、组件主题、触控和语义 |
| Asana、Notion、Miro、Google Calendar | 后续结构参考，本轮未重新查阅 | 任务/文档/关系/时间结构，不再决定全局色板 |

## 2. 工具选择

- 项目本地 .agents/skills/flutter-ui-design/SKILL.md：原型、Material 3、人物许可、无障碍、统一验收。
- project-development-gate：需求、设计、实现批次和证据；本轮只更新设计。
- 浏览器：只读查看官方来源，后续核对原型和运行界面。
- Flutter 原生组件与 ThemeExtension：正式实现，不增加 UI 框架。
- 自有 SVG：本轮静态示意，最终人物另行评审。
- 位图生成或 Lottie/Rive：只有角色资产批次明确后才选，不自动增加运行依赖。

无需再安装外部 skill 才能推进阶段 2。cute_ui 调用方可渐进迁移，但组件视觉服从新版，不保留旧色板与小圆角约束。

## 3. 后续设计输入

目标：Flutter Material 3，360/390dp 手机竖屏企业工作台。

视觉：阳光纸张、动漫橙 #FF8A24、深可可 onPrimary、暖白卡片；普通卡 20dp、人物卡 24dp、按钮 18dp、字段 16dp、chip 胶囊；薄荷/天空蓝/淡紫/蜂蜜黄按语义分区。

人物：原创 2.5 头身伙伴；欢迎、书写、来源解释、成功、空状态；失败/待审不庆祝。

状态：loading、empty、error、forbidden、unauthorized、saving、saved、conflict、offline。

约束：48dp 触控、中文换行、字体放大、减少动态效果、版权登记；五栏默认导图、完整四象限、派发无完成情况、下属日志在日志页、AI 人工确认。

输出：令牌/状态矩阵 → 组件展示 → 导图/日志代表页 → 统一验收。

## 4. 交接状态

本轮完成研究、规范、静态示意和 OpenSpec 同步。新版 HTML、Flutter 和生产人物素材待实施。主色方向不再作为待选择任务；人物最终稿、组件截图及 AI 首屏信息结构在后续评审中确定。
