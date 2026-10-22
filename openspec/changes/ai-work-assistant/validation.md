# AI办事工作台实施与验收记录

主分支、混合改动和数据库历史协调的最新证据见 [协调验收](validation-reconciliation-2026-10-22.md)。该记录优先于下文旧迁移编号和混合工作区暂停；业务性能/真机/人测及完整 Web 交付限制继续保留。

当前 4.2、9.6、9.7 与 main 日志接口接入批次的详细证据见 [2026-10-22批次验收](validation-batch-2026-10-22.md)，其最终状态优先于下文历史快照；尚在运行的验收不提前计作通过。

日期：2026-10-21至2026-10-22（本地测试日志Asia/Shanghai，容器UTC）。变更：`ai-work-assistant`。用户已批准实施；当前为核心实现和本地验证阶段，正式自动写入关闭，尚未全量交付或归档。

## 2026-10-22 Web续办与真实双端补验

本节为最新批次，保持51/64。11.2/11.3是复合交付任务，以下子链路通过不等同完整双端正式写入、读屏或三条Web业务闭环全部交付。本批只改Web及对应规格/接口/追踪文档，后端、Flyway和APK沿用上一批已验版本；未新增依赖、权限或写入开关。

- 新增`web/src/workContract.ts`：对v1、事项id/整数版本/已知状态、消息/计划/步骤/回执、能力限值、删除受理身份及附件进行边界校验并冻结业务响应。未知状态或损坏回执不显示成功，不清输入、不把失败显示为空历史。普通网络异常只显示恢复文案，不输出浏览器原始异常/供应商正文。
- Web沿用服务端nextCursor读更多历史；刷新重读已展开页，同id保留较新版本，失败或游标不推进保留旧列表。消息/确认/取消/续办互斥，409立即GET当前事项并保留合法文字与材料；相同未确认请求重发保留键，版本/事项/对象改变后换键。能力失败暂停发送；即使401/403/404正文不是JSON也清私人内容。删除须匹配id与CANCELLED受理回执后离开。
- 键盘焦点：确认按钮禁用/移除后聚焦当前状态标题；异步刷新不抢输入焦点。新建/清除后可继续输入，事项列表有已选择语义，分页有真实加载状态。未添加开发说明文案或新的视觉体系。

| 验证 | 命令、结果与证据 |
| --- | --- |
| Web类型与构建 | `npm.cmd run build`，vue-tsc和Vite退出0；`output/ai-work-web-continuation-build-final.log/.exit` |
| Web全量浏览器 | `npm.cmd run test:e2e`，Chrome桌面1280×900及移动390×844，32通过/2项旧分析真实登录跳过，退出0；`output/ai-work-web-continuation-tests-final.log/.exit`。覆盖13类损坏事项/契约、分页失败/游标、消息409→GET→版本变化→503重发、删除回执错误、能力失败、非JSON失权、两个浏览器并发确认、键盘焦点及既有SSE/账号切换/长内容回归 |
| 真实Web→Android→Web | `node output/ai-work-runtime/continuation-live-browser.cjs`，退出0；`output/ai-work-runtime/continuation-live-verified.log/.exit`、`continuation-live.json`。已有Docker API/PG/Redis、已配置DeepSeek、真实Chrome与App_Run_API37模拟器，同一合成示例账号：Web创建只读资料事项→Android打开同一事项并追加消息→Web收到更新→重载仍恢复2条消息→Web删除202→Android失权清空正文和输入。事项版本3→6、0正式回执、写入false；测试事项随后删除，未改用户正式任务/日志 |
| 实际界面/语义 | 已查看`continuation-web-after-app.png`和`continuation-app-deleted.png`；前者为真实更新过程截图，不冒称全部处理完成。浏览器无障碍树存在未忽略status节点、输入Tab到文件控件；`continuation-web-semantics.txt`。Android回AI地图后仅原有历史记录，删除事项未留在列表；`continuation-final-ui.xml`。无障碍树不等同NVDA/Narrator/TalkBack完整读屏验收 |
| 规范与卫生 | `openspec.cmd validate --all --strict`，29/29、退出0；`output/ai-work-web-continuation-openspec-final.log/.exit`。`git diff --check`退出0；`output/ai-work-web-continuation-diff.log/.exit`。20个本批相关文本UTF-8有效、无Key模式或行末空白，`output/ai-work-web-continuation-hygiene.json`。apply复核仍51/64，`output/ai-work-web-continuation-apply.json` |

首轮浏览器22通过/10失败/2跳过，日志`output/ai-work-web-continuation-tests.log/.exit`保留：新增夹具漏配旧分析响应造成页面额外异常，补齐正常旧接口夹具；同时发现真实键盘确认按钮禁用后焦点丢失，修复生产焦点交接后全量32通过。未删失败断言或放宽契约校验。

真实跨端脚本的失败记录也保留：首轮模拟器进程自行退出，adb无设备，重新启动App_Run_API37后恢复；第二轮将删除202误断言200；第三轮在DOM更新过程读取简化ARIA快照，改用等待状态节点及Chrome完整无障碍树确认。最终`continuation-live-verified.exit=0`，这些脚本修正不改变生产接口或业务状态。

本批非功能证据为安全与可靠性，并补键盘可用性：损坏/晚到响应不消费为成功，非法身份不依赖JSON错误正文清理，冲突与故障不丢合法输入；真实双端续办/删除可恢复。尚缺完整屏幕阅读器、Android/Web并发正式写入/撤权组合、Web三条完整业务链路、9.6完整20次故障矩阵、60份真实代表集、真机性能/5位首次使用者和正式Issue/PR。混合改动和远程未认证限制保留，未提交/推送，未归档。

## 2026-10-22 最新边界与运行环境验收

本节优先于下文历史记录。当前51/64，5.2、6.5、9.3、9.4、9.5均已有对应实现与真实数据库验收；其余复合验收不因子场景通过而勾选。

- 人员范围快照不再截断前100人，同名、负责人/期限缺失一次汇总；多任务分别绑定本次原句、用户选择优先，模型taskId不能改换目标。单计划最多10动作/5新任务，超限保留请求并询问本批，避免静默丢项；修复“分别”误识别为禁止及“晚上8点5分”丢分钟。
- 同级冲突比较同范围全部有效资料，包含不同标题重叠约束、同字段不同清单ID及新发布冲突使旧确认失效。此证据不代表任意自然语言矛盾都有完备识别，4.2仍保留整体待验收。
- 取消/删除与提交用真实PG advisory lock确定先后：已提交任务保留，后续步骤停止；原键20次重放无新增正式记录。首次删除后仍可取原幂等受理回执，异内容409；取消/删除/派发撤权/停用/入口关闭先发生时不写业务。
- Web长结果曾被sticky输入区遮挡，改为随正文布局；新增390px/桌面长结果非覆盖、焦点与减少动画验证。Android五栏上方输入区沿用现有布局。

