# 管理员简易后台

关联 OpenSpec：`admin-simple-console`。2026-11-11用户确认仅做ADMIN后台，本地运行加云端部署说明，不操作在线服务器。实际结果见 [验收记录](admin-console-validation.md)。

## 功能

- 员工与账号：搜索含停用人员的目录；录入姓名、手机号、部门、账号、初始密码，直接创建ACTIVE/EMPLOYEE并强制首次登录改密。公开注册仍为PENDING。账号3–64位字母/数字/`_.-`；大陆手机号；密码至少12字符、UTF-8最多72字节。
- 员工维护：姓名、部门、启停提交独立审核，跨部门时同一候选解除旧团队归属；旧值审核前保持，停用生效撤销会话。已有手机号只读；本批不做批量导入、重置他人密码、角色授予或组织关系编辑。
- 公司重要事项：新增、修改、排序、置顶、撤下、恢复，最多十条置顶，审核前旧版有效。Android读取同一已生效数据。
- 修改记录：本人申请和分配审核的进度/详情，不能自审。没有有效审核人保持待审，组织维护人员需通过原有能力补齐申请人直属关系。
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

产物为 `web/dist/`。按 [现有systemd部署](cloud-systemd-deployment.md) 更新配套后端JAR，保留实际DB_URL，不启动第二个占用8080的API。后台无需新表/新迁移。

把dist上传服务器新的静态版本目录，备份Nginx配置后合并 [Nginx示例](../deploy/web/admin-console.nginx.conf)，替换域名、证书、静态目录；示例用于独立站点根路径。保留原移动端`/api/`路由，同源反代到8080；先`nginx -t`再reload。正式使用需HTTPS，不原样覆盖现有配置。

前端请求相对`/api`，不内嵌服务器地址或密钥。发布验收包括管理员登录、创建员工、首次改密、独立审核、Android读取；不得在生产用个人数据做破坏性测试。回滚静态目录和配套旧JAR，已创建账号及审计保留，不删表。

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
