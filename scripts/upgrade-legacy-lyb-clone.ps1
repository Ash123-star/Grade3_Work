[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9_.-]+$')][string]$SourceContainer,
    [ValidatePattern('^[a-zA-Z0-9_]+$')][string]$SourceDatabase = 'workpanel',
    [ValidatePattern('^[a-zA-Z0-9_]+$')][string]$DatabaseUser = 'workpanel',
    [Parameter(Mandatory)][string]$EnvFile,
    [string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $root 'output/legacy-upgrade' }
$jar = Join-Path $root 'server/target/collaboration-server-1.0.0.jar'
if (-not (Test-Path -LiteralPath $jar)) { throw '先完成后端 clean verify，生成当前 JAR。' }
$passwordLine = Get-Content -LiteralPath $EnvFile | Where-Object { $_ -match '^DB_PASSWORD=' } | Select-Object -First 1
if (-not $passwordLine) { throw '环境文件缺少 DB_PASSWORD。' }
$savedPassword = $env:DB_PASSWORD
$suffix = [Guid]::NewGuid().ToString('N').Substring(0,12)
$clone = "workpanel_lyb_upgrade_$suffix"
$containerDump = "/tmp/lyb-upgrade-$suffix.dump"
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$backup = Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) "$SourceDatabase-$suffix.dump"
try {
    # pg_dump 读源库；后续所有迁移只指向随机生成的新库。不执行 DROP DATABASE、repair 或 down -v。
    docker exec $SourceContainer pg_dump -U $DatabaseUser -d $SourceDatabase -Fc -f $containerDump
    if ($LASTEXITCODE -ne 0) { throw '源库备份失败，未进行转换。' }
    docker cp "${SourceContainer}:$containerDump" $backup
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $backup)) { throw '备份导出失败，未进行转换。' }
    docker exec $SourceContainer createdb -U $DatabaseUser -T template0 $clone
    if ($LASTEXITCODE -ne 0) { throw '独立副本数据库创建失败。' }
    docker exec $SourceContainer pg_restore -U $DatabaseUser -d $clone --exit-on-error $containerDump
    if ($LASTEXITCODE -ne 0) { throw "恢复失败；保留备份和副本 $clone 供检查。" }
    $env:DB_PASSWORD = $passwordLine.Substring('DB_PASSWORD='.Length).Trim().Trim('"').Trim("'")
    docker run --rm --network "container:$SourceContainer" --volume "${root}:/workspace:ro" `
        --env "DB_URL=jdbc:postgresql://127.0.0.1:5432/$clone" --env "DB_USER=$DatabaseUser" --env DB_PASSWORD `
        eclipse-temurin:21-jre-jammy java '-Dloader.main=cn.workpanel.tools.LegacyAuthUpgrade' `
        -cp /workspace/server/target/collaboration-server-1.0.0.jar org.springframework.boot.loader.launch.PropertiesLauncher --restored-clone
    if ($LASTEXITCODE -ne 0) { throw "升级失败；原库未改，备份及副本 $clone 保留。禁止将应用切换到失败副本。" }
    $result = @{ database=$clone; container=$SourceContainer; backup=$backup; backupSha256=(Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash; sourceDatabase=$SourceDatabase }
    $result | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutputDirectory "$clone.json") -Encoding UTF8
    Write-Output "升级验证通过：$clone；备份：$backup。应用的 DB_URL 需显式指向该副本；原库保持不变。"
} finally { $env:DB_PASSWORD=$savedPassword }