| 验证 | 明确结果与证据 |
| --- | --- |
| 边界后端全量 | 标准脚本最终211项通过、退出0，含51项WorkIntegrationTest；`output/ai-work-boundaries-backend-final.log/.exit`。首轮失败揭示“分别”误判，修复后重跑，失败日志保留 |
| 人员/规则最后补丁 | 隔离本机PG/Redis定向71项通过、退出0，含52项WorkIntegrationTest；`output/ai-work-boundaries-targeted-final.log/.exit`。与211项不相加为独立总数 |
| Web边界批次 | 构建及浏览器均退出0，18通过/2旧分析真实登录跳过；`output/ai-work-boundaries-web-{build,tests}.log/.exit` |
| 真实浏览器链路 | Chrome示例管理员登录→真实已配置DeepSeek只读查询→GET/刷新恢复，桌面/390px均无横向溢出，0正式动作回执，测试私人事项随后删除；`output/ai-work-runtime/boundaries-live-browser-final.log/.exit`、`boundaries-live-browser.json`、`boundaries-live-{desktop,mobile}.png` |
| 锁定OCR运行 | `python scripts/verify-ai-ocr.py`退出0，中文合成样例全文匹配、unverifiable=false、8.527秒；`output/ai-work-runtime/boundaries-ocr.log/.exit`。仍高于5秒目标，不能替代60份代表集 |
| Android实际运行 | 已adb覆盖安装并启动真实API APK，示例管理员登录，第四栏AI地图选中，已人工查看截图；`output/ai-work-runtime/boundaries-app.json/.png/.xml`、`boundaries-apk-install.exit`。APK SHA256 `efe36c89d1c35707a9fefdddb9cd8debcdc86a2cb83d8a74d5d4dba65dba70be`；本批未改Flutter，273通过/1跳过为前批证据 |
| 规范与差异 | 严格OpenSpec29/29、退出0及diff check退出0；`output/ai-work-boundaries-openspec-final.log/.exit`、`output/ai-work-boundaries-apply.json` |

Docker已恢复，用户数据库/卷保留；`pandora-stage-data-1`健康，API `workpanel-ai-api-main`在127.0.0.1:8080运行，锁定OCR `workpanel-ai-ocr`只读且限制2GB/2CPU/128进程、位于隔离网络。API直接使用数据容器内5432/6379/7687，修复旧宿主Redis映射拒连；保留旧API/OCR停止容器用于追溯。当前边界JAR SHA256 `73e4785c8f349cf431bf413c43f7a5364bc9c1862081139a33f1b4239c343aae`，后续结果核对代码尚待最终部署证据。历史“Docker不可用/adb无设备”不再代表现状。

结果核对批次实现同事务回执指纹校验、UNKNOWN/过期RUNNING恢复、无回执证明后重排、核对不一致停写、补充指令暂停与取消/删除fencing；新增独立复核缺失、最终资料版本冲突、过期资料、材料修正复检与损坏/低置信拒绝场景。首轮标准验收未通过：结果核对夹具缺少不可变计划，清理404使写入测试开关未恢复，引发后续6项派生失败；修复为完整计划且finally必恢复开关，没有放宽生产验证。日志保留`output/ai-work-outcomes-backend.log/.exit`。本批最终后端/Flutter/Web/运行镜像结果在下方补记。

远程认证复核：`C:/Program Files/GitHub CLI/gh.exe auth status`本次明确显示未登录；当前工作区仍包含前批次布局、团团迁移和锁文件混合改动。按仓库要求未自动提交/推送或创建PR，不虚构Issue。真实代表样本、完整负向/故障/跨端矩阵、TalkBack/真机profile、5人体验和正式配置服务器性能仍未全部验收，自动写入保持false，不归档。

### 结果核对与三条链路最终补记

- 标准后端统一验收：`powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-backend.ps1`，219项全过（含59项WorkIntegrationTest）、退出0；`output/ai-work-outcomes-backend-final.log/.exit`。UNKNOWN和过期已提交步骤20次回放只恢复回执，无新增任务；无回执且事务锁释放后重排，指纹不一致停写；核对中的补充指令409，取消/删除分别20次重放、fence推进一次、正式任务保留；无回执耗尽FAILED，有已有回执PARTIAL，其他失败不遮盖UNKNOWN。
- 新增独立复核人缺失仍待审、重新路由后最终资料版本冲突拒绝且审核决定回滚、更新候选重新发布；过期正式资料不进入模型，缺依据不编规定。合并既有未发布/冲突/撤权/自审/模板/流程创建测试，覆盖9.3。
- 真实DOCX金额错误→NEEDS_FIX→补充文件不能复用旧报告→新报告PASS→FEEDBACK→派发人人工ACCEPTED；损坏DOCX检查FAILED、低置信PNG UNVERIFIABLE，无交付副作用。合并既有无清单/仅检查/未接收/非参与者/回执故障事务回滚测试，覆盖9.4。OCR低置信为受控供应商，真实OCR效果仍按9.7验收。
- 最后补丁保护未接入申请文案，拒绝模型虚构的报销编号/提交/任务替代动作，有动作计划只说明要求已整理；在本机PG18.4/Redis5隔离58432/58479定向跑`mvn.cmd -B -f server/pom.xml -Dtest=WorkIntegrationTest,WorkDomainTest,WorkSearchPolicyTest test`，79项全过、含60项集成、退出0；`output/ai-work-outcomes-focused-final.log/.exit`。与219项不相加，隔离实例已停止。
- Flutter本批全量273通过/1跳过，analyze无问题、APK构建退出0；`output/ai-work-outcomes-flutter-{analyze,tests}.log/.exit`、`output/ai-work-outcomes-apk.log/.exit`。Web本批构建退出0、18通过/2旧分析真实登录跳过，`output/ai-work-outcomes-web-{build,tests}.log/.exit`。后续实际截图发现“检查已完成但材料需补充”仍标已办妥，已改两端按报告结果显示需要补充/需核对/重新检查/材料已核对，任务创建与反馈提交单独表达，最后定向结果在下方补记。
- 最新服务JAR已打包，`output/ai-work-outcomes-package.log/.exit`退出0；小运行镜像构建`output/ai-work-runtime/outcomes-image.log/.exit`退出0，API重新启动健康UP，原数据库/卷保留、正式写入false；`output/ai-work-runtime/outcomes-restart.log/.exit`和`recovery-health.json`。未新增数据库迁移。
- 最新APK已覆盖安装，模拟器回到AI地图；第一次UI定位误选同名标题而非第四导航导致断言失败，修正为可点击导航语义、截图已人工审阅。`output/ai-work-runtime/outcomes-app-check-final.log/.exit`退出0。最终结果文案补丁后的APK/截图另行补记，不把早期截图当成补丁生效。

最终文案补丁补验：Flutter analyze退出0；三个AI模型/repository/工作台/恢复测试文件共28项通过，`output/ai-work-outcomes-ui-{analyze,tests}.log/.exit`，与273项全量不相加。APK重新构建退出0，SHA256 `f4a55454dd1f27455adc1133aed7f7aadf4c5f9883871c50590f1428c50a1180`，已adb安装并再次查看AI地图，原“已办妥”在NEEDS_FIX报告上改为“需要补充材料”；`output/ai-work-runtime/outcomes-final-{apk-install,app-check}.log/.exit`、`outcomes-app.json/.png`。Web重新构建退出0，20项通过/2旧分析真实登录跳过，含材料不足状态回归；`output/ai-work-outcomes-ui-web-{build,tests}.log/.exit`。界面状态变更未改变服务端状态或数据库历史。

