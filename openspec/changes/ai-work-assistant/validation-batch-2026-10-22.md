# 4.2、9.6、9.7 与 main 接口接入验收

环境：Windows、JDK21、Docker PostgreSQL16/Redis、已锁定 PaddleOCR3.0.3 镜像、服务端已配置 DeepSeek、Chrome 和 Android App_Run_API37。材料按用户确认使用合成多场景测试集，不代表真实生产材料准确率。正式自动写入保持 false；可写故障测试只使用 `workpanel-it-data-*` 隔离库。

## 已取得的运行证据

本批指定4.2、9.6、9.7已完成，当前54/64。9.7是完成采样、记录指标并按不达标项停写，不能解释为已达到全部性能/发布条件。自动写入false，原10.2等发布前性能与设备任务继续待办。

- 标准后端命令 `powershell -ExecutionPolicy Bypass -File scripts/test-backend.ps1 -KeepContainers` 首轮退出0，387项全过，`output/ai-work-batch-backend-final.log/.exit`。随后因材料验收发现模型把附件误当制度引用，修复已知材料引用处理、补充模型约束，并将 OCR 连接/响应超时映射为可有限重试的 OCR_UNAVAILABLE；受影响34项回归退出0，`output/ai-work-backend-affected.log/.exit`。修复后标准完整回归388项全过、退出0，`output/ai-work-batch-backend-verified.log/.exit`。交付样本又发现标题关键词被算作字段重复和模型空动作，修复后相关领域/HTTP/检查提交链路20项全过并重新打包、退出0，`output/ai-work-delivery-affected.log/.exit`；最后两项修改不以此前388项结果单独证明。
- `python scripts/verify-ai-work-restarts.py --container workpanel-it-data-4e0cb3720d --jar output/ai-work-acceptance-build/server/target/collaboration-server-1.0.0.jar` 退出0。20轮、40次真实 JVM 强制终止，提交前使用 PostgreSQL 屏障证明业务事务已到回执插入，终止后确认回滚；重启正常持久 worker 恢复，提交后再次终止，再重启并每轮20次重复确认。每轮任务派发事件/动作回执/审计/outbox 均为1，`output/ai-work-restarts/result.json` 和完整服务日志。仅推进租约时钟，未用状态修改代替进程重启。被验包与最终包生产代码差异只有 WorkPlanner 的附件引用/问题约束/只读检查空动作处理、FileExtractor 超时分类及 DeliveryRules 字段标签匹配，执行事务/恢复代码相同；差异清单在 `output/ai-work-final-source-differences.json`，SHA256清单保存在对应 build 目录和最终源文件清单。
- 正式资料检索覆盖授权范围、50条后检索、中文/同义词、行段定位、同级冲突、模型漏引用、过期/不存在/撤回及调岗失权。服务端绑定匹配工作流/规则依据，模型不能漏报后绕过检查。未知 ID 拒绝，私人材料不能提升为正式制度，金额数量需同值同单位。保守语义检查不承诺识别任意自然语言隐含冲突。
- Flutter `flutter analyze` 退出0，无问题；`flutter test --dart-define=USE_MOCK=true` 退出0，276通过/1跳过；实际 API debug APK 构建退出0。证据 `output/ai-work-batch-flutter-analyze-final.*`、`ai-work-batch-flutter-tests-final.*`、`ai-work-batch-apk-final.*`。首轮未传项目所需 USE_MOCK 造成18项旧演示测试失败，原日志保留。最终 APK 安装 Success，现有示例会话从真实后台恢复，首页保留五栏导航。
- Web 类型/构建退出0。全量浏览器36通过/4失败/4凭据依赖跳过；四项失败为分析页导航名称及失权后导航消失的旧定位，修正后定向4通过/2凭据跳过。合计40项通过，4个真实登录用例仍未执行，不重复计数。证据 `output/ai-work-batch-web-build-final.*`、`ai-work-batch-web-tests-final.*`、`ai-work-batch-web-analysis-verified.*`。
- 实际 HTTP 联调退出0，`output/ai-work-main-sync/contracts-result.json`：ADMIN别名可读写本人事项、真实SSE转发、员工403、撤权立即403、未知别名404，原移动端路径可用；日志提交能力、公开评论与同日志回复、非法回复400、撤回保留首次时间、重提不重置、超24小时撤回409及窗口外评论、部门关键词查询均通过。由该运行服务导出 `docs/openapi.json`。
- 本地数据先 pg_dump 和删除标记备份，再升级 V17/V18；健康 UP，自动写入 false。旧 API 停止保留，备份267258字节；`output/ai-work-runtime/batch-update-result.json`、`batch-update-final.log/.exit`。首次运维脚本遇到空 Cmd 参数，已恢复旧 API 后修正并成功重跑；原失败日志保留，未删除数据库或卷。

