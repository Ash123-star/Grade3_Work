# 管理员简易后台

关联 OpenSpec：`admin-simple-console`、`admin-employee-directory-improvements`。2026-11-11用户确认仅做ADMIN后台，本地运行加云端部署说明，不操作在线服务器。实际结果见 [验收记录](admin-console-validation.md)。

## 功能

- 员工与账号：按部门筛选、搜索含停用人员的精简目录，显示部门/组及直属上级；点击姓名或“查看详情”打开只读资料；录入姓名、手机号、性别、身份证号、部门、组、直属上级、业务职位、账号、初始密码，直接创建ACTIVE/EMPLOYEE并强制首次登录改密。组须属于所选部门，普通岗位的上级须为同部门在职业务管理人员；部门经理及公司级任职人员可跨部门选择创始人、总经理或分管副总。ADMIN身份本身不提供业务上级资格。身份证号只在创建或修改时提交，详情只显示是否录入，审计不保存原号码。公开注册仍为PENDING。账号3–64位字母/数字/`_.-`；大陆手机号；密码至少12字符、UTF-8最多72字节。
- 员工维护：Web 管理员修改姓名、部门、组、直属上级和启停会立即生效，保留版本、原因与审计；待确认员工启用前必须补齐部门、组和直属上级，原待审申请标记为已由管理员处理。跨部门时若未指定新组则清除旧团队归属，停用撤销会话。手机端及普通员工原有审核规则不变。已有手机号只读；本批不做批量导入、重置他人密码或角色授予。
- 公司重要事项：Web 管理员新增和修改立即生效；页面只显示事项与编辑操作，内部排序、展示状态和版本不作为可见设置。Android读取同一已生效数据。
- 修改记录：展示管理员直接生效的员工开通、资料和公司事项操作，包含操作者、对象、原因、时间和脱敏前后值。“申请与审核”只展示当前有效待审申请，历史已决和目标版本失效的成员申请不占列表，数据库仍保留记录供审计；Web 管理员直接修改不进入该待办。
- 旧AI源码保留但不作为后台入口；不建设完整任务、日志、报表和AI Web。

## 本地启动

后端使用Java21、PostgreSQL、Redis和server Flyway模型，按 [后端说明](backend.md) 启动；不要混用deploy/postgresql独立模型。使用现有管理员账号，没有公开默认密码，初始化仍通过后端环境配置。

仓库根目录执行：

```powershell
Set-Location web
npm.cmd ci
npm.cmd run dev
```

打开终端打印的地址（默认 `http://127.0.0.1:5173`）。默认 `/api` 代理至 `http://127.0.0.1:8080`。其他端口可在 `web/.env.local` 设置 `VITE_API_TARGET=http://127.0.0.1:8081`。环境文件不提交，不填写密钥。Vite仅用于本地开发。

## 云端部署说明

本地开发完成后使用同一份代码构建静态文件，不需要第二套后台；实际云端发布不在本次范围。

```powershell
Set-Location web
npm.cmd run build
```

产物为 `web/dist/`。按 [现有systemd部署](cloud-systemd-deployment.md) 更新配套后端JAR，保留实际DB_URL，不启动第二个占用8080的API。后端需执行 Flyway `V35__employee_identity_card.sql` 及 `V36__employee_business_position.sql`，不得混用独立 `deploy/postgresql` 迁移模型。

把dist上传服务器新的静态版本目录，备份Nginx配置后合并 [Nginx示例](../deploy/web/admin-console.nginx.conf)，替换域名、证书、静态目录；示例用于独立站点根路径。保留原移动端`/api/`路由，同源反代到8080；先`nginx -t`再reload。正式使用需HTTPS，不原样覆盖现有配置。

前端请求相对`/api`，不内嵌服务器地址或密钥。发布验收包括管理员登录、创建员工、首次改密、Web 修改立即生效、Android读取及手机端既有审核；不得在生产用个人数据做破坏性测试。回滚静态目录和配套旧JAR，已创建账号及审计保留，不删表。

## 集中验收

```powershell
powershell -ExecutionPolicy Bypass -File scripts/test-backend.ps1
openspec.cmd validate --all --strict
Set-Location web
npm.cmd run build
npm.cmd run test:e2e
```

后台UI用例`web/tests/admin`通过独立配置自动启动5177端口，使用接口夹具，不能替代真实HTTP/数据库验收。旧AI入口测试保留为`npm.cmd run test:e2e:legacy`。

`AdminConsoleIntegrationTest`覆盖真实HTTP→认证/审核→PostgreSQL，依赖测试数据环境；`EmployeeProvisioningTest`覆盖输入边界。安全验证包括角色、公司、初始密码和文本转义；可靠性验证包括唯一约束、事务原子性、版本冲突和置顶上限。

## 员工录入规则（Issue #101）

姓名去除首尾空格并按NFC规范化，2–50个Unicode字符，兼容生僻汉字、字母与组合标记，以及内部空格、·、连字符、撇号；禁止数字、表情、控制字符、首尾或连续分隔符。前后端规则相同，新建/修改时检查，不批量改写旧数据。

大陆手机号须11位数字并满足维护的公众移动号段策略，拒绝111、154、194等无效前缀；账号、手机号和身份证任一重复返回409，fieldErrors分别指出所有预检查冲突；同时录入仍由数据库唯一约束兜底。响应不说明已有员工身份。

身份证需匹配现行/历史县区码、1900年至今天的真实出生日期、标准校验位和所选性别；不接入实名认证。字典版本、来源及许可见server/src/main/resources/identity/input-data.md。修改证件号排除员工本人，原号码不回显、也不写审计。年龄只从有效证件计算，不能由姓名或手机号推算。

目录保留六列：员工/账号、组织归属、角色/业务职位、直属上级、账号状态、操作；详情显示手机号、性别、证件录入标记、年龄与组织关系。窄窗口转为卡片布局，长内容换行。

业务职位NONE（普通岗位）/GENERAL_MANAGER（总经理）/DEPUTY_GENERAL_MANAGER（分管副总）与五种系统角色独立。管理员按实际任职设置，不自动提升系统权限。部门经理可跨部门配置本公司在职公司级负责人，禁止自身、循环、跨公司或停用人员。关系仍保存到reporting_relations，手机端原manager_id与审核链共用该关系。职位变更沿用员工version/reason和审计，不自动重排已有组织。V36只新增字段，默认NONE，不猜测已有人员任职；发布前须先执行迁移，回滚应用时保留字段及数据。
