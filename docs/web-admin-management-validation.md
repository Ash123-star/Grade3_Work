# Web 两页管理端验证记录

日期：2026-10-23。OpenSpec：`web-admin-account-company-items`（US-01～US-06）。

## 实施范围

- `/` 默认进入 `/admin/accounts`：查询本公司全部状态账号、部门/状态/关键词筛选、分页、编辑姓名/组织/直属上级/角色/状态/派发资格、待确认员工归属候选。
- `/admin/company-items`：事项查询、新增与编辑、置顶/取消置顶、排序位置、归档、正式生效前十预览；不补造十条数据。
- 两页各自提供修改与审核抽屉，不新增第三个主页面。旧 AI 工作区仅保留 `/legacy` 兼容地址，原有自动化用例迁至该地址。
- 新增管理 Controller/Application/Repository；公司事项候选复用审核服务，输入规则放入领域策略。服务端双入口均验证 ACTIVE ADMIN 和公司范围，不改变 Android 原有公共权限。
- 保留候选版本、独立复核、禁止自审、版本冲突及公司级置顶容量锁。账号/手机号/复核资格只读，不提供账号硬删除、密码重置、跨公司总管理员功能。

## 环境与依赖

Windows PowerShell、Node 24.17.0、Chrome、Java 21、Docker Maven 3.9.9 / Temurin 21、独立 PostgreSQL 16/Redis 测试容器；Web `127.0.0.1:5173`，后端 `127.0.0.1:8080`。当前工作分支 `codex/ai-work-assistant`。

新增 Element Plus 2.14.7、@element-plus/icons-vue 2.3.2、Vue Router 4.6.4、Pinia 3.0.4，均为 MIT；版本和许可读取已安装包，lockfile 固定依赖。沿用 Vue 3.5 / Vite 6 与 TypeScript，生产构建验证兼容；未使用 OpenMoji 或外部图片素材。原 VueFlow 页面与两管理页均按路由拆包，组件与图标显式导入。

## 验证命令与结果

| 项目 | 命令 / 证据 | 结果 |
| --- | --- | --- |
| 前端构建 | `npm.cmd --prefix web run build`；`output/web-admin-pr/frontend-build.log` | 退出0，类型检查与生产打包通过 |
| 前端回归 | `npm.cmd --prefix web run test:e2e -- --workers=4`；`frontend-validation.log`、`frontend-real-validation.log` | 首轮退出0：46通过、4跳过。新增详情失败保护后48项通过、5跳过，真实系统用例因组件内部input选择器失败；修正后仅重跑该真实用例通过。跳过不能计为通过 |
| 规范 | `openspec.cmd validate --all --strict`；`openspec-validation.log` | 退出0，31通过、0失败 |
| 后端全量首次 | `powershell -ExecutionPolicy Bypass -File scripts/test-backend.ps1 -DockerMaven`；`backend-validation.log` | 退出1；401项中1失败、1错误。AI流式撤权用例未收到access-lost；新增容量夹具遗漏非空body，已修正夹具 |
| 后端定向复验 | `backend-targeted-validation.log` | 43项中42通过，包含原18项、组织8项、审核9项、AI流式撤权1项；容量夹具将非ADMIN复核人错误送入管理入口产生403，修正为原公共审核入口 |
| 管理后端最终验收及打包 | 隔离容器执行 `mvn -B -f server/pom.xml verify "-Dtest=CompanyItemPolicyTest,ManagementIntegrationTest"`；`backend-management-validation.log` | 退出0，7通过、0失败、0错误；JAR重新打包成功。与上一轮已通过的定向项共同覆盖本次失败修复，未将其报告为最终重新全量通过 |
| 真实浏览器系统链路 | `npm.cmd --prefix web run test:e2e -- management-real.spec.ts --project=desktop --workers=1`；`frontend-real-system.log` | 退出0，1通过；真实登录、页面表单、两名独立管理员、真实PostgreSQL与审核生效，无Mock。凭据通过环境变量提供，默认无凭据跳过 |
| 运行服务 | `backend-deployment.log`；`GET http://127.0.0.1:5173/api/health` | 退出0，本地既有容器运行新JAR，Vite同源代理返回UP；没有重置示例账号密码 |

修复测试脚本的 PowerShell 5 NativeCommandError 处理：Docker Maven 的 Mockito 警告不再触发提前清理数据库，以 Maven 进程退出码判定。首次定向执行因该执行器问题中断，孤立 Maven 容器已停止；未将其计入通过。

