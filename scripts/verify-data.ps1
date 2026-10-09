param([switch]$SkipRestart)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$deploy = Join-Path $root 'deploy'
$composeFile = Join-Path $deploy 'compose.yaml'
$envFile = Join-Path $deploy '.env'
$compose = @('compose', '--env-file', $envFile, '-f', $composeFile)
$postgresContainer = & docker @compose ps -q data
if ($LASTEXITCODE -ne 0 -or !$postgresContainer) { throw 'PostgreSQL must be running.' }
$postgresUser = & docker exec $postgresContainer printenv POSTGRES_USER
$postgresDb = & docker exec $postgresContainer printenv POSTGRES_DB
if ($LASTEXITCODE -ne 0 -or !$postgresDb -or !$postgresUser) { throw 'Cannot read database connection settings.' }
$OutputEncoding = New-Object System.Text.UTF8Encoding($false)
function Invoke-Sql([string]$Database, [string]$Sql) {
    # 捕获预期失败的 stderr 和退出码，测试明确检查失败原因。
    $ErrorActionPreference = 'Continue'
    $reply = $Sql | & docker exec -i $postgresContainer psql -X -qAt -v ON_ERROR_STOP=1 -U $postgresUser -d $Database 2>&1
    $exitCode = $LASTEXITCODE
    [pscustomobject]@{ Code = $exitCode; Text = ($reply | ForEach-Object { "$_" }) -join "`n" }
}
function Assert-SqlSuccess($Result, [string]$Label) {
    if ($Result.Code -ne 0) { throw "$Label failed: $($Result.Text)" }
}
$migration = [IO.File]::ReadAllText((Join-Path $deploy 'postgresql/migrations/V001__initial_schema.sql'))
$baseline = Invoke-Sql $postgresDb 'SELECT count(*) FROM schema_migrations; SELECT count(*) FROM departments; SELECT count(*) FROM roles;'
Assert-SqlSuccess $baseline 'Migration baseline'
if ($baseline.Text.Trim() -ne "1`n3`n5") { throw "Unexpected bootstrap counts: $($baseline.Text)" }
$repeat = Invoke-Sql $postgresDb $migration
Assert-SqlSuccess $repeat 'Repeated migration'
if ($repeat.Text -notmatch 'already applied; skipped') { throw 'Repeated migration was not skipped.' }
$counts = Invoke-Sql $postgresDb 'SELECT count(*) FROM schema_migrations; SELECT count(*) FROM departments; SELECT count(*) FROM roles;'
Assert-SqlSuccess $counts 'Repeated migration counts'
if ($counts.Text -ne $baseline.Text) { throw 'Repeated migration changed seed counts.' }
$drifted = [regex]::Replace($migration, "checksum = '[a-f0-9]{64}'", ("checksum = '" + ('0' * 64) + "'"))
$drift = Invoke-Sql $postgresDb $drifted
if ($drift.Code -eq 0 -or $drift.Text -notmatch 'checksum mismatch') { throw 'Changed applied version was not rejected.' }
$integrity = Invoke-Sql $postgresDb ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'data-integrity.sql')))
Assert-SqlSuccess $integrity 'Business constraints'
Write-Host $integrity.Text

# 创建临时数据库检验首次迁移失败；finally 只删除本次明确创建的测试库。
$testDb = 'verify_migration_' + [guid]::NewGuid().ToString('N')
& docker exec $postgresContainer createdb -U $postgresUser $testDb
if ($LASTEXITCODE -ne 0) { throw 'Cannot create isolated migration test database.' }
try {
    $broken = $migration.Replace('$schema_payload$;', 'SELECT 1 / 0;' + "`n" + '$schema_payload$;')
    $failed = Invoke-Sql $testDb $broken
    if ($failed.Code -eq 0 -or $failed.Text -notmatch 'division by zero') { throw 'Invalid migration unexpectedly succeeded.' }
    $tables = Invoke-Sql $testDb "SELECT count(*) FROM pg_tables WHERE schemaname = 'public';"
    Assert-SqlSuccess $tables 'Rollback inspection'
    if ($tables.Text.Trim() -ne '0') { throw 'Failed migration left partial schema.' }
    $clean = Invoke-Sql $testDb $migration
    Assert-SqlSuccess $clean 'Fresh isolated migration after rollback'
} finally {
    & docker exec $postgresContainer dropdb -U $postgresUser $testDb
    if ($LASTEXITCODE -ne 0) { Write-Warning "Cannot remove temporary test database: $testDb" }
}
Write-Host 'Migration repeat, checksum drift, full rollback and fresh install verified.'
& (Join-Path $deploy 'redis/verify.ps1') -ComposeFile $composeFile -EnvFile $envFile -Service data
if (!$SkipRestart) {
    $key = 'collaboration:verification:persistence:' + [guid]::NewGuid().ToString('N')
    $value = [guid]::NewGuid().ToString('N')
    try {
        $setReply = & docker @compose exec -T data sh /opt/redis/auth-cli.sh SET $key $value EX 300
        if ($LASTEXITCODE -ne 0 -or $setReply -ne 'OK') { throw 'Redis persistence SET failed.' }
        $saved = & docker @compose exec -T data sh /opt/redis/auth-cli.sh SAVE
        if ($LASTEXITCODE -ne 0 -or $saved -ne 'OK') { throw 'Redis snapshot failed.' }
        & docker @compose restart data
        if ($LASTEXITCODE -ne 0) { throw 'Container restart failed.' }
        & docker @compose up -d --wait --wait-timeout 120 data
        if ($LASTEXITCODE -ne 0) { throw 'Restarted services unhealthy.' }
        $reply = & docker @compose exec -T data sh /opt/redis/auth-cli.sh GET $key
        if ($LASTEXITCODE -ne 0 -or $reply -ne $value) { throw 'Redis data did not survive restart.' }
        $persisted = Invoke-Sql $postgresDb 'SELECT count(*) FROM schema_migrations; SELECT count(*) FROM departments; SELECT count(*) FROM roles;'
        Assert-SqlSuccess $persisted 'PostgreSQL restart persistence'
        if ($persisted.Text -ne $baseline.Text) { throw 'PostgreSQL data did not survive restart.' }
    } finally {
        & docker @compose exec -T data sh /opt/redis/auth-cli.sh DEL $key | Out-Null
    }
    Write-Host 'PostgreSQL and Redis restart persistence verified.'
}
& docker @compose ps
if ($LASTEXITCODE -ne 0) { throw 'Docker status check failed.' }
Write-Host 'All data infrastructure checks passed.'
