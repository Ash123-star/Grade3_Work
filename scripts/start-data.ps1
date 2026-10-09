param([switch]$SkipBuild)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$deploy = Join-Path $root 'deploy'
$envFile = Join-Path $deploy '.env'
$composeFile = Join-Path $deploy 'compose.yaml'
if (!(Test-Path -LiteralPath $envFile)) {
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $secrets = @()
        for ($i = 0; $i -lt 2; $i++) {
            $bytes = New-Object byte[] 32
            $rng.GetBytes($bytes)
            $secrets += ([BitConverter]::ToString($bytes)).Replace('-', '').ToLowerInvariant()
        }
        $config = [IO.File]::ReadAllText((Join-Path $deploy '.env.example'))
        $config = $config.Replace('replace-with-a-random-secret', $secrets[0])
        $config = $config.Replace('replace-with-a-different-random-secret', $secrets[1])
        [IO.File]::WriteAllText($envFile, $config, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host 'Created private deploy/.env with random credentials.'
    } finally { $rng.Dispose() }
}
if (!$SkipBuild) { & (Join-Path $PSScriptRoot 'build-data-packages.ps1') }
$compose = @('compose', '--env-file', $envFile, '-f', $composeFile)
& docker @compose config --quiet
if ($LASTEXITCODE -ne 0) { throw 'Invalid Docker Compose configuration.' }
& docker @compose build data
if ($LASTEXITCODE -ne 0) { throw 'Combined database image build failed.' }
# 只清理同一 Compose 项目下的旧两个组件容器，保留全部数据卷。
$projectNames = & docker @compose config --format json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or !$projectNames.name) { throw 'Cannot resolve Compose project name.' }
$legacyIds = @(& docker ps -aq --filter "label=com.docker.compose.project=$($projectNames.name)" --filter 'label=com.docker.compose.service=postgres')
$legacyIds += @(& docker ps -aq --filter "label=com.docker.compose.project=$($projectNames.name)" --filter 'label=com.docker.compose.service=redis')
foreach ($legacyId in $legacyIds) {
    if (!$legacyId) { continue }
    & docker stop --timeout 60 $legacyId
    if ($LASTEXITCODE -ne 0) { throw 'Cannot safely stop legacy database container.' }
    & docker rm $legacyId
    if ($LASTEXITCODE -ne 0) { throw 'Cannot remove stopped legacy container.' }
}
& docker @compose up -d --wait --wait-timeout 120 data
if ($LASTEXITCODE -ne 0) { throw 'Combined database startup failed.' }
& (Join-Path $deploy 'postgresql/migrate.ps1') -ComposeFile $composeFile -EnvFile $envFile -Service data
& (Join-Path $deploy 'redis/verify.ps1') -ComposeFile $composeFile -EnvFile $envFile -Service data
& docker @compose ps
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect Docker services.' }
Write-Host 'PostgreSQL migration complete; PostgreSQL and Redis running in one container.'
