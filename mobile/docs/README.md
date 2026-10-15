# Flutter 文档索引

## 当前设计基线

- [阶段0：需求范围](stage-0-requirements-scope.md)
- [阶段1：路由与流程](stage-1-route-and-flow-design.md)
- [团团记账气质 UI 设计基线](tuantuan-ui-design-system.md)
- [阶段3：页面布局与交互](stage-3-page-layout-and-interaction-design.md)
- [原始八屏设计稿](../prototypes/ui-direction/)
- [可运行页面原型](../prototypes/stage-3-pages/README.md)

## 实现进度与验收

- [HCJ 远程交付记录](hcj-delivery.md)：提交、Issue、草稿 PR 与遗留验收。
- [当前完成性审查](stage-3-completion-audit.md)：已实现、未验证与缺失项。
- [页面验收记录](stage-3-verification.md)：最新结果在前，历史批次在后。
- [实际 Flutter 截图](evidence/stage3-rebuild/)
- [安全本地状态验收](secure-local-state-verification.md)
- [Windows 启动修复验收](windows-startup-repair-verification.md)
- [重做复盘](stage-3-restart-retrospective.md)

## 接口与素材

- [接口及契约边界](API_CONTRACT.md)
- [原创人物与素材记录](sunny-companion-assets.md)
- [image-2.5 素材生成提示词](image-2.5-ui-asset-generation-prompts.md)

`screenshots/` 是早期截图，不能作为当前重建验收证据。阶段3 SVG/PNG 示意板是设计产物，不能替代实际 Flutter 截图。

## 文件维护约定

源代码放 `lib/`，测试放 `test/`，设计原型放 `prototypes/`，验收文档和截图放 `docs/`。后续命令日志统一输出到 `mobile/.diagnostics/`，如 `.diagnostics/analyze.log`、`.diagnostics/mock.log`、`.diagnostics/http.log`，该目录被Git忽略。只保留正在排查的失败日志和最新结果，排查后可清理；命令、明确退出码、环境、结果与限制必须写入验收文档。

历史阳光纸张/动漫橙视觉方案与命令过程日志、临时诊断输出已清理；当前视觉基线、页面布局、接口边界及验收结论保留在对应文档中。历史报告中的日志名称仅说明当时执行记录，不能作为可读取附件。

`.dart_tool/`、`build/`、`.flutter-plugins-dependencies` 是工具生成内容，`.idea/` 是本地IDE配置，保留。`.native-cache/` 保存已校验的SQLite原生库，用于解决下载超时，保留；Flutter clean后运行仓库`scripts/prepare-flutter-sqlite.ps1`预热钩子缓存。
