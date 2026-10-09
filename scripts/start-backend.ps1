param([switch]$Https)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$backendEnv = Join-Path $repoRoot 'deploy/backend/.env'
if (-not (Test-Path -LiteralPath $backendEnv)) {
    Copy-Item -LiteralPath (Join-Path $repoRoot 'deploy/backend/.env.example') -Destination $backendEnv
    throw '已创建 deploy/backend/.env。填写数据库、Redis、管理员凭据及手机号后重新执行。'
}
$arguments = @('compose','--env-file',$backendEnv,'-f',(Join-Path $repoRoot 'deploy/backend/compose.yaml'))
if ($Https) { $arguments += @('--profile','https') }
& docker @arguments up --detach --build --wait
if ($LASTEXITCODE -ne 0) { throw '后端启动失败，请检查 Compose 日志' }
Write-Host '后端已启动。首次登录必须修改管理员密码，然后补齐独立复核人。'