## 60份材料验收

脚本 `scripts/ai-work-acceptance-corpus.py` 生成20份任务整理、20份正式制度查询、20份交付核对，覆盖 PNG/JPEG/DOCX/XLSX/多页扫描 PDF，缺日期/旧相对日期/同名/注入/模糊/冲突/缺依据/过期/金额不符/缺字段/公式/签字等场景。`verify-ai-work-corpus.py` 经真实本地 OCR 和真实 DeepSeek，只读检查可产生检查回执，但不写正式任务或反馈。工具依赖记录在 `scripts/requirements-ai-work-acceptance.txt`；默认完整60份，--chain/--case仅定向复验，自身不算全样本通过。

完整60份运行 `python scripts/verify-ai-work-corpus.py --container workpanel-it-data-a5ef8f51e8 --image workpanel-backend:ai-work-final --output output/ai-work-corpus-final`，55通过、5未满足预期，退出1。68,646 tokens、业务字段准确率92.65%、提取字段准确率100%、定位率100%、追问率28.33%、中位14.835秒/P95 27.984秒、账户余额观察扣减0.15元。关键字段误写0、正式AI写入0。失败41/51为标题提及成本造成不唯一，43/59为模型空动作，57是公式在规划阶段安全追问而未生成检查报告，原脚本只接受报告而误记失败。原报告保持原样，不改写通过。

交付修复采用独立字段标签匹配，重复标签/无单位/不清晰仍不能通过；明确从任务入口要求“只检查”且模型无动作/无问题时，由服务端补建只读 CHECK_DELIVERY，不补任何提交/创建动作。规则版本升为delivery-rules-2，旧报告快照自动失效。模糊样本因格式轮换落入docx，已改为真实PNG并加重模糊；新的交付20份重新验收，另补任务模糊图片。公式/模糊安全暂停必须同时有解析器无法核实标记、持久WAITING_INPUT及非空问题且无检查回执，单纯文字成功不能通过。以下记录最终定向统计，不能将不同轮次伪称一次60/60运行。

最终复验证据如下，原始报告均保留：

- `--chain delivery --image workpanel-backend:ai-work-delivery-final --output output/ai-work-corpus-delivery-recheck` 实际20份中19份符合脚本预期，1份（55，缺成本）在规划时针对成本追问，尚未生成报告。原退出1/原19统计保留；该版脚本对任意不足60份的子集也返回1，已改为按本次选择的样本数判退出，子集仍不能等同完整覆盖。
- 55的材料明确“成本尚未填写”，问题明确要求补充成本，WAITING_INPUT、无回执，属于安全提前追问；补充验收条件同时要求这三项独立证据，不能用任意问题代替检查。`--case 55 --output output/ai-work-corpus-missing-supplement` 真实重跑返回UNVERIFIABLE，退出0。19的加重模糊PNG补验 `--case 19 --output output/ai-work-corpus-blur-supplement` 正确追问、无动作，退出0。59加重模糊PNG也安全追问；公式安全暂停、签字UNVERIFIABLE、金额不符NEEDS_FIX均保留。
- `output/ai-work-corpus-reviewed.json` 按每个场景最新证据汇总，明确标为跨轮次复验，60个独立场景均有符合预期结果，关键字段误写0、正式AI写入0；保留完整首轮失败与构建差异。最终业务字段完成准确率97.06%、提取字段准确率96.81%、定位率100%、追问率31.67%，模糊材料未提取字段计入分母，不因追问就算字段识别成功。选定最新样本68,797 tokens，中位14.392秒、P95 27.984秒；耗时包括验收夹具、HTTP轮询及余额观察，不作为纯OCR性能数据。
- 四组证据共82次实际供应商调用、93,394 tokens；账户观察扣减分别0.15/0.03/0.01/0.00元，合计约0.19元。受余额精度及并发账号流量影响，不能当单请求精确账单，也不包含更早中断/诊断轮次。请求配置deepseek-chat，供应商实际响应模型为deepseek-flash，未套用旧模型费率估算成本。
- 完整组12PNG/11JPEG/12DOCX/13XLSX/12扫描PDF；最终补验将两个原模糊DOCX用例改为真实PNG。生成器、每轮manifest、供应商JSON、事项回执和原始日志保存在对应output目录。隐私、组织范围与故障测试另在后端中完成，不用合成准确率替代权限验证。

