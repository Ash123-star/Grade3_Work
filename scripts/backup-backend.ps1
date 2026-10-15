param([string]$OutputDirectory,[switch]$JournalOnly,[string]$Container,[string]$Database='workpanel',[string]$DatabaseUser='workpanel')
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repoRoot 'deploy/backend/backups' }
$backupDir = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
if ($Database -notmatch '^[a-zA-Z_][a-zA-Z0-9_]*$' -or $DatabaseUser -notmatch '^[a-zA-Z_][a-zA-Z0-9_]*$') { throw '数据库及用户名称格式无效' }
if ($Container) { $pgContainer = $Container }
else {
    $backendEnv = Join-Path $repoRoot 'deploy/backend/.env'
    $composeArgs = @('compose','--env-file',$backendEnv,'-f',(Join-Path $repoRoot 'deploy/backend/compose.yaml'))
    $pgContainer = (& docker @composeArgs ps -q data | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $pgContainer) { throw '后端 PostgreSQL 未运行' }
}
$suffix = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)
if (-not $JournalOnly) {
    $backupName = "workpanel-$suffix.dump"
    $remoteDump = "/tmp/workpanel-$suffix.dump"
    docker exec $pgContainer pg_dump --username=$DatabaseUser --dbname=$Database --format=custom --file=$remoteDump
    if ($LASTEXITCODE -ne 0) { throw '数据库备份失败' }
    # docker cp 保持二进制内容，避免 Windows PowerShell 重定向破坏自定义格式。
    docker cp "${pgContainer}:$remoteDump" (Join-Path $backupDir $backupName)
    if ($LASTEXITCODE -ne 0) { throw '备份下载失败' }
    docker exec $pgContainer rm $remoteDump
    if ($LASTEXITCODE -ne 0) { throw '临时备份清理失败' }
    Write-Host "备份已保存：$(Join-Path $backupDir $backupName)"
}
# 账本独立于历史备份，遗忘后可用 -JournalOnly 导出最新排除记录。
$journalSql = docker exec $pgContainer psql --username=$DatabaseUser --dbname=$Database -v ON_ERROR_STOP=1 -At -c "SELECT format('INSERT INTO memory_exclusions(company_id,actor_id,domain,scope_id,source_type,source_id) VALUES (%L,%L,%L,%L,%L,%L) ON CONFLICT DO NOTHING;',company_id,actor_id,domain,scope_id,source_type,source_id) FROM memory_exclusions ORDER BY company_id,domain,scope_id,source_type,source_id;"
if ($LASTEXITCODE -ne 0) { throw '独立遗忘账本导出失败' }
$journalPath = Join-Path $backupDir "ai-forget-journal-$suffix.sql"
[IO.File]::WriteAllText($journalPath,(($journalSql -join "`n") + "`n"),[Text.UTF8Encoding]::new($false))
Write-Host "独立遗忘账本已保存：$journalPath"
Write-Output $journalPath
