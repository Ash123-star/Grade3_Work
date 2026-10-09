param(
    [string]$ComposeFile = (Join-Path $PSScriptRoot 'compose.yaml'),
    [string]$EnvFile = (Join-Path $PSScriptRoot '.env'),
    [string]$Service = 'postgres'
)
$ErrorActionPreference = 'Stop'
$compose = @('compose', '--env-file', $EnvFile, '-f', $ComposeFile)
if (!(Test-Path -LiteralPath $EnvFile)) { throw 'Create a private .env before running migrations.' }
$migrations = @(Get-ChildItem (Join-Path $PSScriptRoot 'migrations') -Filter 'V*.sql' | Sort-Object Name)
if ($migrations.Count -eq 0) { throw 'No migration files found. Run scripts/build-data-packages.ps1.' }
foreach ($migration in $migrations) {
    # 使用容器环境变量；不输出密码。不依赖 initdb 首次启动机制。
    & docker @compose exec -T $Service sh -c 'exec psql -X -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f "$1"' -- "/migrations/$($migration.Name)"
    if ($LASTEXITCODE -ne 0) { throw "Migration failed: $($migration.Name)" }
}
