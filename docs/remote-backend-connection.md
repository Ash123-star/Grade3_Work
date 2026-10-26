# Web 管理后台远程 API 配置

2026-10-26：本地 Web 开发服务器将 `/api` 代理至 `https://www.panduolawork.asia`，保留 `/api` 路径，并通过 `changeOrigin: true` 使用目标域名的 Host。修改位置：`web/vite.config.ts`。重启 Vite 后生效。生产构建仍使用同源 `/api`，需由部署网关配置转发。

继续支持通过 `web/.env.local` 中的 `VITE_API_TARGET=http://127.0.0.1:8080` 切回本地；环境变量优先于默认目标。本次未修改后端服务、数据库、权限或移动端配置。

## 连通性与限制

- 本机 DNS 查询：`www.panduolawork.asia` 解析为 `39.96.84.51`。
- `curl.exe -I http://www.panduolawork.asia`：HTTP 403，Server 为 Beaver；GET 响应标题为 `Non-compliance ICP Filing`，内容指向阿里云备案拦截页面。
- `curl.exe https://www.panduolawork.asia/api/health`（连接超时 10 秒、总超时 15 秒）：退出码 35，连接被重置，HTTP 状态 000。
- `curl.exe http://www.panduolawork.asia/api/health`：HTTP 403。
- 远程后端连接尚未通过验收，登录与业务链路未验证。需排查域名备案状态及服务器 HTTPS 配置后重新验收；不能将本地代理配置完成视为远程后端可用。
- 工作区存在其他任务的未提交改动，本次未提交、推送或创建 PR。