## 验收链路与证据

前端测试覆盖两个独立路由、刷新深链、手机导航、账号完整候选、事项409保留输入和纯文本、非ADMIN不发管理请求。后端新增管理测试覆盖本公司全部状态、公司隔离、跨公司404、直接入口拒绝、非法分页、账号候选审核前不生效、禁止自审、旧版本冲突、敏感字段拒绝、事项公开读取/归档一致及容量冲突回滚。

真实系统用例使用独立验收公司，不修改原有示例账号；通过真实登录、页面表单、第二名管理员抽屉审核，验证待确认员工激活、部门生效及停用后旧会话被拒绝；事项新增、编辑与归档逐次审核后核对Web预览及Android共用公共API，纯文本script片段没有执行。先前失败用例仅为自动化点击Element Plus内部隐藏input/被占位层覆盖的input，改为点击可见控件容器后通过，业务接口未绕过。

已实际查看1440×900、1024×768、768×1024及200% CSS缩放截图，页面无横向溢出，键盘焦点保持在编辑抽屉中。干净截图等待临时成功消息自然消失后拍摄，保存至 `output/web-admin-pr/accounts-1440.png`、`accounts-200-percent.png`、`items-1440.png`、`items-1024.png`、`items-768.png`（本地产物，不提交Git）；原图同时位于 `web/test-results/management-real-real-manag-5f552--through-independent-review-desktop/`。CSS缩放验证不等同于所有浏览器原生缩放及辅助技术的完整验收。

独立测试公司以 `web-acceptance-` 前缀标识，只包含本地生成的验收成员和业务记录；重试使用新公司避免覆写原数据，保留审核证据。该数据不混入示例管理员所属公司的列表。测试结束已退出管理员会话，未把密码/token写入源码或本文。

安全验证关注公司隔离、敏感字段白名单、未授权管理入口、Vue纯文本XSS和停用后会话。易用性/无障碍验证关注导航名称、抽屉焦点、键盘、缩放与页面溢出；深色次要文字提高可读性。未做全量WCAG审计，不宣称全部颜色/辅助技术组合达标。

## 启动、部署与回滚

1. 先启动后端及其 PostgreSQL、Redis，再启动 `npm.cmd --prefix web run dev -- --host 127.0.0.1`。
2. 开发 Vite 代理 `/api` 至8080，生产反向代理同源 `/api`；对 `/admin/accounts`、`/admin/company-items`、`/legacy` 配置 SPA 回退 `index.html`，开启HTTPS，禁止公开数据库端口和环境文件。
3. 使用已有管理员凭据，首次登录按原流程改密；至少准备另一名独立有效公司复核人，否则候选持续待审，不能由申请人自审。
4. 本批没有数据库迁移：复用已存在的 users、dashboard_items、审核、审计、outbox及公司索引；不修改任何已发布Flyway脚本。未新增大规模负载指标，生产性能仍需实际环境评估。
5. 本地更新保留现有后端容器配置、网络及数据库，先备份旧JAR，再替换应用JAR并检查健康；失败还原旧JAR。生产应正常重建并发布带版本镜像，不复用本地热替换方式。
6. 回滚前端和后端应成对进行；已审核的账号/事项属于正式业务数据，不通过应用回滚撤销，需提交新的审核候选修正。

## 未完成、未验证与外部阻塞

- 原规划中的审核状态/目标筛选及独立管理审计检索未实现；现有抽屉显示本人申请/分配审核及其决定历史。对应2.5、3.5保持未勾选。
- OpenSpec仅勾选已有实现与实际验收证据的任务，其他角色组合、完整只读字段呈现、团队契约确认等任务仍保留未勾选；不会以两页主流程通过代表整个26项规划全部完成。
- Android实体设备与生产部署未验收，公共API一致性不能代替设备验收；完整无障碍审计、全部角色调岗组合和生产负载未验证。
- 真实 Issue/看板关联、非作者审阅、归档未完成；本地完成不等于生产上线或整个OpenSpec全部完成。
- 仓库存在用户原有 `.vscode/settings.json`、两个mobile锁文件及 `docs/weekly-report-2026-10-23.md` 改动；按AGENTS约束停止自动提交/推送，未覆盖这些文件。GitHub此前认证/网络不可用，未创建成功PR，不能报告已提交。
- 实施贡献：本次代理负责两页前端、管理后端契约、公司事项输入策略、测试与本文档；不冒用团队成员或认证上下文姓名。