最终部署JAR SHA256 `09ee9c1aeff5f42244d206b14616f6bc165f710abf8c1a3d4d6f9da6a65f8a50`，运行镜像 `sha256:928e5038c83e3b545c3abd4bb5dbde4944ae191c527f6b7543d1b7f11d220bd0`。新服务上真实Chrome登录/DeepSeek只读问答/GET与重载恢复再次退出0，桌面与390px均0横向溢出，WAITING_INPUT/0回执/测试私人事项删除；`output/ai-work-runtime/outcomes-live-browser.log/.exit`、`outcomes-live-browser.json`及双宽截图。严格OpenSpec29/29、diff check退出0，日志`output/ai-work-outcomes-openspec-final.log/.exit`、`output/ai-work-outcomes-diff-check.log/.exit`；Windows LF/CRLF提示不是差异错误。

权限负向矩阵补验：真实本机PG18/Redis5与HTTP执行两项新增集成测试，退出0；`output/ai-work-privacy-focused.log/.exit`。覆盖本人私人截图/事项/检查报告/解析缓存与同公司组长/管理员/外组负责人/其他公司管理员；逐项请求历史/详情/补充/取消/SSE/下载/二次接入，均拒绝且缓存无跨用户副本，管理员不因组织读取权获得私人事项。待确认403、停用401涵盖能力/事项/资料/下载/候选/AI接收；私人制度草稿与其他部门资料搜索计数0、详情404，模型不含这两者/私人备注/未提交日志/原手机号，CapturedOutput普通日志无这些敏感标记。与既有会话/失权SSE及私有材料用途测试共同覆盖9.5。本批只新增测试，无生产代码变化，运行JAR仍为上述已验哈希。

最终卫生检查139个变更文本文件UTF-8有效、API Key模式无命中，结果`output/ai-work-outcomes-hygiene.json`；首轮脚本沿用Windows GBK解码Git中文路径失败，改用Git NUL分隔UTF-8路径后得到明确结果，未改动文件编码或绕过检查。测试生成的单个Python字节码已移除，隔离PG/Redis已停止，保留运行API/OCR/用户数据/模拟器。未完成13项仍见tasks，不提前归档或对真实代表集/人测作完成声明。

## 实现与环境

- Windows PowerShell、JDK21、Maven、Flutter/Dart、Docker Desktop。后端使用真实隔离PostgreSQL16/Redis数据容器及受控模型/OCR测试；真实供应商样本单独记录。
- 新增aiwork/procedure模块、应用适配、附件用途鉴权、V14/V15迁移、交付清单/异步检查、独立资料复核；DeepSeek只由服务端原预算/限流通道调用。
- Flutter统一办事入口、材料上传/补信息/具体确认/回执、交付检查/反馈、授权和制度维护；Web办事台实现同契约。沿用团团纸卡/导航/本地素材，未引入新素材许可。
- 工作分支 `codex/ai-work-assistant`。46/64项有对应实现及运行证据，复合任务缺口不勾选。当前工作区包含前批次混合差异，未自动提交/推送。

## 2026-10-21 集中收尾验收

本节优先于后文历史批次。代码补齐模板真实文件预填下载、维护稿搜索分页/待审入口、依赖与批量部分失败续办、过时确认重新核对、逐动作授权复用、正式资料发布与消费的锁、前后台动效/焦点与大字体状态卡。未改变V14–V16迁移。

- 模板DOCX跨run/表格/页眉页脚替换服务端白名单字段；XLSX只替换字符串，公式和未知占位保留，事由不递归执行占位。真实HTTP及子进程验证下载、撤回、版本/附件/伪造身份拒绝。维护页已验证管理员待审入口、禁重复发布、员工隐藏维护、错误恢复和换账号清私有资料。
- 批量第一步成功、第二步注入回执故障时返回部分成功；同键20次续办只补未成功动作。未完成依赖未勾选则确认整体回滚，token仍可用；无关人员变化、已完成目标变化不阻塞其他待办，当前目标变化拒绝。过期计划可重新核对，成功回执保留，失效动作重新确认。
- 本次再发现并修补已有任务目标边界：用户选择优先；本次文字完整标题/ID只有唯一可读命中时才自动匹配，模型不能改换目标；多项/无目标追问，转派同名须选择。该最后补丁的最终定向验收结果另行补记，不能沿用之前全量结果。
- OCR完整锁定依赖镜像重建退出0并执行pip check；镜像`530b71ce21d8b0e984bf430d05870520674e694090ed1b7232478bafcc982773`。只读、2GB/2CPU/128进程、内部网络运行中文合成截图，全文匹配、unverifiable=false，外连返回101；耗时11.937秒，未达到性能目标，不以此替代60份代表集。证据`output/ai-work-completion-ocr-{build.log,locked-smoke.json}`。
- seccomp/资源探针构建退出0，镜像`d1383386be1bd859900f4e972275ca66d90d1df350afaa3a1c1b8b3796bb5265`。禁止socket等系统调用，限制CPU/地址空间/文件/FD/core；正式运行JAR在该沙箱内的复验另记。
- 清理作业新增90天未用于正式交付的私人检查报告清理，365天AI动作/授权审计详情清理，保留最小追溯元数据、幂等回执及正式文件。授权创建/撤回与审计同事务，同键20次不重复。真实PG保留策略用例通过。
- 新增删除标记导出/重放CLI，导出合并旧标记并原子保存，拒绝运行中的API；真实pg_dump/pg_restore演练2次重放，私人消息/文件清理、待办停止、正式文件/任务保留，标记合并通过。备份1761092字节，结果`output/ai-work-restore-acceptance/result.json`。部署仍须持续导出并独立保存最新标记，停止所有副本；本地演练不等于生产恢复已验证。

| 集中验证 | 明确结果 |
| --- | --- |
| 后端标准脚本 | `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-backend.ps1 -KeepContainers`，202项全过（44项WorkIntegrationTest），退出0；`output/ai-work-completion-acceptance-backend.log`。上述最后目标匹配补丁晚于这次编译，须看最终定向补记 |
| Flutter | `flutter analyze --no-pub`退出0；`flutter test --no-pub --dart-define=USE_MOCK=true --reporter expanded`退出0，273通过/1跳过；`output/ai-work-completion-acceptance-flutter-{analyze,test}-final.log` |
| APK | `flutter build apk --debug --no-pub --target-platform android-x64 --dart-define=USE_MOCK=false --dart-define=API_BASE_URL=http://10.0.2.2:8080/api`，退出0；`output/ai-work-completion-acceptance-apk-final.log` |
| Web | `npm run build`与`npm run test:e2e`均退出0，16通过/2真实登录跳过；`output/ai-work-completion-web-{build,tests}.log`；未把受控浏览器用例报告为完整双端真机验收 |
| 界面 | 实际审阅360dp/1.5倍字体首页、确认与回执，修正选择任务按钮断行，最终三种宽度控件测试全过；`output/ai-work-acceptance-temp/pandora-ui-evidence/ai-workbench/` |

