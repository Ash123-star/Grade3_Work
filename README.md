# 企业协作智能面板

产品需求见 [方案.md](方案.md)，跨端实施任务见 [tasks.md](openspec/changes/initial-product/tasks.md)。Flutter 当前使用演示数据；Spring Boot 后端实现位于 `server/`，运行、接口与验收分别见 [后端说明](docs/backend.md)、[接口说明](docs/backend-api.md) 和 [验证记录](docs/backend-validation.md)。

后端覆盖认证、组织范围、独立审核、导图数据、日报、任务、附件、站内消息、统计导出及服务端 DeepSeek 建议。Android 联网接入、独立 Web 工作台和生产环境上线仍需实施，不能视为整个产品已交付。

OpenSpec 1.5.0 已通过官方命令初始化：
```powershell
openspec.cmd init --tools codex,claude,codebuddy --profile core
```

Codex 项目技能位于 .codex/skills，提示命令在用户级 ~/.codex/prompts；Claude Code 和 CodeBuddy 的技能与命令分别位于 .claude/ 和 .codebuddy/。三种工具共用同一规范，没有额外的自动角色分配配置。

重启工具后，Claude Code / CodeBuddy 可使用 /opsx:propose、/opsx:apply、/opsx:archive；Codex 可使用对应 openspec-propose、openspec-apply-change 技能或生成的 opsx 提示命令，具体以客户端命令列表为准。

```powershell
openspec.cmd list
openspec.cmd status --change initial-product
openspec.cmd validate --all --strict
```

initial-product 保留跨端里程碑待办。后端的具体交付以对应变更和验证记录为准，不将其他待办自动勾选。
