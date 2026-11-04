[CmdletBinding()]
param([string]$FlutterSdk='D:\flutter',[int]$Port=18089)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$name='workpanel-home-live-'+[Guid]::NewGuid().ToString('N').Substring(0,10)
$dir=Join-Path $root "output/$name"
$variables=@('DB_URL','DB_USER','DB_PASSWORD','REDIS_HOST','REDIS_PORT','REDIS_PASSWORD','NEO4J_URI','NEO4J_PASSWORD','ADMIN_ACCOUNT','ADMIN_PASSWORD','ADMIN_PHONE','SERVER_PORT','JOBS_ENABLED','HOME_LIVE_DIR')
$saved=@{};foreach($key in $variables){$saved[$key]=[Environment]::GetEnvironmentVariable($key,'Process')}
$process=$null;$created=$false
if(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue){throw 'Select an unused port.'}
New-Item -ItemType Directory -Force $dir | Out-Null
Push-Location $root
try {
    & cmd.exe /d /c 'mvn.cmd -B -f server/pom.xml -DskipTests package 2>&1' *> "$dir/build.log"
    if($LASTEXITCODE -ne 0){throw "Package failed: $dir/build.log"}
    $password=[Guid]::NewGuid().ToString('N')+[Guid]::NewGuid().ToString('N')
    $redis=Join-Path $root 'deploy/redis'
    docker run -d --name $name -p '127.0.0.1::5432' -p '127.0.0.1::6379' -p '127.0.0.1::7687' --volume "${redis}:/opt/redis:ro" -e POSTGRES_DB=workpanel -e POSTGRES_USER=workpanel -e "POSTGRES_PASSWORD=$password" -e "REDIS_PASSWORD=$password" -e "NEO4J_PASSWORD=$password" collaboration-data-runtime:local | Out-Null
    if($LASTEXITCODE -ne 0){throw 'Isolated data container failed.'};$created=$true
    $ready=$false
    for($i=0;$i -lt 120;$i++){
        $ErrorActionPreference='Continue';docker exec $name sh /opt/runtime/health.sh *> $null;$ErrorActionPreference='Stop'
        if($LASTEXITCODE -eq 0){$ready=$true;break};Start-Sleep -Seconds 1
    }
    if(!$ready){throw 'Data readiness timeout.'}
    $pg=(docker port $name 5432/tcp).Split(':')[-1]
    $env:DB_URL="jdbc:postgresql://127.0.0.1:$pg/workpanel";$env:DB_USER='workpanel';$env:DB_PASSWORD=$password
    $env:REDIS_HOST='127.0.0.1';$env:REDIS_PORT=(docker port $name 6379/tcp).Split(':')[-1];$env:REDIS_PASSWORD=$password
    $neo=(docker port $name 7687/tcp).Split(':')[-1];$env:NEO4J_URI="bolt://127.0.0.1:$neo";$env:NEO4J_PASSWORD=$password
    $env:ADMIN_ACCOUNT='home-live-admin';$env:ADMIN_PASSWORD=$password;$env:ADMIN_PHONE='13900000001';$env:SERVER_PORT="$Port";$env:JOBS_ENABLED='false'
    $jar=Join-Path $root 'server/target/collaboration-server-1.0.0.jar'
    $process=Start-Process -FilePath (Get-Command java).Source -ArgumentList '-Xms64m','-Xmx384m','-jar',('"'+$jar+'"') -WorkingDirectory $root -WindowStyle Hidden -RedirectStandardOutput "$dir/api.log" -RedirectStandardError "$dir/api-error.log" -PassThru
    $ready=$false
    for($i=0;$i -lt 90;$i++){
        if($process.HasExited){throw "API exited: $dir/api.log"}
        try{$null=Invoke-RestMethod "http://127.0.0.1:$Port/api/health" -TimeoutSec 2;$ready=$true;break}catch{Start-Sleep -Seconds 1}
    }
    if(!$ready){throw 'API readiness timeout.'}
    # Synthetic users reuse the disposable bootstrap password hash; no production accounts.
    $sql=@'
INSERT INTO users(id,company_id,account,password_hash,name,phone,role,status,must_change_password)
SELECT 'home-'||v.who,company_id,'home-'||v.who,password_hash,v.who,'phone-'||v.who,'EMPLOYEE','ACTIVE',false
FROM users CROSS JOIN (VALUES ('alice'),('bob'),('outsider')) AS v(who) WHERE account='home-live-admin';
INSERT INTO tasks(id,company_id,owner_id,issuer_id,title,deadline,body,phase)
SELECT 'home-task-'||n,company_id,'home-alice','home-alice','Shared task '||n,now()+interval '1 day','{}'::jsonb,'DISPATCHED'
FROM users CROSS JOIN generate_series(1,12) AS n WHERE account='home-alice';
INSERT INTO task_participants(task_id,user_id,company_id)
SELECT t.id,u.id,t.company_id FROM tasks t JOIN users u ON u.company_id=t.company_id
WHERE t.id LIKE 'home-task-%' AND u.id IN ('home-alice','home-bob');
'@
    $sql | docker exec -i $name psql -U workpanel -d workpanel -v ON_ERROR_STOP=1 *> "$dir/fixture.log"
    if($LASTEXITCODE -ne 0){throw "Fixture failed: $dir/fixture.log"}
    @{baseUrl="http://127.0.0.1:$Port/api";password=$password} | ConvertTo-Json | Set-Content "$dir/fixture.json" -Encoding UTF8
    Invoke-WebRequest "http://127.0.0.1:$Port/api/openapi" -UseBasicParsing -OutFile 'docs/openapi.json' | Out-Null
    $env:HOME_LIVE_DIR=$dir
    Push-Location (Join-Path $root 'mobile')
    try {
        & (Join-Path $FlutterSdk 'bin/cache/dart-sdk/bin/dart.exe') (Join-Path $FlutterSdk 'bin/cache/flutter_tools.snapshot') test --no-pub test/personal_todos_live_test.dart --reporter expanded *> "$dir/flutter.log"
        if($LASTEXITCODE -ne 0){throw "Live Flutter test failed: $dir/flutter.log"}
    } finally {Pop-Location}
    Write-Output "HOME_LIVE_PASSED evidence=$dir"
} finally {
    if($process -and !$process.HasExited){Stop-Process -Id $process.Id}
    if($created){docker rm -fv $name | Out-Null}
    foreach($key in $saved.Keys){[Environment]::SetEnvironmentVariable($key,$saved[$key],'Process')}
    Pop-Location
}