失败与环境修复保留：首轮新增过期计划夹具尝试修改不可变计划被数据库拒绝，改为INSERT时构造过期计划；未放宽不可变触发器。Flutter首轮C盘临时目录满导致编译拷贝失败，停止该轮并把TEMP/TMP切到D盘后全量通过。最后后端全量重跑时C盘耗尽导致Docker文件系统只读、PG/Redis断连，该轮被中止、不计通过；本次生成的编译缓存已移至D盘，Docker恢复与最后补丁验收另行记录。未删除用户数据库/附件。

仍未满足发布条件：9.7真实代表集未达标、复杂自然语言隐含制度矛盾、完整负向/故障/跨端矩阵、真机TalkBack/profile、5人易用性、正式服务器20并发性能及远程Issue/PR。正式自动写入保持false。未安装在新设备上不声称已打开App；当前adb无连接设备。

2026-10-22最终补记：Docker中断后未再冒充标准脚本通过。以本机已安装PostgreSQL18.4/pgvector和Redis5.0.14.1启动隔离58432/58479实例，目录`output/ai-work-native-acceptance`；`mvn.cmd -B -f server/pom.xml -Dtest=WorkIntegrationTest,WorkDomainTest,WorkSearchPolicyTest,DocumentParserTest,TemplateRendererTest test`最终退出0，73项全过，含45项真实HTTP/PG/Redis/持久队列集成测试，覆盖最后的任务名/选择器目标防篡改、无目标与同名追问。日志`output/ai-work-completion-native-focused-final.log`。首轮未等待测试库创建导致数据库不存在，修正环境后重跑；未删或放宽测试。`mvn.cmd -B -f server/pom.xml -DskipTests package`退出0只是最终打包证据，不单独代表业务验收。此前202项标准全量和本次73项受影响验证共同记录，不相加为275项独立测试。

Docker恢复限制：宿主C盘释放空间后，Docker Desktop仍因`dockerInference` IPC socket错误1920/地址占用无法启动；已保留原运行目录，数据磁盘/业务卷未删除。恢复尝试含停止Docker Desktop、终止docker-desktop WSL、重新启动和隔离临时IPC目录，最后恢复原run目录；仍不能更新运行中的API/OCR镜像，也未把新APK安装到无连接设备。旧API本轮开始即Exited。部署者需修复Docker启动环境后再进行新JAR的Linux运行镜像验收和服务启动；当前不能报告后端已重新运行。

Linux解析最终补验：在独立WSL Ubuntu安装GCC/OpenJDK21.0.12.1，用仓库sandbox.c和sandbox-test.c编译探针，退出0；以相同256MB堆/128MB metaspace/1CPU参数、空凭据环境运行最终打包JAR，真实DOCX提取、白名单预填、未知审核字段保留、损坏PDF拒绝均通过。证据`output/ai-work-linux-acceptance/{result,process-exits}.json`和`output/ai-work-completion-linux-sandbox.log`；JAR SHA256=`d47d26c4c90839d7e19cc0036621d16451151385af9f47504380a85b7d399194`。这是Linux子进程验收，不替代尚未恢复的Docker API服务验收。早期探针脚本把不支持签名误断言为损坏、中文检查经PowerShell管道编码失真，已改用损坏PDF和ASCII字符码验证，未修改生产错误码或模板实现。

动效最后补丁把11处AI弹层接入集中overlay/press参数，减少动画/离屏用noAnimation。最终`flutter analyze --no-pub`、全量`flutter test --no-pub --dart-define=USE_MOCK=true --reporter expanded`与同参数APK构建均退出0，273通过/1跳过；日志`output/ai-work-completion-motion-{analyze,test,apk}.log`。严格OpenSpec最终29/29、退出0。134个变更文本文件UTF-8/敏感值检查无命中，`git diff --check`退出0；前序混合改动保留，不提交/推送。

## 最新续做：Flutter正式契约与续办恢复（8.2）

本批完成8.2，当前38/64。下文37/64及以前的测试计数为保留的历史快照。

- 能力、分页和事项响应在repository边界严格解析；验证contractVersion、身份/整数版本、已知状态及消息/步骤/回执集合，保存不可变数据。损坏或不兼容响应是可恢复错误，不转换为空列表或“已办妥”；READY、RECONCILING、CANCEL_REQUESTED分别显示准备办理、核对结果、正在停止。列表使用服务端nextCursor，同id保留较新版本。
- 正式repository随账号/权限失效，晚到HTTP响应不能进入新账号，旧repository不能继续写入。详情与选择弹层使用请求代次，命令401/403/404立即清理正文/输入，409重新GET并保留合法输入；替换路由事项时清除旧选择。
- 消息提交与确认/取消/续办互斥；相同未确认请求重发保留键，动作、版本、人员/任务等请求上下文改变时换键。取消、重试及重新打开都从服务端恢复，已创建任务回执保留；删除只接受匹配id与CANCELLED回执。能力刷新失败保留输入与已选材料并暂停发送，恢复后继续，不虚构接口成功。
- 新增真实本地HTTP协议测试，覆盖完整收件/补充/GET恢复/确认/重试/取消/删除，以及13类损坏响应、401/403/404/409/429/503、账号变化后晚到结果/继续写入拒绝。控件测试覆盖重开后的问题/消息/回执、补充中的互斥、冲突换版本与保留输入、超时重发、立即失权清理、能力故障恢复；原SSE乱序/重连/同版本脱敏/账号守卫回归保留。
- 本批非功能证据为安全与可靠性：HTTP错误不泄漏供应商原文，旧账号请求受隔离；响应不可变、故障不消费为成功、版本冲突/请求键/已有回执恢复有运行证据。受控HTTP与控件夹具不冒充真实模型效果或完整Android/Web业务验收。

| 验证 | 命令、结果与证据 |
| --- | --- |
| Flutter分析 | `flutter analyze --no-pub`，最终退出0、No issues；`output/ai-work-contract-flutter-analyze.log` |
| Flutter全量 | `flutter test --no-pub --dart-define=USE_MOCK=true --reporter expanded`，退出0、269通过/1跳过；`output/ai-work-contract-flutter-test.log` |
| 定向恢复与夹具回归 | 三个AI工作台测试文件首轮21项通过；更新旧界面完整v1夹具后的定向21项通过；`output/ai-work-contract-focused.log`、`output/ai-work-contract-fixture-check.log` |
| Android构建 | `flutter build apk --debug --target-platform android-x64 --dart-define=USE_MOCK=false --dart-define=API_BASE_URL=http://10.0.2.2:8080/api`，退出0；`output/ai-work-contract-apk.log` |
| 后端/Web | 本批未改服务端/Web或数据库，未重复全量；沿用上一批186项后端及Web16通过/2真实登录跳过的证据，不能计为本批新跑的双端验收 |
| 规范/差异 | 最终严格校验、apply进度和卫生检查见`output/ai-work-contract-{openspec,apply,hygiene,diff-check}.log/json` |

首轮分析发现DTO迁移遗漏附件能力读取及风格问题；已定向终止该轮编译失败的测试进程，不计通过，日志保留`*-first.log`。修复后全量发现旧界面6项及demo导航1项使用不完整夹具，更新为真实v1结构，未放宽运行时校验；失败日志保留`ai-work-contract-flutter-test-fixture.log`。最终全量269项通过；新增能力恢复测试的一处括号风格修正后分析无问题，保留`ai-work-contract-flutter-analyze-style.log`。

