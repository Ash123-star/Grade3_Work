# 项目约定

- 产品基线为根目录方案.md；当前为规划阶段，不把待实施任务报告为已完成。
- Codex、Claude Code、CodeBuddy 共用 openspec/config.yaml 和变更目录，职责不固定；不默认启动多代理。
- 新能力先维护 changes/<change-id>/ 的 proposal、design、specs、tasks，完成校验后归档。
- App 导航从左到右：我的、AI地图、日志、视图、导图；默认导图。
- 派发页面无完成情况，下属日志入口在日志页。
- 素材直接查官网或 GitHub，不用百炼。产品 AI 通过服务端 DeepSeek 接入。
- 文档 UTF-8 中文，OpenSpec 标准标题及 SHALL/WHEN/THEN 关键词保留。
- Windows 验证命令：openspec.cmd validate --all --strict。
