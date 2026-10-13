## ADDED Requirements
### Requirement: Curated components and local icons
客户端 SHALL 使用本地Phosphor及Material功能图标和兼容Forui标签，继承动漫橙主题。
#### Scenario: Navigate offline
- **WHEN** 用户点击五个导航入口
- **THEN** 图标本地加载，顺序和路由不变，无素材网络请求
#### Scenario: Accessible label
- **WHEN** 用户放大字体或使用辅助阅读
- **THEN** 标签有文字，触控入口仍可用，无溢出
### Requirement: Companion decoration
客户端 SHALL 用原创猫狗装饰欢迎区与个人页，装饰不改变业务状态或遮挡操作。
#### Scenario: Welcome and profile
- **WHEN** 用户打开首页或个人页
- **THEN** 显示与橙主题协调的原创猫狗，业务信息及操作可读
### Requirement: Honest asset provenance
导入素材 MUST 保留来源、版本与原文许可；未取得资源不得宣称已导入。
#### Scenario: Missing original kit
- **WHEN** Figma原文件或具体角色授权未取得
- **THEN** 在资源记录与待办明确说明，未明确的授权不得宣称已获得
### Requirement: Framed business sections
客户端 SHALL 为卡片及周月报提供统一边框、柔和阴影和独立内容分区。
#### Scenario: Large text reports
- **WHEN** 用户在360dp和1.5字号下阅读周月报
- **THEN** 正文完整、分区有标题、源日报仍可打开，装饰不覆盖操作