APK已adb覆盖安装并保留会话，实际核对AI地图第四栏selected=true并人工查看截图；APK SHA256为`f6b031d9f171e874ff1e4e78a6d6be30f4462b85ff00803dc0a530b8a63f6c32`。本地后端健康为UP、V16及正式写入关闭状态保持。运行与截图记录见`output/ai-work-runtime/install-contract.log`、`contract-app.json`、`ai-workbench-contract-emulator.png`；页面运行不替代完整业务/性能验收。首次启动抓取XML过早失败，待首页稳定后再次定位底栏并确认切页，未把首页截图冒充AI地图。完整跨端/读屏、解析OS沙箱、代表样本/真机性能、人测与备份演练等仍按原任务跟踪。gh认证检查退出1（未登录），混合工作区未提交、推送或创建PR。

## 最新续做：事件恢复与权限失效

完成6.6，当前37/64，未归档。下文36/64及181项是前一批快照。

- GET正文/事件游标使用只读可重复读快照，防止读取正文后游标越过并发提交。流连接即发心跳、按持久序号重放，只发送版本。非法/负数/溢出/超前游标400；当前事项私有，管理员无权穿透。来源/目标视图失效即使事项版本未变，也发不推进序号的refresh；会话、成员或事项失权发无正文access-lost并结束。
- Web新增带Bearer头的fetch流、递增游标、断流重连、前台GET和低频兜底；不把token放URL。GET拒绝旧版本覆盖，同版本允许受权视图替换。账号/页面切换与失权清除私人输入、文件、选项、授权和正文，废弃旧请求。Android增加事件去重、失权/账号切换的请求隔离、待刷新合并、旧版本拒绝；成员状态变化而token不变时，选择器、设置、资料/交付入口也不展示受保护缓存。
- 状态事务集中写AI_WORK_UPDATED，进入需补充、需确认、失败/部分成功或办妥时通知；处理中、同状态刷新和等待复核不逐步通知。稳定事项版本键与既有通知id防重复，删除不删除正式业务。
- 真实PG/Redis/HTTP新增5项集成测试：持久序号重放/断线恢复/非法游标/私有隔离；成员、会话、删除三类在流失权；同版本来源撤回；60次并发状态更新与24次GET快照一致；状态/outbox回滚及20次重复投递仅各产生一条通知。WorkIntegrationTest现33项，后端全量186项，0失败/错误/跳过。
- 两端新增测试覆盖重复/乱序、较旧GET拒绝、同版本脱敏替换、断流后携带游标、延迟命令遇撤权、相同token账号切换、成员限制后的选择器隐藏及旧账号请求返回；Web解析覆盖跨块UTF-8/CRLF/多行data与超过JS安全整数的游标。
- 本批非功能证据为安全（失权停流、无正文、账号缓存隔离）和可靠性（重放无副作用、快照一致、通知去重/事务回滚）。浏览器交互使用受控HTTP/流夹具，不能替代真实Android/Web同账号双端和读屏验收；8.2、9.5–9.6、11.2–11.3复合任务保留待办。

| 验证 | 命令、退出码与证据 |
| --- | --- |
| 后端 | `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-backend.ps1`，退出0，186项全过；`output/ai-work-recovery-backend.log` |
| Flutter | `flutter analyze --no-pub`，退出0、No issues；`flutter test --no-pub --dart-define=USE_MOCK=true --reporter expanded`，退出0，256通过/1跳过；`output/ai-work-recovery-flutter-{analyze,test}.log` |
| Android | `flutter build apk --debug --target-platform android-x64 --dart-define=USE_MOCK=false --dart-define=API_BASE_URL=http://10.0.2.2:8080/api`，退出0；`output/ai-work-recovery-apk.log` |
| Web | `npm run build`类型检查/构建退出0；`npm --prefix web run test:e2e`退出0，16通过/2真实登录跳过；`output/ai-work-recovery-web-build.log`、`output/ai-work-recovery-web-test-final.log` |
| 界面证据 | 已人工查看Web窄屏失权清理、桌面回执和模拟器AI地图；留存在`output/ai-work-runtime/web-recovery-{access-mobile,result-desktop}.png`及`ai-workbench-recovery-emulator.png` |
| 规格与差异 | `openspec.cmd validate --all --strict`，退出0、29/29；apply确认37/64，剩余27项；`output/ai-work-recovery-openspec-final.log`、`output/ai-work-recovery-apply.json`。`git diff --check`及UTF-8/真实凭据扫描通过 |

最终APK已通过adb install -r（退出0/Success），保留登录与数据，已重新启动并实际确认AI地图第四栏selected=true；仅点击而未切页的首次截图已重新捕获核对。APK SHA256为`131e51c47f7f265d5fda18af0b217db80cf20c7d7b0a2d90f1c7d738c363ac02`，已验收JAR SHA256为`26f836a43ec5263997f1e15fc8d809b2402d38f00124ac39626e19a2fa950881`。安装与运行记录见`output/ai-work-runtime/install-recovery.log`、`recovery-app.json`，空事项列表使用真实API，未把模拟器页面运行称为完整真实双端业务通过。

首轮Flutter分析5条风格问题；首轮测试的AsyncError保留旧value导致测试重复计数，单订阅夹具收尾卡住后已定向终止测试进程，不能计为通过。修复事件监听顺序、夹具收尾和风格后，定向3项及最终全量256项通过，保留`output/ai-work-recovery-flutter-*-first.log`。首轮Web发现上传文案被通用错误覆盖与夹具缺分析响应，修复为错误码白名单；第二轮2项上传夹具缺错误码，与真实API契约不符，修正后最终16项全过；第二轮日志为`output/ai-work-recovery-web-test-fixture.log`。

本批不新增迁移，V14–V16不修改。本地后端已更新为镜像`debb2423bac6`并恢复8080服务，health=UP，保留原数据库/会话，正式自动写入仍为false；`output/ai-work-runtime/recovery-health.json`。OS解析沙箱、真实供应商/代表样本、真机性能、完整跨端/读屏、人测和备份恢复等限制仍按原待办追踪。混合工作区及gh未登录仍阻止独立提交/推送/PR，未声称远程已更新。

## 最新续做：文件契约与检查后提交

本节为本批最新验收，优先于后文保留的历史结果。完成3.2和7.5，apply确认36/64，剩余28项，尚未归档。

