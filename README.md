# 企业协作智能面板

产品需求见 [方案.md](方案.md)，实施任务见 [tasks.md](openspec/changes/initial-product/tasks.md)。当前交付为规划和工具配置，尚无可运行应用。

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

initial-product 是待实施变更，规范尚未归档为已交付能力。
