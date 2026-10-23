[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$FlutterSdk,[switch]$SkipBuild,[switch]$KeepEnvironment,[int]$Port=18083)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$suffix=[Guid]::NewGuid().ToString('N').Substring(0,10)
$name="workpanel-b-live-$suffix"
$dir=Join-Path $root "output/member-b-live-$suffix"
$dart=Join-Path $FlutterSdk 'bin/cache/dart-sdk/bin/dart.exe'
$flutter=Join-Path $FlutterSdk 'bin/cache/flutter_tools.snapshot'
$java=if($env:JAVA_HOME){Join-Path $env:JAVA_HOME 'bin/java.exe'}else{(Get-Command java -ErrorAction Stop).Source}
if(!(Test-Path $dart) -or !(Test-Path $flutter)){throw 'Flutter SDK cache is missing; initialize the installed SDK first.'}
if(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue){throw "Port $Port is occupied; choose another port."}
$variables=@('DB_URL','DB_USER','DB_PASSWORD','REDIS_HOST','REDIS_PORT','REDIS_PASSWORD','NEO4J_URI','NEO4J_PASSWORD','ADMIN_ACCOUNT','ADMIN_PASSWORD','ADMIN_PHONE','SERVER_PORT','DEEPSEEK_API_KEY','AI_WORK_EXECUTION_ENABLED','RUN_STAGE_INTEGRATION','STAGE_DEMO_DIRECTORY')
$saved=@{};foreach($key in $variables){$saved[$key]=[Environment]::GetEnvironmentVariable($key,'Process')}
$process=$null;$created=$false
New-Item -ItemType Directory -Path $dir -Force | Out-Null
Push-Location $root
try{
    if(!$SkipBuild){
        & cmd.exe /d /c 'mvn.cmd -B -f server/pom.xml -DskipTests package 2>&1' *> "$dir/build.log"
        if($LASTEXITCODE -ne 0){throw "Build failed: $dir/build.log"}
    }
    $jar=Join-Path $root 'server/target/collaboration-server-1.0.0.jar'
    if(!(Test-Path $jar)){throw 'No built JAR. Run backend verification or omit SkipBuild.'}
    $password=[Guid]::NewGuid().ToString('N')+[Guid]::NewGuid().ToString('N')
    $redisScripts=Join-Path $root 'deploy/redis'
    docker run -d --name $name -p '127.0.0.1::5432' -p '127.0.0.1::6379' -p '127.0.0.1::7687' --volume "${redisScripts}:/opt/redis:ro" -e POSTGRES_DB=workpanel -e POSTGRES_USER=workpanel -e "POSTGRES_PASSWORD=$password" -e "REDIS_PASSWORD=$password" -e "NEO4J_PASSWORD=$password" collaboration-data-runtime:local | Out-Null
    if($LASTEXITCODE -ne 0){throw 'Isolated data container could not start.'};$created=$true
    $ready=$false
    for($i=0;$i -lt 120;$i++){
        $ErrorActionPreference='Continue'
        docker exec $name sh /opt/runtime/health.sh *> $null
        $ErrorActionPreference='Stop'
        if($LASTEXITCODE -eq 0){$ready=$true;break};Start-Sleep -Seconds 1
    }
    if(!$ready){throw 'Isolated database health timeout.'}
    $pg=(docker port $name 5432/tcp).Split(':')[-1]
    $env:DB_URL="jdbc:postgresql://127.0.0.1:$pg/workpanel";$env:DB_USER='workpanel';$env:DB_PASSWORD=$password
    $env:REDIS_HOST='127.0.0.1';$env:REDIS_PORT=(docker port $name 6379/tcp).Split(':')[-1];$env:REDIS_PASSWORD=$password
    $neo=(docker port $name 7687/tcp).Split(':')[-1];$env:NEO4J_URI="bolt://127.0.0.1:$neo";$env:NEO4J_PASSWORD=$password
    $env:ADMIN_ACCOUNT='b-live-admin';$env:ADMIN_PASSWORD=$password;$env:ADMIN_PHONE='13900000001';$env:SERVER_PORT="$Port"
    $env:DEEPSEEK_API_KEY='';$env:AI_WORK_EXECUTION_ENABLED='false'
    @("SERVER_PORT=$Port","ADMIN_ACCOUNT=b-live-admin","ADMIN_PASSWORD=$password") | Set-Content "$dir/stage.env" -Encoding ASCII
    $process=Start-Process -FilePath $java -ArgumentList '-Xms64m','-Xmx384m','-XX:+UseSerialGC','-jar',('"'+$jar+'"') -WorkingDirectory $root -WindowStyle Hidden -RedirectStandardOutput "$dir/api.log" -RedirectStandardError "$dir/api-error.log" -PassThru
    $process.Id | Set-Content "$dir/api.pid"; $name | Set-Content "$dir/container.txt"
    $ready=$false
    for($i=0;$i -lt 90;$i++){
        if($process.HasExited){throw "API exited: $dir/api.log"}
        try{$null=Invoke-RestMethod "http://127.0.0.1:$Port/api/health" -TimeoutSec 2;$ready=$true;break}catch{Start-Sleep -Seconds 1}
    }
    if(!$ready){throw 'API health timeout.'}
    $env:RUN_STAGE_INTEGRATION='1';$env:STAGE_DEMO_DIRECTORY=$dir
    Push-Location (Join-Path $root 'mobile')
    try{
        foreach($test in @('member_b_real_backend_test','member_b_log_live_test')){
            & $dart $flutter test --no-pub --dart-define=USE_MOCK=false "--dart-define=API_BASE_URL=http://127.0.0.1:$Port/api" "test/$test.dart" --reporter expanded *> "$dir/$test.log"
            if($LASTEXITCODE -ne 0){throw "Real HTTP test failed: $dir/$test.log"}
        }
    }finally{Pop-Location}
    Write-Output "REAL_HTTP_TESTS_PASSED evidence=$dir"
}finally{
    if(!$KeepEnvironment){
        if($process -and !$process.HasExited){Stop-Process -Id $process.Id}
        # Only the randomly named disposable container created by this invocation.
        if($created){docker rm -fv $name | Out-Null}
    }else{Write-Output "Retained isolated environment: $dir"}
    foreach($key in $saved.Keys){[Environment]::SetEnvironmentVariable($key,$saved[$key],'Process')}
    Pop-Location
}