- AiFilePolicy统一能力接口、AI用途上传、事项/交付接入及隔离解析的限制。PNG/JPEG/PDF签名和扩展名共同验证，OOXML继续核实内部类型；普通附件上传兼容。两端读取相同格式/字节限值，手机端按白名单错误码显示可操作中文，不暴露解析异常。
- 真实文件测试覆盖50/51页PDF、50000/50001格Excel、20MP边界、100MB展开体积/20000条目超限、宏/嵌入对象/外部关系/路径穿越拒绝，以及真实DOCX/公式XLSX和隔离子进程错误分类。真实PG/HTTP覆盖能力契约、AI上传伪装格式、普通上传兼容、单文件/消息数量/总大小限制。
- AI链路覆盖明确检查后提交、限定任务授权、非匹配/已撤回授权待确认、纯检查覆盖模型提交建议及匹配授权、当前“先不要提交”阻止模型候选、检查不通过/旧无清单不自动提交、主动人工核对保留非通过报告并拒绝硬性缺项。未接收不隐含接收，可读派发人无反馈权限；未自动验收/归档。
- 写入开关关闭仍可生成私人检查报告，提交继续排队。注入动作回执失败时，FEEDBACK、交付、附件用途、审计/outbox同事务回滚，重试只提交一次。提交额外重验解析器版本。解析版本v3使旧缓存/报告失效，须复检，本批不新增数据库迁移。
- 本批非功能证据为安全与可靠性：真实格式/压缩/外链攻击拒绝、当前禁止指令与授权范围校验；持久检查、停写可检查及提交故障回滚/重试。尚不能替代完整OS沙箱、性能、真实供应商、设备与人测验收。

| 本批验证 | 命令、明确结果与证据 |
| --- | --- |
| 后端 | `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-backend.ps1`，最终退出0，181项无失败/错误/跳过，含28项WorkIntegrationTest、8项真实文件测试；`output/ai-work-delivery-backend-final.log` |
| Flutter分析 | `flutter analyze --no-pub`，退出0，No issues；`output/ai-work-delivery-flutter-analyze-final.log` |
| Flutter全量 | `flutter test --no-pub --dart-define=USE_MOCK=true --reporter expanded`，退出0，251通过/1跳过；`output/ai-work-delivery-flutter-final.log` |
| Android | `flutter build apk --debug --target-platform android-x64 --dart-define=USE_MOCK=false --dart-define=API_BASE_URL=http://10.0.2.2:8080/api`，最终构建与运行证据见本节末补记及`output/ai-work-delivery-apk-final.log` |
| Web | `npm run build`、`npm run test:e2e`均退出0，10通过/2真实登录跳过；新增桌面/窄屏文件限额与上传错误交互；`output/ai-work-delivery-web-build.log`、`output/ai-work-delivery-web-test.log` |
| 规格 | `openspec.cmd validate --all --strict`，退出0、29/29；`output/ai-work-delivery-openspec-final.log` |

Flutter首次全量漏带仓库README要求的USE_MOCK参数，241通过/15失败/1跳过；保留`output/ai-work-delivery-flutter-test.log`，按原有演示测试命令重跑后通过，未删除失败证据。后端首轮179项全过，复查发现当前禁止指令仍需独立于长期授权进行防守，补单元及真实HTTP测试后最终181项全过。最后修复手机端文件错误分类/文案后重新分析、全量测试和构建，未沿用旧APK作最终交付。

本批运行补记：最终APK构建退出0，adb install返回Success并重开`emulator-5554`的App。镜像`8bcf123da3d7`已替换无数据卷API容器，健康UP、API到OCR ready、数据库仍V16、自动写入false，证据`output/ai-work-runtime/delivery-health.json`。最终JAR SHA256为`d180d8851369f6f2b478641503d550dffcd195a16f29a4caf0c18ad3727857b7`；同一JAR的Word、Excel公式、PDF文本、扫描页渲染和损坏文档入口专项退出0，`output/ai-work-delivery-parsers.log`。扫描专项仅证明渲染，不代表完整真实OCR验收。无新迁移，数据/OCR容器保留。gh明确未登录，混合工作区未提交/推送；OS沙箱、完整真实样本、设备/人测、跨端和剩余复合任务保持待办。

已实际查看模拟器新版AI地图截图`output/ai-work-runtime/ai-workbench-delivery-emulator.png`：真实会话加载空事项，五栏导航、材料入口和固定输入区可见，无开发说明文案。此截图只证明本地运行与该页面布局，不替代真机性能、读屏或易用性验收。最终差异UTF-8/敏感值检查123文件无错误，`git diff --check`退出0；测试生成的无关检索指标内容已恢复。

## 续做批次：正式资料检索、相似任务与公司授权限制

以下记录为本轮最新结果，优先于后文保留的前批次记录。

- 资料检索先过滤当前公司/组织/正式版本/有效期，按问题及材料中的中文二元词/英文词排序；支持分页，提供原文行/段摘录。模型引用限制为本次提供集合，不再使用空查询前8份。真实PG/HTTP验证55份目录分页、后排目标的第81行命中、无权部门标题/正文不进入模型、撤回后答案/列表失效。可检测同级同标题正文不一致与同流程稳定清单项差异，列双方依据并停止写入；任意自然语言隐含矛盾的完整判定仍未完成，4.2不勾选。
- 相似任务仅从当前可读集合、同主负责人、最近100个标题候选中选最多3个；暂停该项自动新建，提供原任务入口和“仍然创建任务”。真实链路验证确认前无回执、确认后新建独立任务、原任务版本不变。未达到全库语义查重和全部多任务/消歧矩阵，5.2及6.4保持未完成。
- 5.4已完成：本人限定授权含对象/有效期/每批上限，默认无授权；公司动作开关及上限走现有POLICY独立复核，管理员自审拒绝，生效前旧策略有效。V16将个人授权绑定公司授权修订，任何AI授权政策变化使旧授权失效，放宽不自动复活。用户锁和公司共享/排他行锁使撤回/公司变更与动作提交有确定顺序；真实数据库锁竞争测试验证在途提交先完成、下一步拒绝。Flutter管理员可提交公司限制复核，普通成员只在允许范围内创建个人授权。
- 安全/隐私：受权检索前过滤、模型上下文不含无权部门资料、撤回引用失效、自审拒绝；可靠性：真实PG两项锁竞争与不可复活授权测试。两类非功能验收限于上述已运行子集，不替代完整安全/性能矩阵。

| 本轮验证 | 明确结果与日志 |
| --- | --- |
| 后端标准脚本 | `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-backend.ps1`，退出0；162项、0失败/错误/跳过，含19项WorkIntegrationTest和5项检索/策略单元测试；`output/ai-work-continuation-backend-fixed.log` |
| Flutter分析 | `flutter analyze --no-pub`，退出0、No issues；`output/ai-work-continuation-flutter-analyze-fixed.log` |
| Flutter全量 | `flutter test --no-pub --dart-define=USE_MOCK=true`，退出0、249通过/1跳过；`output/ai-work-continuation-flutter-final.log` |
| Flutter专项 | `flutter test --no-pub --dart-define=USE_MOCK=true test/ai_workbench_test.dart`，退出0、5通过；`output/ai-work-continuation-flutter-fixed.log` |
| APK | debug/android-x64/真实8080 API，退出0；`output/ai-work-continuation-apk.log`；adb install Success，已重新打开模拟器 |
| Web | `npm run build`与`npm run test:e2e`均退出0；8通过、2真实登录跳过，`output/ai-work-continuation-web-build.log`及`output/ai-work-continuation-web-test.log`；新增相似/策略界面未做真实跨端验收 |
| 规范 | 严格校验29/29，退出0；`output/ai-work-continuation-openspec-final.log` |

首轮后端失败为历史升级测试固定断言15份迁移，与新增V16不符；修正为16后标准脚本全量通过，原失败日志保留。Flutter首轮发现相似任务按钮重复Flexible父数据，修正后专项和全量通过；3处lint也已修复。失败证据保留在`ai-work-continuation-backend.log`、`ai-work-continuation-flutter-test.log`和`ai-work-continuation-flutter-analyze.log`，不隐藏首轮失败。