正式自动写入继续关闭：本地OCR先前冷推理硬超时、当前全链路P95及模糊样本识别不足不能当性能达标；真实生产材料、20并发隔离性能、真机profile/TalkBack和首次用户验收仍由原待办跟踪。9.7采样工作完成不开放自动动作。

最后运行镜像为 `sha256:4fe7679e6aeafea6c6062c8665aa1bf46a104ed8e23d0d902bc0c0b2541f758a`，同源JAR及172份生产源文件SHA256清单在 `output/ai-work-delivery-source-manifest.json`。本地数据库再次备份后已更新到该镜像，V18、健康UP、写入false，`output/ai-work-runtime/batch-delivery-update.log/.exit`、`batch-update-result.json`；最新备份268527字节，旧API停止保留。此前备份与旧API仍保留。真实Web示例管理员登录、办事页和任务审计导航冒烟退出0，`batch-web-smoke.log/.exit`，已留页面截图；模拟器新版APK实际读取AI地图，`batch-ai.png/.xml`。这不等于三条Web业务闭环或读屏任务全部交付。

保留失败轮次：首轮在 OCR 冷推理超时退出且缺重启策略时中止；后续审计轮确认模型把 files[].id 当制度 sourceIds 导致 AI_SCHEMA，修复后重新完整运行。中止/诊断子集不计作60份验收通过。审计代理仅转发合成验收请求并保存无鉴权头的供应商JSON，供逐例核查，不属于生产调用路径。

## GitHub 和迁移限制

通过公开 GitHub API 核实 main 为 `dc00e2b86650f0b9077f898c5a510dc78e86ce9b`，无开放PR，已合并 [#23](https://github.com/Ash123-star/Grade3_Work/pull/23)。三方内容接入保留本地 AI 改动，未生成 Git 合并提交。`git fetch` 到 GitHub443失败，gh认证不可用；工作区另有前批布局、OpenSpec及lockfile混合改动，按AGENTS.md不自动混入提交/推送，未创建新PR。

本地 AI 已执行 V14/V15/V16，与 main 日志 V14/V15 编号冲突。本批保留已执行脚本，前向新增 V17/V18。当前本地 AI 库和新建库均可升级；已执行 main 日志 V14/V15 的数据库不能直接升级本分支。发布前须在恢复副本统一并验证两条历史，不使用 repair 掩盖冲突。详情见 acceptance-batch-2026-10-22.md。代码接入不代表远程已合并或可直接部署到 main 数据库。

安全与可靠性为本批两项非功能验收：服务端身份/组织/私人事项隔离、未知引用与数字不猜测；事务回滚、持久恢复、重放去重和有界供应商重试。性能、真机读屏和首次用户人测仍按原任务保留待办。

最终规范与卫生核对：`openspec.cmd validate --all --strict` 退出0，30通过/0失败；`output/ai-work-batch-openspec-verified.log/.exit`。apply确认54/64，`ai-work-batch-apply-final.json`。`git diff --check` 退出0，`ai-work-batch-diff-verified.log/.exit`。164份实际差异/未跟踪文本通过UTF-8、替换字符/损坏问号和已配置Key匹配检查，`ai-work-batch-hygiene-final.json`；验收脚本Python语法检查通过并清理本批pyc。此为工作区卫生检查，不意味着混合差异可自动提交。已人工查看本机App和Web截图，真实旧检查显示“需要重新检查”，未将失效报告显示为通过；完整读屏仍待办。
