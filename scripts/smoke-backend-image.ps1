param([string]$Image = 'workpanel-backend:local',[switch]$KeepContainers)
$ErrorActionPreference = 'Stop'
$suffix = [Guid]::NewGuid().ToString('N').Substring(0, 10)
$pgName = "workpanel-smoke-pg-$suffix"
$redisName = "workpanel-smoke-redis-$suffix"
$apiName = "workpanel-smoke-api-$suffix"
$networkName = "workpanel-smoke-$suffix"
$smokePassword = [Guid]::NewGuid().ToString('N')
$repoRoot = Split-Path -Parent $PSScriptRoot
try {
    docker network create $networkName | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Smoke network creation failed' }
    docker run --detach --network $networkName --name $pgName --env POSTGRES_DB=workpanel --env POSTGRES_USER=workpanel --env "POSTGRES_PASSWORD=$smokePassword" postgres:16 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Smoke PostgreSQL creation failed' }
    $redisScripts = Join-Path $repoRoot 'deploy/backend/redis'
    docker run --detach --network $networkName --name $redisName --env "REDIS_PASSWORD=$smokePassword" --volume "${redisScripts}:/opt/redis:ro" --entrypoint /bin/sh redis:7-alpine /opt/redis/start.sh | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Smoke Redis creation failed' }
    $ready = $false
    for ($i = 0; $i -lt 30; $i++) {
        docker exec $pgName pg_isready -U workpanel -d workpanel *> $null
        if ($LASTEXITCODE -eq 0) { $ready = $true; break }
        Start-Sleep -Seconds 1
    }
    if (-not $ready) { throw 'Smoke PostgreSQL not ready' }
    docker run --detach --memory 512m --cpus 2 --network $networkName --name $apiName --publish '127.0.0.1::8080' --env "DB_URL=jdbc:postgresql://${pgName}:5432/workpanel" --env DB_USER=workpanel --env "DB_PASSWORD=$smokePassword" --env "REDIS_HOST=$redisName" --env REDIS_PORT=6379 --env "REDIS_PASSWORD=$smokePassword" --env ADMIN_ACCOUNT=smoke-admin --env "ADMIN_PASSWORD=$smokePassword" --env ADMIN_PHONE=13900000001 --env 'JAVA_TOOL_OPTIONS=-Xms32m -Xmx256m -XX:+UseSerialGC -XX:MaxMetaspaceSize=160m -XX:ReservedCodeCacheSize=64m -XX:ActiveProcessorCount=2' $Image | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Smoke API creation failed' }
    $apiPort = (docker port $apiName 8080/tcp).Split(':')[-1]
    $base = "http://127.0.0.1:$apiPort/api"
    $ready = $false
    for ($i = 0; $i -lt 90; $i++) {
        try { $health = Invoke-RestMethod -Uri "$base/health" -TimeoutSec 3; if ($health.status -eq 'UP') { $ready = $true; break } } catch { }
        Start-Sleep -Seconds 1
    }
    if (-not $ready) { docker logs --tail 40 $apiName; throw 'Smoke API not ready' }
    $contract = Invoke-RestMethod -Uri "$base/openapi" -TimeoutSec 10
    if ($contract.servers[0].url -ne '/' -or -not $contract.components.schemas.TaskDraft) { throw "Invalid OpenAPI contract: server=$($contract.servers[0].url), taskSchemaPresent=$($null -ne $contract.components.schemas.TaskDraft)" }
    $login = Invoke-RestMethod -Method Post -Uri "$base/auth/login" -ContentType 'application/json' -Body (@{ account='smoke-admin'; password=$smokePassword } | ConvertTo-Json)
    if (-not $login.user.must_change_password) { throw 'Bootstrap password change not enforced' }
    $headers = @{ Authorization="Bearer $($login.token)" }
    Invoke-RestMethod -Method Post -Uri "$base/auth/password" -Headers $headers -ContentType 'application/json' -Body (@{ oldPassword=$smokePassword; newPassword=($smokePassword+'x') } | ConvertTo-Json) | Out-Null
    $login = Invoke-RestMethod -Method Post -Uri "$base/auth/login" -ContentType 'application/json' -Body (@{ account='smoke-admin'; password=($smokePassword+'x') } | ConvertTo-Json)
    $headers = @{ Authorization="Bearer $($login.token)" }
    $dashboard = Invoke-RestMethod -Uri "$base/dashboard" -Headers $headers
    if (-not $dashboard.canDispatch) { throw 'Admin dashboard failed' }
    # 备份恢复到另一个新库，原 smoke 库不覆盖；测试完成后两者一同清理。
    docker exec $pgName sh -c 'exec pg_dump --username=workpanel --dbname=workpanel --format=custom --file=/tmp/smoke.dump'
    if ($LASTEXITCODE -ne 0) { throw 'Smoke backup failed' }
    docker exec $pgName test -s /tmp/smoke.dump
    if ($LASTEXITCODE -ne 0) { throw 'Smoke backup file missing or empty' }
    docker exec $pgName createdb -U workpanel workpanel_restore
    if ($LASTEXITCODE -ne 0) { throw 'Smoke restore database creation failed' }
    docker exec $pgName pg_restore -U workpanel -d workpanel_restore --no-owner --no-privileges /tmp/smoke.dump
    if ($LASTEXITCODE -ne 0) { throw 'Smoke restore failed' }
    $adminCount = docker exec $pgName psql -U workpanel -d workpanel_restore -tAc "SELECT count(*) FROM users WHERE role='ADMIN'"
    if ($LASTEXITCODE -ne 0 -or $adminCount.Trim() -ne '1') { throw 'Restored admin count mismatch' }
    $contractFile = Join-Path $repoRoot 'docs/openapi.json'
    [IO.File]::WriteAllText($contractFile, ($contract | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
    Write-Host 'PASS: image boot, Flyway, OpenAPI, auth, dashboard, PostgreSQL backup and isolated restore.'
} finally {
    if ($KeepContainers) { Write-Host "Smoke resources retained: $apiName $pgName $redisName $networkName" }
    else {
        docker rm -f $apiName $pgName $redisName 2>$null | Out-Null
        docker network rm $networkName 2>$null | Out-Null
    }
}