已查看360dp/1.5倍字体相似任务截图，中文可读、无溢出，390/412同步控件验收；证据`output/ai-work-ui/similar-task-360.png`。本地数据库升级前备份`output/ai-work-runtime/backups/workpanel-pre-v16-20261021-172910.dump`，254014字节；最新镜像`9255e2c6e674`已重建API容器，保留数据库与OCR。自动写入false。真实供应商样本、OS禁网沙箱、真机/人测、审计备份恢复和远程Issue/PR阻塞保持原记录。

部署后已确认`/api/health=UP`、数据库当前版本16、容器到OCR返回ready，见`output/ai-work-runtime/continuation-health.json`。模拟器真实首页已加载空事项状态，截图`output/ai-work-runtime/ai-workbench-emulator.png`。任务勾选后apply返回34/64、30待办，严格校验仍29项通过；差异UTF-8/敏感值检查116文件无错误，`git diff --check`退出0。gh仍未登录且保留混合工作区，不自动提交/推送。

## 自动化命令与明确结果

| 验证 | 命令 | 结果与证据 |
| --- | --- | --- |
| 后端最终全量 | `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-backend.ps1` | 退出码0，151项、0失败/错误/跳过；含人员变更、正式流程清单来源/材料快照失效、事项列表/回执失效传播、V15及最终服务端打包，`output/ai-work-backend-release-candidate.log` |
| 补信息/选人追加验收 | `powershell -NoProfile -ExecutionPolicy Bypass -File output/verify-ai-retained.ps1 -Tests WorkIntegrationTest` | 退出码0，10项通过；真实PG/Redis/HTTP，`output/ai-work-clarification-verification.log` |
| Flutter分析 | `flutter analyze --no-pub` | 退出码0，No issues，`output/ai-work-flutter-pagination-analyze-fixed.log` |
| Flutter完整测试 | `flutter test --dart-define=USE_MOCK=true` | 退出码0，248通过、1跳过，`output/ai-work-flutter-all-verified.log`；含翻页去重/账号隔离与失效报告阻止提交；旧演示测试必须显式mock配置 |
| Flutter后续控件/文案 | `flutter test --dart-define=USE_MOCK=true test/ai_workbench_test.dart` | 退出码0，4项通过，`output/ai-work-flutter-pagination-tests.log`；发送失败保留、幂等键重用、真实回执语义、三种宽度/大字体、长任务选择标题无溢出且按钮≥48dp、翻页/失效报告/账号切换 |
| Android APK | `flutter build apk --debug --no-pub --target-platform android-x64 --dart-define=USE_MOCK=false --dart-define=API_BASE_URL=http://10.0.2.2:8080/api` | 退出码0，`output/ai-work-apk-release-candidate.log`；已adb安装成功，debug仅证明构建，不证明真机profile性能 |
| Web构建/类型 | `npm run build`（web） | 退出码0，`output/ai-work-web-build-final.log` |
| Web自动化 | `npm run test:e2e`（web） | 退出码0，8通过/2真实登录测试跳过，`output/ai-work-web-test-final.log`；浏览器接口桩不等于真实跨端验收 |
| 最后打包适配 | `mvn -B -f server/pom.xml -DskipTests package` | 退出码0，`output/ai-work-package-final.log`；修正部署文件改名app.jar的子进程入口识别，后续专项如下 |
| 打包解析专项 | `python output/verify-ai-parsers.py` | 退出码0，DOCX、公式XLSX、文本PDF、扫描页渲染、损坏DOCX拒绝5项通过，`output/ai-work-parser-verification.log` |
| app.jar子进程 | `java -Dloader.main=ParserProbe -Dloader.path=output/ai-work-parsers -cp output/ai-work-runtime/app.jar org.springframework.boot.loader.launch.PropertiesLauncher output/ai-work-parsers/valid.docx` | 退出码0，最终全量构建产物中真实ParserProcess调用独立子进程成功，`output/ai-work-parser-release-candidate.log` |
| 严格规格 | `openspec.cmd validate --all --strict` | 退出码0，29项通过、0失败，`output/ai-work-openspec-verified.log` |
| 差异卫生 | `git diff --check`及未跟踪文件UTF-8/尾随空格检查 | 结果见本记录末尾；不包含忽略的凭据、样本、构建/备份文件 |

官方后端首轮最终回归发现结构化选人answers为空导致规划失败，以及Flutter3项lint；修复后集中回归通过。第一次clean还曾因正在运行真实供应商验收的jar被占用而失败，等待该运行结束后重跑。后续150项首轮出现人员快照用例被旧Spring测试上下文的worker抢占，使用了前一用例的供应商配置；在BackendIntegrationTest和WorkIntegrationTest结束后关闭上下文，消除共享队列干扰。修复注解时一次testCompile失败也保留在`output/ai-work-backend-final-verified.log`。最终重新运行官方全量脚本150项通过，包含app.jar适配、结构化选人、人员快照及正式流程清单来源全部当前后端代码。失败日志不改写为通过。

## 已运行的业务与非功能证据

- 截图→受控OCR/模型→具体确认→创建任务→读取正式任务；新增追问→结构化选人/日期补充→确认→真实创建。员工无派发资格保持草稿；未知人员和旧version拒绝。
- 同确认键20线程重放只产生一次任务/回执/审计/outbox；20次过期租约恢复且旧fence拒绝。补充租约耗尽进入可恢复失败。注入回执写失败时业务整体回滚，移除故障后只成功一次。
- 补充人员快照校验：调岗/更名后GET隐藏旧计划，确认409且无业务回执。正式CREATE_TASK流程中的交付清单由服务端合入任务，并保留制度版本来源；制度撤回后旧PASS报告不得提交。后续补充GET报告、事项详情/列表/回执的实时失效传播；材料变更或制度撤回后返回STALE并隐藏旧核对项，Flutter禁用提交，前台/恢复时重新核对，提供最新任务入口。新增相关链路后13项WorkIntegrationTest通过，初轮证据 `output/ai-work-backend-snapshot-final.log`；其后对列表补充校验的最终全量另行记录。首轮正式流程测试误读任务body而非fields，修正断言路径后通过。
- 真实DOCX材料→202持久检查作业→GET恢复最终报告→反馈→人工验收；20次重复入队/反馈不重复。检查不会隐含接收、反馈不等于验收，旧报告/非参与者拒绝。
- 正式制度/模板独立发布、禁止申请人自审、维护稿不替换旧正式版本、撤回经复核；服务端安全正文预填、未知占位保留、伪造role与旧版本拒绝、比较入口鉴权。
- 权限与隐私：私人事项管理员拒读、原截图不随任务共享；当前组织范围、任务/附件读取、脱敏和复合外键/唯一键测试通过。这是已执行安全子集，完整负向矩阵仍待补齐。
- 迁移演练：V13历史任务、附件、AI作业和审批合成快照升级V14/V15，历史保留、跨公司外键与重复键拒绝。真实本地数据库升级前另有完整备份；未演练生产恢复。
- 可靠性与权限/隐私作为本批两项非功能验证，以上均有实际运行证据。性能、无障碍和易用性不因这些测试通过而自动通过。

