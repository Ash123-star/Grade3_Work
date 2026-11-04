param([switch]$KeepContainers,[switch]$DockerMaven)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$testSuffix = [Guid]::NewGuid().ToString('N').Substring(0, 10)
$dataName = "workpanel-it-data-$testSuffix"
$testPassword = [Guid]::NewGuid().ToString('N') + [Guid]::NewGuid().ToString('N')
$variables = @('DB_URL','DB_USER','DB_PASSWORD','REDIS_HOST','REDIS_PORT','REDIS_PASSWORD','NEO4J_URI','NEO4J_PASSWORD','MAVEN_OPTS')
$saved = @{}
foreach ($name in $variables) { $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
try {
    $redisScripts = Join-Path $repoRoot 'deploy/redis'
    docker run --detach --name $dataName --publish '127.0.0.1::5432' --publish '127.0.0.1::6379' --publish '127.0.0.1::7687' --env 'POSTGRES_DB=workpanel_test' --env 'POSTGRES_USER=workpanel' --env "POSTGRES_PASSWORD=$testPassword" --env "REDIS_PASSWORD=$testPassword" --env "NEO4J_PASSWORD=$testPassword" --volume "${redisScripts}:/opt/redis:ro" collaboration-data-runtime:local | Out-Null
    if ($LASTEXITCODE -ne 0) { throw '统一测试数据库容器创建失败；请先构建 data 镜像' }
    $pgPort = (docker port $dataName 5432/tcp).Split(':')[-1]
    $redisPort = (docker port $dataName 6379/tcp).Split(':')[-1]
    $neoPort = (docker port $dataName 7687/tcp).Split(':')[-1]
    $ready = $false
    for ($attempt = 0; $attempt -lt 120; $attempt++) {
        $ErrorActionPreference = 'Continue'
        docker exec $dataName sh /opt/runtime/health.sh *> $null
        $ErrorActionPreference = 'Stop'
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
    $env:NEO4J_URI = "bolt://127.0.0.1:$neoPort"
    $env:NEO4J_PASSWORD = $testPassword
    $env:MAVEN_OPTS = '-Xms32m -Xmx256m -XX:+UseSerialGC -XX:MaxMetaspaceSize=128m -XX:ReservedCodeCacheSize=64m -XX:ActiveProcessorCount=2 -Xss512k'
    Push-Location $repoRoot
    try {
        # 合并 JVM 的诊断 stderr，避免 PowerShell 5 把非失败警告变成终止错误。
        if ($DockerMaven) {
            $env:DB_URL = "jdbc:postgresql://host.docker.internal:$pgPort/workpanel_test"
            $env:REDIS_HOST = 'host.docker.internal'
            $env:NEO4J_URI = "bolt://host.docker.internal:$neoPort"
            $mavenCache = Join-Path $env:USERPROFILE '.m2'
            # PowerShell 5 的 NativeCommandError 不代表进程失败；以 Maven 退出码为准。
            $ErrorActionPreference = 'Continue'
            docker run --rm --memory 1g --cpus 2 --volume "${repoRoot}:/workspace" --volume "${mavenCache}:/root/.m2" --workdir /workspace --env DB_URL --env DB_USER --env DB_PASSWORD --env REDIS_HOST --env REDIS_PORT --env REDIS_PASSWORD --env NEO4J_URI --env NEO4J_PASSWORD --env MAVEN_OPTS maven:3.9.9-eclipse-temurin-21 mvn -B -f server/pom.xml clean verify
            $mavenExit = $LASTEXITCODE
            $ErrorActionPreference = 'Stop'
        } else { & cmd.exe /d /c 'mvn.cmd -B -f server/pom.xml clean verify 2>&1'; $mavenExit = $LASTEXITCODE }
        if ($mavenExit -ne 0) { throw '后端验证失败，见 server/target/surefire-reports' }
    } finally { Pop-Location }
} finally {
    foreach ($name in $variables) { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
    if (-not $KeepContainers) { docker rm -fv $dataName 2>$null | Out-Null }
    else { Write-Host "保留隔离测试容器：$dataName" }
}
