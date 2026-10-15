$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$deploy = Join-Path $root 'deploy'
$compose = @('compose', '--env-file', (Join-Path $deploy '.env'), '-f', (Join-Path $deploy 'compose.yaml'))
$container = & docker @compose ps -q data
if ($LASTEXITCODE -ne 0 -or !$container) { throw 'Combined data container must be running.' }
function Get-RuntimeState {
    $value = & docker inspect $container --format '{{.RestartCount}} {{.State.Health.Status}} {{.State.Status}}'
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect combined container.' }
    $parts = $value.Split(' ')
    [pscustomobject]@{ Restarts = [int]$parts[0]; Health = $parts[1]; State = $parts[2] }
}
function Wait-Restart([int]$PreviousCount) {
    $deadline = [DateTime]::UtcNow.AddSeconds(120)
    do {
        $state = Get-RuntimeState
        if ($state.Restarts -gt $PreviousCount -and $state.Health -eq 'healthy' -and $state.State -eq 'running') { return }
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $deadline)
    throw 'Child exit did not restart and recover three databases within 120 seconds.'
}
$key = 'collaboration:verification:child-exit:' + [guid]::NewGuid().ToString('N')
$value = [guid]::NewGuid().ToString('N')
$graphMarker = [guid]::NewGuid().ToString('N')
function Invoke-Graph([string]$Cypher) {
    $result = $Cypher | & docker @compose exec -T data sh -c 'exec gosu neo4j /var/lib/neo4j/bin/cypher-shell -u neo4j -p "$NEO4J_PASSWORD" --non-interactive'
    if ($LASTEXITCODE -ne 0) { throw 'Neo4j verification query failed.' }
    return ($result -join "`n")
}
try {
    $reply = & docker @compose exec -T data sh /opt/redis/auth-cli.sh SET $key $value EX 300
    if ($LASTEXITCODE -ne 0 -or $reply -ne 'OK') { throw 'Lifecycle marker SET failed.' }
    Invoke-Graph "CREATE (:LifecycleMarker {id:'$graphMarker'})" | Out-Null
    $initial = Get-RuntimeState
    & docker @compose exec -T data sh /opt/redis/auth-cli.sh shutdown
    if ($LASTEXITCODE -ne 0) { throw 'Cannot stop Redis for lifecycle verification.' }
    Wait-Restart $initial.Restarts
    $afterRedis = Get-RuntimeState
    & docker @compose exec -T data sh -c 'gosu postgres pg_ctl -D "$PGDATA" -m fast stop'
    if ($LASTEXITCODE -ne 0) { throw 'Cannot stop PostgreSQL for lifecycle verification.' }
    Wait-Restart $afterRedis.Restarts
    $afterPostgres = Get-RuntimeState
    & docker @compose exec -T data gosu neo4j /var/lib/neo4j/bin/neo4j stop
    if ($LASTEXITCODE -ne 0) { throw 'Cannot stop Neo4j for lifecycle verification.' }
    Wait-Restart $afterPostgres.Restarts
    $reply = & docker @compose exec -T data sh /opt/redis/auth-cli.sh GET $key
    if ($LASTEXITCODE -ne 0 -or $reply -ne $value) { throw 'Redis marker lost after child process recovery.' }
    if ((Invoke-Graph "MATCH (n:LifecycleMarker {id:'$graphMarker'}) RETURN count(n) AS count") -notmatch '\b1\b') { throw 'Neo4j marker lost after child process recovery.' }
    & docker @compose exec -T data sh /opt/runtime/health.sh
    if ($LASTEXITCODE -ne 0) { throw 'Combined health check failed after lifecycle verification.' }
    $ids = @(& docker @compose ps -q)
    if ($LASTEXITCODE -ne 0 -or $ids.Count -ne 1) { throw 'Expected exactly one running project container.' }
    Write-Host 'Redis, PostgreSQL and Neo4j child exits each restarted and recovered the single container; Redis and Neo4j markers persisted.'
} finally {
    try { Invoke-Graph "MATCH (n:LifecycleMarker {id:'$graphMarker'}) DELETE n" | Out-Null }
    catch { Write-Warning 'Neo4j marker cleanup awaits database recovery.' }
    & docker @compose exec -T data sh /opt/redis/auth-cli.sh DEL $key | Out-Null
}