## 真实供应商与文件证据

`python scripts/verify-ai-work-provider.py --container workpanel-it-data-9efd01979f` 在隔离测试库生成合成公司/用户，使用真实本地PaddleOCR和已配置DeepSeek，走服务端MemoryModel预算/限流。执行始终false，不创建正式任务，凭据只在子进程环境，不打印。脚本后续已修正：有FAILED样本时退出1，并可用--output保存独立轮次。

- 第一轮完成60份合成中文截图，clear/compact/blur/missing_date/relative_date/injection各10份；27份待确认、31份需补充、2份失败。失败为OCR_FAILED与INVALID_FIELD各1份。候选负责人/截止时间误匹配0；无正式写入。追问31/60，端到端中位约11.41秒、P95约13.39秒，`output/ai-work-provider/result.json`。
- 该轮旧脚本退出0只检查样本数和关键误匹配，漏计FAILED；因此此轮不能判为通过。现脚本将FAILED纳入失败判定，保留原始样本与统计，不改写为成功。
- 新版服务端6份短复核，5份待确认/追问、1份INVALID_FIELD失败、关键误匹配0，退出码1，`output/ai-work-provider-final/result.json`。该文件记录被测jar SHA256；后续app.jar入口小改由打包解析专项覆盖。
- OCR真实中文冒烟3行精确识别，但约6.04秒；只有单次证据，不能称P95≤5秒已通过。证据 `output/ai-work-samples/ocr-smoke.json`。
- 文档专项验证扫描PDF可渲染出待OCR页面，未在该专项中调用真实OCR；不能把渲染当作扫描PDF全文识别验收。
- 样本均为合成截图，未完整覆盖真实聊天历史、多页、同名、全格式组合；逐字段定位/金额/成本统计也不完整。9.7仍未完成，不降低原60份代表样本的验收要求。

## 界面和本地运行

窄屏原型：`mobile/prototypes/ai-workbench.html`。Flutter控件截图：`output/ai-work-ui/home-{360,390,412}.png`、`confirmation-*.png`、`receipt-*.png`、`selected-task-*.png`。360宽度使用1.5倍字体；首页五栏导航、输入区、自然中文确认/回执及长任务选择均无溢出，字体未缩小。长标题最多两行，保留完整文本语义。控件截图采用受控repository，只证明布局和交互语义。

真实模拟器 `App_Run_API37 / emulator-5554` 已安装最终debug APK并打开AI地图，截图 `output/ai-work-runtime/ai-workbench-emulator.png`，现有会话通过真实API读取首页。后端 `workpanel-ai-api-main` 在127.0.0.1:8080，健康UP；本地数据保留并从V13升级V15，迁移前备份和独立遗忘账本在 `output/ai-work-runtime/backups/`。OCR容器只在internal网络，后端同时接普通出站网络与OCR内网；后端到OCR健康ready。写入false、OCR true。没有为演示创建用户正式任务。

此模拟器运行不算真机profile、TalkBack或五人易用性验收。后端当前使用本地验证镜像/配置，正式部署仍需按部署文档完成资源、安全和恢复验收。

最终151项全量通过后已复制同一jar构建镜像`815fe4946270`并重建无数据卷API容器；数据/OCR容器保留。镜像构建退出码0，日志`output/ai-work-runtime/build-release-candidate.log`。后端当前包含人员快照、正式流程清单来源及报告/回执失效校验；同名部署文件app.jar独立解析专项退出码0。

## 历史批次的未完成范围与阻塞

本表为前批次快照，3.3、4.4–4.5、5.5、6.1/6.4、8.7及10.4的最新实现和验证以文首集中收尾记录及tasks为准；保留此表用于解释历史验收范围。

| 任务 | 已做与缺口 |
| --- | --- |
| 1.1、10.7 | 本地Issue草稿已建；gh未登录，未建立正式Issue/Sprint/PR。前批次布局、旧change和lockfile混合改动仍在，按AGENTS.md不得自动混入提交/推送 |
| 3.3 | 3.2共同文件契约已在本批完成；OCR成功部署，但完整依赖锁重建、文档OS级禁网/资源沙箱尚未完成 |
| 4.2、4.4–4.5 | 已补检索/分页/原文行段定位，复杂隐含语义冲突、二进制模板填表及管理页完整异常矩阵仍待补齐。正式来源变化已在检查/提交时重查；完整界面失效矩阵待验收 |
| 5.2、5.5 | 已补跨事项相似任务提醒，5.4公司收窄策略和并发顺序已验证并勾选；完整多任务拆分/实体消歧矩阵、只重问受影响步骤仍待完成 |
| 6.1、6.4–6.5 | 有持久步骤、有限串行调度、部分结果/回执；6.6的SSE/GET恢复已验收，复杂依赖、完整竞态/跨端矩阵仍未全覆盖 |
| 7.5、9.4 | 7.5检查后提交边界及正反链路本批已完成；9.4完整材料损坏/模糊、多格式补充与全部异常矩阵仍待补齐 |
| 8.7–8.8 | 8.2的正式DTO/repository、分页去重、恢复与账号隔离已验收；焦点/滚动、离屏动画暂停、完整读屏/对比度/触控审核仍待完成。分页按现有offset契约刷新已加载窗口，不宣称并发变化期间的全局一致数据库快照 |
| 9.3–9.7 | 已有核心发布/检查/权限/重放测试；全部场景矩阵、各类20次故障重放、完整真实供应商代表集未达标 |
| 10.1–10.4 | 窄屏/大字体布局通过子集；真机profile/TalkBack、装饰失败、20并发完整隔离性能、5位首次用户、365天审计/备份删除重放仍待完成 |
| 11.2–11.3 | Web页面/SSE/构建/受控自动化已实现；完整真实Android/Web续办/冲突/失权/键盘读屏和真实登录测试待完成 |
| 12.1–12.2 | 未满足发布/归档条件，不提前同步主规格为已交付，不归档 |

未开放写入不是功能完成。后续应先关闭上述P0缺口并保留外部设备/人测阻塞，确认发布条件后再开放对应自动动作。

## 本批最终核对

- 官方后端151项全量、Flutter分析与受影响控件4项、Android APK、最终app.jar独立解析专项均取得退出码0；Flutter最新全量248通过/1跳过。Web8通过/2跳过的先前证据仍保留其快照限制。
- `openspec.cmd validate --all --strict`退出码0，29项通过、0失败；当前34/64项完成，未归档。
- `git diff --check`退出码0；107个实际差异/未跟踪文件通过UTF-8、替换字符、新文件尾随空格与已配置密钥匹配检查，敏感值未打印。忽略目录中的凭据、备份、样本和构建物未进入提交。
- 无关自动生成的`docs/ai-map-retrieval-metrics.json`已恢复HEAD原始字节；保留新接口的OpenAPI快照。
- 本地最新后端`/api/health`为UP，容器内到OCR健康ready；模拟器安装返回Success并打开AI地图。自动写入仍false，不以运行健康替代业务发布验收。
- `gh auth status`明确未登录；混合工作区未提交/推送/建PR。远程main因此不会出现本次代码，不虚构已上传状态。
