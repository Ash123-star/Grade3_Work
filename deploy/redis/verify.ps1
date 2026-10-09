param(
    [string]$ComposeFile = (Join-Path $PSScriptRoot 'compose.yaml'),
    [string]$EnvFile = (Join-Path $PSScriptRoot '.env'),
    [string]$Service = 'redis'
)
$ErrorActionPreference = 'Stop'
$compose = @('compose', '--env-file', $EnvFile, '-f', $ComposeFile)
$reply = & docker @compose exec -T $Service sh /opt/redis/auth-cli.sh ping
if ($LASTEXITCODE -ne 0 -or $reply -ne 'PONG') { throw 'Authenticated Redis PING failed.' }
$unauthorized = & docker @compose exec -T $Service redis-cli ping
if ($unauthorized -notmatch 'NOAUTH') { throw 'Redis unexpectedly allows anonymous commands.' }
$key = 'collaboration:verification:' + [guid]::NewGuid().ToString('N')
$value = [guid]::NewGuid().ToString('N')
try {
    $reply = & docker @compose exec -T $Service sh /opt/redis/auth-cli.sh SET $key $value EX 120
    if ($LASTEXITCODE -ne 0 -or $reply -ne 'OK') { throw 'Redis SET failed.' }
    $reply = & docker @compose exec -T $Service sh /opt/redis/auth-cli.sh GET $key
    if ($LASTEXITCODE -ne 0 -or $reply -ne $value) { throw 'Redis GET failed.' }
} finally {
    & docker @compose exec -T $Service sh /opt/redis/auth-cli.sh DEL $key | Out-Null
}
Write-Host 'Redis authentication and read/write verified.'
