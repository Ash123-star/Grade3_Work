# 合并验证记录（2026-10-29）

## 范围与合并指示

用户确认将HCJ当前全部业务代码、数据库、移动端、测试和文档改动纳入同一提交/PR。已告知Flutter全量测试仍有33项失败，以及仓库原定验收和非作者审阅要求；用户随后明确指示“立刻合并”。本次按该最新指示执行PR合并，不表示全量验收合格或失败项已修复。

## 已验证

- 后端本批 `ScenarioDataBootstrapTest,AsyncTimeoutErrorTest` 共4项通过，Maven package成功。此前认证/日志/组织/审核等定向组78项通过。
- Android真实接口debug包构建、安装、登录及五个页签启动成功；强制停止进程后恢复身份，无需输入密码。默认新会话168小时。
- 真实HTTP场景验收127项全部通过，覆盖组织范围、待确认/停用、任务审核和状态流转、幂等、版本、日志直接修改和历史、附件字节、统计导出及通知投递。
- 旧日志read/revisions/withdraw接口返回404，不恢复旧入口。
- Flyway独立种子历史表执行V1/V2；重启不重复插入，关闭种子开关后后端正常启动。正式结构仍V23。
- 本地PostgreSQL有21个虚构场景账号、34项任务、140篇日志、9种低饱和标签。实际开发库连接未提供，不能据此声称同步了其他数据库。
- SSE流实际55.72秒正常结束，重连成功，无JSON错误响应。
- OpenSpec严格校验通过。密码、token、实际环境配置、运行日志和APK位于Git忽略目录，不随本次提交上传。

## 未通过与限制

- 最终 `flutter test --no-pub --reporter expanded` 退出1：294项通过、3项跳过、33项失败。涉及AI工作台输入/重试、附件边界、月历和成员工作区、日志/审核交互、小屏和截图等用例。尚未逐条区分旧断言与真实缺陷，不能一概认定为过时用例。
- 后端全量未在最终代码上重新验证通过；此前全量失败记录不能被定向通过替代。
- DeepSeek/OCR外部供应商、真实性能和TalkBack尚未完整验收。不伪造AI成功数据。
- 非作者审阅尚未完成。本次合并采用用户了解失败结果后的明确即时合并指示；后续仍需补充审阅并修复失败项。

## 本机证据

Git忽略目录 `output/local-scenario-20261029/` 下：`backend-final-build.log`、`flutter-debug-build.log`、`final-http/http-results.json`、`prepush-flutter-full.log`、`native-session-result.json`、`mobile-calendar-muted.png`、`mobile-session-restored.png`、`sse-result.json`、`seed-repeat-result.json`、`backend-disabled.log`。这些是本机证据，不会自动出现在远程PR中。

种子启用与账号角色说明见 `docs/local-scenario-data.md`。后续优先处理33项失败、最终后端全量验收及非作者审阅。
