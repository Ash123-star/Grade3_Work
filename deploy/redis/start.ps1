param(
    [string]$ComposeFile = (Join-Path $PSScriptRoot 'compose.yaml'),
    [string]$EnvFile = (Join-Path $PSScriptRoot '.env')
)
$ErrorActionPreference = 'Stop'
& docker compose --env-file $EnvFile -f $ComposeFile up -d --wait --wait-timeout 120 redis
if ($LASTEXITCODE -ne 0) { throw 'Redis startup failed.' }
& (Join-Path $PSScriptRoot 'verify.ps1') -ComposeFile $ComposeFile -EnvFile $EnvFile
