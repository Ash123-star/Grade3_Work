param([string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repoRoot 'deploy/backend/backups' }
$backupDir = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
$backendEnv = Join-Path $repoRoot 'deploy/backend/.env'
$composeArgs = @('compose','--env-file',$backendEnv,'-f',(Join-Path $repoRoot 'deploy/backend/compose.yaml'))
$pgContainer = (& docker @composeArgs ps -q postgres).Trim()
if ($LASTEXITCODE -ne 0 -or -not $pgContainer) { throw '后端 PostgreSQL 未运行' }
$backupName = 'workpanel-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.dump'
& docker @composeArgs exec -T postgres sh -c 'exec pg_dump --username=workpanel --dbname=workpanel --format=custom --file=/tmp/workpanel-backup.dump'
if ($LASTEXITCODE -ne 0) { throw '数据库备份失败' }
# docker cp 保持二进制内容，避免 Windows PowerShell 重定向破坏自定义格式。
docker cp "${pgContainer}:/tmp/workpanel-backup.dump" (Join-Path $backupDir $backupName)
if ($LASTEXITCODE -ne 0) { throw '备份下载失败' }
docker exec $pgContainer rm /tmp/workpanel-backup.dump
if ($LASTEXITCODE -ne 0) { throw '临时备份清理失败' }
Write-Host "备份已保存：$(Join-Path $backupDir $backupName)"
