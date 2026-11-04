## 1. Plan

- [x] 1.1 阅读设计基线、现有主题、路由、资源和工作区状态
- [x] 1.2 建立本变更 proposal/design/spec/tasks

## 2. Assets and theme

- [x] 2.1 裁剪装饰图集并生成 ASCII 命名资源
- [x] 2.2 接入 pubspec、资源目录和授权记录
- [x] 2.3 更新 Material 3 / ThemeExtension token

## 3. Components and pages

- [x] 3.1 建立本地素材组件和纸张背景
- [x] 3.2 更新卡片、弹窗、底部弹层、Toast 和图表容器
- [x] 3.3 更新导图样板页
- [x] 3.4 更新视图和日志页的视觉组合

## 4. Verification

- [x] 4.1 Flutter analyze 和受影响测试
- [x] 4.2 360/390/412dp 与 1.5 倍字体截图
- [x] 4.3 OpenSpec strict 与 git diff --check
- [ ] 4.4 真机、TalkBack、真实后端联调

## 5. Screenshot repair batch (2026-10-14)

- [x] 5.1 记录截图需求、路线比较、本地 Issue 和严格规划校验
- [x] 5.2 修复资源脚本 UTF-8 路径/裁剪/背景清理，登记源和输出 SHA256，保留原图
- [x] 5.3 公共纹理/边界/按钮/筛选器/Toast/标题组件接入真实状态和无障碍
- [x] 5.4 重做欢迎卡叠层、紧凑四象限、更多右对齐、详情分区、AI 建议与我的入口
- [x] 5.5 月历屏幕内完整显示七列、无需横向滑动，均衡单元高宽，以纯颜色标签和单行标题简写保留最多两条/+N，保留当天完整列表
- [x] 5.6 全批统一 analyze/测试/资源检查/360-390-412及1.5截图/strict/diffcheck 并记录证据
- [x] 5.7 原生设备/TalkBack/真实服务验收（不得以 Mock 与截图替代）

## 6. Complete page coverage (2026-10-15)

- [x] 6.1 全路由/状态/弹层素材接入与审计（不能只提供首页证据）
- [x] 6.2 GenSen Rounded TW 本地授权粗圆字体打包、标题及关键数字迁移、正文保持可读
- [x] 6.3 全页面截图、交互回归、字体/素材加载、窄屏大字与失效回退验收
- [x] 6.4 接入潘多拉应用图标、Android 原生启动占位和 Flutter 开屏动画，保留 reduced-motion 与离线回退

## 7. AI map simplification (2026-10-20)

2026-10-21 用户追加：删除欢迎卡及“点击开始分析，基于已有任务…”空状态说明，开始分析固定在页面底部、五栏导航之上；保留顶部三 Tab。本次追加验收完成前不视为旧验收覆盖。

- [x] 7.5 完成底部固定分析按钮、移除欢迎卡及空状态说明，验证正式/演示与模拟器

- [x] 7.1 同步已确认范围、设计、规格与本地 Issue，并完成实施前严格校验
- [x] 7.2 精简正式与演示 AI 首页，统一卡片/开始分析/三 Tab 顺序，保留失败恢复和权限规则
- [x] 7.3 统一运行分析、受影响测试、窄屏大字与模拟器验收、严格校验和差异检查并记录证据
- [ ] 7.4 检查混合用户改动，满足条件后提交推送和 PR；阻塞时明确记录

7.4 阻塞：原有两个 pubspec.lock 用户改动保留，依 AGENTS.md 第 4 节停止自动提交/推送；GitHub CLI 未登录，远程 Issue/PR 待关联。验收证据见 [历史文件](https://github.com/Ash123-star/Grade3_Work/blob/05d6c25b24d7b4304d8e4b1414adebee1f85fc38/mobile/docs/ai-map-layout-verification.md)。
