# 2026-10-23 实施与验证记录

## 已接入

- PandoraSplash替换旧纸纹/图片卡片/宣传语，以CustomPainter曲线绘制用户新图标风格角色，只展示应用名称；使用集中三色值与1280ms入场、短暂停留、最后约384ms淡出。
- 根Stack与底层IgnorePointer→ExcludeFocus→ExcludeSemantics→child链在过渡前后不变，结束仅删除第二个遮罩。使用控制器完成监听，无Future延迟，底层保持不透明并行启动。减少动画时180ms静态淡出。
- 原生启动7个XML变更：黄底、配套矢量mark、日夜模式系统栏、普通及v21启动layer-list和v31启动icon。不再引用旧launch_image。未删除旧文件、不修改桌面图标源图。
- main.dart与SessionBootstrap、鉴权、路由逻辑不改。保留HCJ原有混合改动，未提交推送或创建PR。

## 静态证据

1. 根目录 `openspec.cmd validate --all --strict`：33 passed / 0 failed，退出码0。
2. mobile目录 `D:/flutter/bin/cache/dart-sdk/bin/dart.exe format lib/shared/pandora_splash.dart`：退出码0。
3. mobile目录 `D:/flutter/bin/cache/dart-sdk/bin/dart.exe analyze lib/shared/pandora_splash.dart lib/main.dart`：No issues found，退出码0。
4. Python ElementTree解析7个修改/新增XML成功；color资源包含#FFD52B，brand_splash_mark.xml存在，启动XML旧launch_image引用数0，退出码0。仅语法与引用检查，不等同Android资源编译。
5. `git diff --check`：退出码0；Git提示个别文件后续可能转换CRLF，无空白错误。

## 未验证与限制

- 按既有授权未运行测试、构建、模拟器或设备，未提供伪造截图。没有自动测试通过或界面验收证据，任务2.1–2.3保持未勾选。
- 尚待：真实冷启动、原生Android12系统图标遮罩/不同版本、原生到Flutter构图过渡、减少动画、字体放大/横屏、小屏、系统栏恢复、账号恢复慢/失败及底层State不重建。可靠性和可用性仍属运行验收待办。
- 原生系统阶段是居中小矢量，Flutter阶段为右下大角色，同一颜色和风格但构图不同，不声称完全无缝。动画结束可能进入原会话恢复页，保持既有身份确认流程。
- 开屏按进程挂载播放一次，不为普通页面导航添加统一动画，不等待网络或承诺恢复完成。实际流畅度与绘制性能尚未测量。
- 新增矢量使用API24可用的尺寸控制，当前Flutter配置minSdk24（已读取本机FlutterExtension）；未执行Android编译验证。远程Issue未创建。
# 2026-10-23 延长停留修订

常规时长已从下文历史记录中的1280ms延长至2400ms，前约540ms入场、末约384ms淡出，减少动画仍180ms。设计文档已同步，受影响文件定向分析退出码0。未执行启动运行、测试或构建，实际视觉和持续时间仍待验收；证据见task-display-metadata/verification.md。
