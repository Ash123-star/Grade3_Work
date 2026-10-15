# 加密草稿与安全会话恢复验收（2026-10-13）

关联 OpenSpec `flutter-secure-local-state`、本地 Issue `docs/issues/flutter-secure-local-state.md` 与阶段3 task3.6。沿用阶段2阳光纸张/动漫橙和原阶段3连续日志布局，未改变五栏/默认导图、日历与日志日期独立、派发禁状态、下属日志入口及服务端权限规则。

## 已实现

- 原生客户端草稿通过 Drift/SQLite schema1 保存；表只含HMAC lookup与AES-256-GCM ciphertext/nonce/mac。查找键参与附加认证，账号/日期、字段、保存时间、确认的服务器草稿ID/version全部在密文内。随机nonce与派生查找子密钥由成熟cryptography实现；主密钥使用平台安全存储，不存普通偏好。
- 精确本人/业务日或日志/修订基线恢复，演示与不同API服务隔离。读取旧偏好后事务写入及解密回读成功才清理旧键；保存新输入也清理对应残留旧键。失败不删旧值、不清输入、不伪造已保存，不重置缺失密钥。上级不读取此存储。
- 编辑器600ms延迟保存、显式保存、返回保存、提交成功清理接入新store；异步恢复不覆盖之后输入，迟到保存不把新输入标为已保存。提交失败保留DiarySubmitFailure返回的真实草稿ID/version，离开后重进仍用该版本重试。
- 安全会话只保存token/account/expiresAt/服务地址，密码、角色、业务正文和DeepSeek密钥不写入。`main`先挂载SessionBootstrap，auth/me确认之前router和业务provider不挂载；待确认、强制改密继续原安全路由。超时保留凭证供显式重试；过期、身份变化、未知状态、401/403拒绝清理；旧账号迟到结果不替换新账号。
- 登录保存失败仍可当前会话使用并明确提示；退出先服务端logout，清理失败不假报完成；失效/改密清理恢复材料。条件清理和串行队列防止旧token清理新token。Android禁自动备份并排除设备迁移，secure_storage禁止错误时自动重置。
- 浏览器仅预览，不将WebStorage当作原生安全存储；启动跳过持久恢复，安全写入明确不支持，编辑器保留当前输入并提示使用Android。本文不宣称浏览器可离线持久保存。

## 验收证据

`test/secure_local_state_test.dart`新增15项，覆盖实际SQLite文件关闭/重开与密文检查、随机nonce、账号/日期/服务/修订版本隔离、密文交换拒绝、密钥丢失不清库、迁移/失败重试、最小凭证/损坏/过期、迟到清理、待确认/强制改密、401/身份变化与网络保留、实际编辑恢复/失权、启动阻断与清除、既有HTTP me待确认（仅auth/me与公开部门，无业务读取）、保存失败输入、迟到恢复、新状态渲染。

原`command_http_contract_test.dart`重试用例增加页面销毁/重新进入，验证加密保存的服务器草稿version9恢复后PUT仍为9，响应version10再提交。原日志交互用例改为验证真实加密store，不保留明文写入断言。测试注入安全存储替身及内存Driftexecutor；SQL与加密实现仍为生产类，不用测试假存储代替它们。

实际Flutter新增[启动恢复失败](evidence/stage3-rebuild/40-session-recovery.png)，360×800/字号1.5已检查：人物、说明、重试、清除及不删除草稿提示完整可达。原16屏及其余认证/附件/AI渲染随回归更新，累计40张单页证据；原日志编辑图06已重新对照原批准详情板，连续纸张/关联任务/分节/底部双按钮保持一致。

环境Windows、Flutter3.38.7/Dart3.10.7。直接使用Dart运行flutter_tools.snapshot以避免flutter.bat版本检查执行器不稳定：

```powershell
$env:FLUTTER_ROOT='D:\flutter'
$dart='D:\flutter\bin\cache\dart-sdk\bin\dart.exe'
$snapshot='D:\flutter\bin\cache\flutter_tools.snapshot'
& $dart $snapshot --no-version-check analyze --no-pub
& $dart $snapshot --no-version-check test --no-pub --dart-define=USE_MOCK=true --reporter expanded
& $dart $snapshot --no-version-check test --no-pub --dart-define=USE_MOCK=false --reporter expanded test/registration_contract_test.dart test/supporting_http_contract_test.dart test/command_http_contract_test.dart test/read_http_contract_test.dart test/auth_state_contract_test.dart test/management_analytics_http_test.dart test/attachment_assignment_http_test.dart test/ai_http_workflow_test.dart test/secure_local_state_test.dart
```

根目录另执行`openspec.cmd validate --all --strict`、`git diff --check`。结果更新至对应tasks后才勾选。测试编译由Flutter test执行；未构建APK。

最终结果：analyze无问题exit0；全量Mock124通过exit0；正式九文件96通过exit0；严格15通过exit0；diffcheckexit0（已有stage2文件CRLF提示，无空白错误）。本地忽略日志secure-final-analyze.log、secure-full-mock.log、secure-full-http.log；最新代码的15项本地状态双模式亦通过。已完成客户端tasks1–4.2；原生设备4.3/远程交付4.4保持未勾选。

验收修复记录：实际SQL异步与widget测试假时钟交接需要有界pump/runAsync，曾出现恢复未完成和卡住；已先查日志/活进程再停止该测试，不盲目重启。截图toImage必须放runAsync；待确认实际还读取公开部门名称，断言精确允许这两条auth路径、禁止业务路径。集中修正格式lint与这些失败后复验，无放宽正文/版本/密文/失权要求。

## 非功能、假设与未验证

- 隐私：密文数据库/账号隔离/附加认证/权限重验有自动证据；安全插件在单元测试中被注入替身，真实AndroidKeystore保护和卸载/锁屏/系统迁移未验证。
- 可靠性：保存失败保留、网络恢复阻断、相同服务器草稿版本重试、乱序会话清理有自动证据。数据库使用原生后台executor，测试用真实SQLite文件但不证明Android打包hooks有效。
- 这属于负载加密的Drift数据库，不是全文件SQLCipher加密。文件可见表名与记录数量；历史删除的明文偏好/设备旧备份无法证明安全擦除。
- 旧格式没有服务地址或Mock标识，精确迁移将历史本人草稿归属当前服务；切换服务前应完成迁移/确认，不声称能自动推断旧草稿原组织。
- 缺密钥不清库；没有自行恢复密钥的入口。数据库与安全密钥一起保留才可能恢复，新代码回滚成旧版会失去新稿读取能力。
- 后端注册/撤销/数据库/供应商、真机TalkBack、原生文件选择/保存、帮助反馈/退回/AI精细范围与原子版本契约仍未验收或未实现，见阶段3审查。
- HCJ混合用户/历史修改且gh不可用，不提交推送混合工作区，不伪造Issue/PR，不归档整个UI变更。
