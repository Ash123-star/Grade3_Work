param([switch]$Https)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$backendEnv = Join-Path $repoRoot 'deploy/backend/.env'
if (-not (Test-Path -LiteralPath $backendEnv)) {
    Copy-Item -LiteralPath (Join-Path $repoRoot 'deploy/backend/.env.example') -Destination $backendEnv
    throw '已创建 deploy/backend/.env。填写数据库、Redis、管理员凭据及手机号后重新执行。'
}
# 迁移同项目旧数据库服务时保留卷，先完成构建再停旧服务。
$arguments = @('compose','--env-file',$backendEnv,'-f',(Join-Path $repoRoot 'deploy/backend/compose.yaml'))
if ($Https) { $arguments += @('--profile','https') }
& docker @arguments config --quiet
if ($LASTEXITCODE -ne 0) { throw '后端配置不完整' }
& docker @arguments build
if ($LASTEXITCODE -ne 0) { throw '后端镜像构建失败' }
foreach ($taskService in @('postgres','redis')) {
    $taskLegacy = @(& docker ps -aq --filter 'label=com.docker.compose.project=workpanel-backend' --filter "label=com.docker.compose.service=$taskService")
    foreach ($taskId in $taskLegacy) {
        if (-not $taskId) { continue }
        & docker stop --timeout 60 $taskId | Out-Null
        if ($LASTEXITCODE -ne 0) { throw '旧数据库无法安全停止' }
        & docker rm $taskId | Out-Null
        if ($LASTEXITCODE -ne 0) { throw '旧数据库容器移除失败' }
    }
}
& docker @arguments up --detach --wait --wait-timeout 300
if ($LASTEXITCODE -ne 0) { throw '后端启动失败，请检查 Compose 日志' }
Write-Host '后端已启动。首次登录必须修改管理员密码，然后补齐独立复核人。'
