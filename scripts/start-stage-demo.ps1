[CmdletBinding()]
param([int]$Port=8080,[switch]$SkipBuild)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$dir=Join-Path $root 'output/stage-demo'
New-Item -ItemType Directory -Path $dir -Force | Out-Null
$envFile=Join-Path $dir 'stage.env'
$java=if($env:JAVA_HOME){Join-Path $env:JAVA_HOME 'bin/java.exe'}else{(Get-Command java -ErrorAction Stop).Source}
if(-not(Test-Path -LiteralPath $java)){throw '需要 JDK 21，并配置 JAVA_HOME。'}
$ErrorActionPreference='Continue'
$version=& $java -version 2>&1 | Out-String
$ErrorActionPreference='Stop'
if($version -notmatch 'version "21[.]'){throw '阶段展示脚本需要 JDK 21。'}
if(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue){throw "端口 $Port 已占用；请先停止原服务或传入 -Port。"}
if(-not(Test-Path -LiteralPath $envFile)) {
    $secret={ [Guid]::NewGuid().ToString('N')+[Guid]::NewGuid().ToString('N') }
    $adminPassword=& $secret
    @("DB_PASSWORD=$(& $secret)","REDIS_PASSWORD=$(& $secret)","NEO4J_PASSWORD=$(& $secret)",
      'ADMIN_ACCOUNT=stage-admin',"ADMIN_PASSWORD=$adminPassword",'ADMIN_PHONE=13900000001',
      'POSTGRES_PORT=55439','REDIS_PORT=56389','NEO4J_BOLT_PORT=57689',"SERVER_PORT=$Port",
      'CORS_ORIGINS=http://localhost:5175,http://127.0.0.1:5175','DEEPSEEK_API_KEY=') |
      Set-Content -LiteralPath $envFile -Encoding ASCII
    @('仅供本机阶段展示；首次登录需要修改密码。','账号：stage-admin',"初始密码：$adminPassword") |
      Set-Content -LiteralPath (Join-Path $dir 'access.txt') -Encoding UTF8
}
Push-Location $root
$saved=@{}
try {
    $ErrorActionPreference='Continue'
    docker image inspect collaboration-data-runtime:local *> $null
    $ErrorActionPreference='Stop'
    if($LASTEXITCODE -ne 0){
        docker build -t collaboration-data-runtime:local -f deploy/runtime/Dockerfile deploy
        if($LASTEXITCODE -ne 0){throw '数据镜像构建失败。'}
    }
    if(-not $SkipBuild){
        $cache=Join-Path $env:USERPROFILE '.m2'
        docker run --rm --volume "${root}:/workspace" --volume "${cache}:/root/.m2" --workdir /workspace maven:3.9.9-eclipse-temurin-21 mvn -B -f server/pom.xml -DskipTests package
        if($LASTEXITCODE -ne 0){throw '后端打包失败。'}
    }
    $sourceJar=Join-Path $root 'server/target/collaboration-server-1.0.0.jar'
    if(-not(Test-Path -LiteralPath $sourceJar)){throw '未找到 JAR；请先运行全套后端测试或去掉 -SkipBuild。'}
    Copy-Item -LiteralPath $sourceJar -Destination (Join-Path $dir 'app.jar') -Force
    docker compose -p pandora-stage -f deploy/backend/compose.yaml --env-file $envFile up -d --wait data
    if($LASTEXITCODE -ne 0){throw '展示数据库未就绪。原开发卷不会被删除。'}
    foreach($line in Get-Content -LiteralPath $envFile){
        if($line -match '^([A-Z_]+)=(.*)$'){
            $key=$Matches[1];$saved[$key]=[Environment]::GetEnvironmentVariable($key,'Process')
            [Environment]::SetEnvironmentVariable($key,$Matches[2],'Process')
        }
    }
    foreach($key in @('DB_URL','DB_USER','REDIS_HOST','REDIS_PORT','NEO4J_URI','SERVER_PORT')){
        if(-not $saved.ContainsKey($key)){$saved[$key]=[Environment]::GetEnvironmentVariable($key,'Process')}
    }
    $env:DB_URL="jdbc:postgresql://127.0.0.1:$env:POSTGRES_PORT/workpanel";$env:DB_USER='workpanel'
    $env:REDIS_HOST='127.0.0.1';$env:NEO4J_URI="bolt://127.0.0.1:$env:NEO4J_BOLT_PORT";$env:SERVER_PORT="$Port"
    $process=Start-Process -FilePath $java -ArgumentList '-Xms64m','-Xmx384m','-XX:+UseSerialGC','-jar',('"'+(Join-Path $dir 'app.jar')+'"') `
        -WorkingDirectory $root -WindowStyle Hidden -RedirectStandardOutput (Join-Path $dir 'api.log') -RedirectStandardError (Join-Path $dir 'api-error.log') -PassThru
    $process.Id | Set-Content -LiteralPath (Join-Path $dir 'api.pid')
    $healthy=$false
    for($attempt=0;$attempt -lt 90;$attempt++){
        if($process.HasExited){throw '后端提前退出；检查 output/stage-demo/api.log。'}
        try{ $null=Invoke-RestMethod "http://127.0.0.1:$Port/api/health" -TimeoutSec 2; $healthy=$true;break }catch{Start-Sleep -Seconds 1}
    }
    if(-not $healthy){throw '后端健康检查超时；保留进程日志供检查。'}
    Write-Output "后端就绪：http://127.0.0.1:$Port/api/docs；PID=$($process.Id)。账号见 output/stage-demo/access.txt。"
    Write-Output '真实 Flutter：在 mobile 中运行 flutter run -d web-server --web-port 5175 --dart-define=USE_MOCK=false（非默认端口需设置 API_BASE_URL）。'
} finally {
    foreach($key in $saved.Keys){[Environment]::SetEnvironmentVariable($key,$saved[$key],'Process')}
    Pop-Location
}
