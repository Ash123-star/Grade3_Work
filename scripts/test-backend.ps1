param([switch]$KeepContainers,[switch]$DockerMaven)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$testSuffix = [Guid]::NewGuid().ToString('N').Substring(0, 10)
$pgName = "workpanel-it-pg-$testSuffix"
$redisName = "workpanel-it-redis-$testSuffix"
$testPassword = [Guid]::NewGuid().ToString('N') + [Guid]::NewGuid().ToString('N')
$variables = @('DB_URL','DB_USER','DB_PASSWORD','REDIS_HOST','REDIS_PORT','REDIS_PASSWORD','MAVEN_OPTS')
$saved = @{}
foreach ($name in $variables) { $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
try {
    docker run --detach --name $pgName --publish '127.0.0.1::5432' --env 'POSTGRES_DB=workpanel_test' --env 'POSTGRES_USER=workpanel' --env "POSTGRES_PASSWORD=$testPassword" postgres:16 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw '测试 PostgreSQL 创建失败' }
    docker run --detach --name $redisName --publish '127.0.0.1::6379' --env "REDIS_PASSWORD=$testPassword" redis:7-alpine sh -c 'exec redis-server --requirepass "$REDIS_PASSWORD"' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw '测试 Redis 创建失败' }
    $pgPort = (docker port $pgName 5432/tcp).Split(':')[-1]
    $redisPort = (docker port $redisName 6379/tcp).Split(':')[-1]
    $ready = $false
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        docker exec $pgName pg_isready -U workpanel -d workpanel_test *> $null
        if ($LASTEXITCODE -eq 0) { $ready = $true; break }
        Start-Sleep -Seconds 1
    }
    if (-not $ready) { throw '测试数据库未就绪' }
    $env:DB_URL = "jdbc:postgresql://127.0.0.1:$pgPort/workpanel_test"
    $env:DB_USER = 'workpanel'
    $env:DB_PASSWORD = $testPassword
    $env:REDIS_HOST = '127.0.0.1'
    $env:REDIS_PORT = $redisPort
    $env:REDIS_PASSWORD = $testPassword
    $env:MAVEN_OPTS = '-Xms32m -Xmx256m -XX:+UseSerialGC -XX:MaxMetaspaceSize=128m -XX:ReservedCodeCacheSize=64m -XX:ActiveProcessorCount=2 -Xss512k'
    Push-Location $repoRoot
    try {
        # 合并 JVM 的诊断 stderr，避免 PowerShell 5 把非失败警告变成终止错误。
        if ($DockerMaven) {
            $env:DB_URL = "jdbc:postgresql://host.docker.internal:$pgPort/workpanel_test"
            $env:REDIS_HOST = 'host.docker.internal'
            $mavenCache = Join-Path $env:USERPROFILE '.m2'
            docker run --rm --memory 1g --cpus 2 --volume "${repoRoot}:/workspace" --volume "${mavenCache}:/root/.m2" --workdir /workspace --env DB_URL --env DB_USER --env DB_PASSWORD --env REDIS_HOST --env REDIS_PORT --env REDIS_PASSWORD --env MAVEN_OPTS maven:3.9.9-eclipse-temurin-21 mvn -B -f server/pom.xml verify
        } else { & cmd.exe /d /c 'mvn.cmd -B -f server/pom.xml verify 2>&1' }
        if ($LASTEXITCODE -ne 0) { throw '后端验证失败，见 server/target/surefire-reports' }
    } finally { Pop-Location }
} finally {
    foreach ($name in $variables) { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
    if (-not $KeepContainers) { docker rm -f $pgName $redisName 2>$null | Out-Null }
    else { Write-Host "保留隔离测试容器：$pgName / $redisName" }
}
