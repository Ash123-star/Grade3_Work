param([Parameter(Mandatory=$true)][string]$Container)
$ErrorActionPreference = 'Stop'
if ($Container -notmatch '^workpanel-it-data-[a-f0-9]{10}$') { throw '仅允许隔离的 workpanel-it-data 测试容器' }
$containerInfo = docker inspect $Container --format '{{.Config.Image}} {{.State.Running}}'
if ($LASTEXITCODE -ne 0 -or $containerInfo -ne 'collaboration-data-runtime:local true') { throw '隔离测试容器未运行或镜像不符' }
$root = Split-Path -Parent $PSScriptRoot
$memoryId = [guid]::NewGuid().ToString()
$chunkId = [guid]::NewGuid().ToString()
$rebuildId = [guid]::NewGuid().ToString()
$restoreDb = 'workpanel_restore_' + [guid]::NewGuid().ToString('N').Substring(0,8)
$journalDir = Join-Path $root 'deploy/backend/backups'
New-Item -ItemType Directory -Force -Path $journalDir | Out-Null
function Invoke-Sql([string]$Database,[string]$Sql) {
    $result = $Sql | docker exec -i $Container psql -U workpanel -d $Database -v ON_ERROR_STOP=1 -At
    if ($LASTEXITCODE -ne 0) { throw "PostgreSQL 验证失败：$Database" }
    return ($result -join "`n")
}
function Invoke-Graph([string]$Cypher) {
    $result = $Cypher | docker exec -i $Container sh -c 'exec gosu neo4j /var/lib/neo4j/bin/cypher-shell -u neo4j -p "$NEO4J_PASSWORD" --non-interactive'
    if ($LASTEXITCODE -ne 0) { throw 'Neo4j 验证失败' }
    return ($result -join "`n")
}
try {
    Invoke-Sql 'workpanel_test' @"
INSERT INTO memory_items(id,company_id,domain,owner_id,scope_type,scope_id,category,claim_type,status,content,source_type,source_id,source_version,locator,provenance)
SELECT '$memoryId',company_id,'PERSONAL',id,'SELF',id,'EXPERIENCE','FACT','ACTIVE','恢复演练旧记忆','MANUAL','$memoryId',1,'self','SELF_REPORTED' FROM users WHERE account='alice' LIMIT 1;
INSERT INTO memory_versions(company_id,memory_id,version,content,claim_type,provenance,status)
SELECT company_id,id,version,content,claim_type,provenance,status FROM memory_items WHERE id='$memoryId';
INSERT INTO knowledge_chunks(id,company_id,memory_id,memory_version,source_type,source_id,source_version,locator,chunk_text,content_hash,chunker_version,search_text)
SELECT '$chunkId',m.company_id,m.id,m.version,m.source_type,m.source_id,m.source_version,'self:0',m.content,md5(m.content),s.active_version,to_tsvector('simple',m.content)
FROM memory_items m JOIN knowledge_index_state s ON s.company_id=m.company_id WHERE m.id='$memoryId';
"@ | Out-Null
    if ((Invoke-Sql 'workpanel_test' "SELECT count(*) FROM knowledge_chunks WHERE memory_id='$memoryId';").Trim() -ne '1') { throw '备份前合成片段未写入' }
    docker exec $Container pg_dump -U workpanel -d workpanel_test --format=custom --file=/tmp/workpanel-before-forget.dump
    if ($LASTEXITCODE -ne 0) { throw '备份失败' }
    Invoke-Sql 'workpanel_test' @"
INSERT INTO memory_exclusions(company_id,actor_id,domain,scope_id,source_type,source_id)
SELECT company_id,owner_id,domain,scope_id,source_type,source_id FROM memory_items WHERE id='$memoryId';
UPDATE memory_items SET status='DELETED',content='',version=version+1 WHERE id='$memoryId';
DELETE FROM knowledge_chunks WHERE memory_id='$memoryId';
"@ | Out-Null
    $journalPath = & (Join-Path $PSScriptRoot 'backup-backend.ps1') -Container $Container -Database workpanel_test -JournalOnly -OutputDirectory $journalDir
    if ([string]::IsNullOrWhiteSpace($journalPath) -or -not (Test-Path -LiteralPath $journalPath -PathType Leaf)) { throw '删除账本导出失败' }
    docker exec $Container createdb -U workpanel $restoreDb
    if ($LASTEXITCODE -ne 0) { throw '恢复库创建失败' }
    docker exec $Container pg_restore -U workpanel -d $restoreDb --no-owner --no-privileges /tmp/workpanel-before-forget.dump
    if ($LASTEXITCODE -ne 0) { throw '旧备份恢复失败' }
    if ((Invoke-Sql $restoreDb "SELECT status FROM memory_items WHERE id='$memoryId';").Trim() -ne 'ACTIVE') { throw '旧备份基线无效' }
    if ((Invoke-Sql $restoreDb "SELECT count(*) FROM knowledge_chunks WHERE memory_id='$memoryId';").Trim() -ne '1') { throw '旧备份缺少原始片段' }
    # 排除记录是备份之后的独立删除账本；开放读流量前先重放。
    Invoke-Sql $restoreDb ([IO.File]::ReadAllText($journalPath,[Text.Encoding]::UTF8)) | Out-Null
    $replaySql = [IO.File]::ReadAllText((Join-Path $root 'deploy/backend/replay-ai-forget.sql'),[Text.Encoding]::UTF8)
    Invoke-Sql $restoreDb $replaySql | Out-Null
    $deletedVersion = (Invoke-Sql $restoreDb "SELECT version FROM memory_items WHERE id='$memoryId';").Trim()
    Invoke-Sql $restoreDb $replaySql | Out-Null
    if ((Invoke-Sql $restoreDb "SELECT version FROM memory_items WHERE id='$memoryId';").Trim() -ne $deletedVersion) { throw '重复重放不幂等' }
    Invoke-Sql $restoreDb @"
INSERT INTO knowledge_rebuild_jobs(id,company_id,request_key,target_version,state)
SELECT '$rebuildId',id,'restore-rehearsal','v2:$rebuildId','BUILDING' FROM companies WHERE id=(SELECT company_id FROM memory_items WHERE id='$memoryId');
UPDATE knowledge_index_state SET building_version='v2:$rebuildId',rebuild_id='$rebuildId',cursor_id='',scan_done=false,state='BUILDING'
WHERE company_id=(SELECT company_id FROM memory_items WHERE id='$memoryId');
"@ | Out-Null
    Invoke-Graph 'MATCH (m:Memory) DETACH DELETE m' | Out-Null
    docker cp (Join-Path $root 'server/target/collaboration-server-1.0.0.jar') "${Container}:/tmp/restore-rehearsal.jar"
    if ($LASTEXITCODE -ne 0) { throw '恢复服务 JAR 复制失败' }
    $launchPath = Join-Path $journalDir 'restore-rehearsal-start.sh'
    $launch = @'
#!/bin/sh
export DB_URL="jdbc:postgresql://127.0.0.1:5432/__RESTORE_DB__"
export DB_USER=workpanel DB_PASSWORD="$POSTGRES_PASSWORD"
export REDIS_HOST=127.0.0.1 REDIS_PORT=6379 REDIS_PASSWORD="$REDIS_PASSWORD"
export NEO4J_URI=bolt://127.0.0.1:7687 NEO4J_PASSWORD="$NEO4J_PASSWORD"
export SERVER_PORT=18091 AI_MEMORY_EXTRACT_ENABLED=false
export JAVA_TOOL_OPTIONS="-Xmx256m -XX:+UseSerialGC"
echo $$ >/tmp/restore-rehearsal.pid
exec java -jar /tmp/restore-rehearsal.jar >/tmp/restore-rehearsal.log 2>&1
'@
    [IO.File]::WriteAllText($launchPath,($launch.Replace('__RESTORE_DB__',$restoreDb).Replace("`r`n","`n")),[Text.UTF8Encoding]::new($false))
    docker cp $launchPath "${Container}:/tmp/restore-rehearsal-start.sh"
    if ($LASTEXITCODE -ne 0) { throw '恢复启动脚本复制失败' }
    docker exec -d $Container sh /tmp/restore-rehearsal-start.sh
    if ($LASTEXITCODE -ne 0) { throw '恢复服务启动失败' }
    $ready = $false
    for ($attempt=0; $attempt -lt 90; $attempt++) {
        Start-Sleep -Seconds 2
        $indexState = (Invoke-Sql $restoreDb "SELECT state FROM knowledge_rebuild_jobs WHERE id='$rebuildId';").Trim()
        $projectionState = (Invoke-Sql $restoreDb "SELECT state FROM memory_projection_state WHERE company_id=(SELECT company_id FROM memory_items WHERE id='$memoryId');").Trim()
        if ($indexState -eq 'SUCCEEDED' -and $projectionState -eq 'READY') { $ready = $true; break }
    }
    if (-not $ready) { throw '恢复后索引或图投影未完成' }
    if ((Invoke-Sql $restoreDb "SELECT count(*) FROM memory_items WHERE id='$memoryId' AND status='DELETED' AND content='';").Trim() -ne '1') { throw '遗忘记录未重放' }
    if ((Invoke-Sql $restoreDb "SELECT count(*) FROM knowledge_chunks WHERE memory_id='$memoryId';").Trim() -ne '0') { throw '旧片段被复活' }
    if ((Invoke-Sql $restoreDb "SELECT count(*) FROM knowledge_chunks WHERE chunker_version='v2:$rebuildId';").Trim() -eq '0') { throw '知识库未重建' }
    $graph = Invoke-Graph "MATCH (m:Memory {id:'$memoryId'}) RETURN m.status AS status,m.version AS version"
    if ($graph -notmatch 'DELETED') { throw '图墓碑未恢复' }
    Write-Host '旧备份恢复、删除账本重放、索引切换和 Neo4j 墓碑重建通过。'
} finally {
    $ErrorActionPreference = 'Continue'
    $servicePid = docker exec $Container cat /tmp/restore-rehearsal.pid 2>$null
    if ($LASTEXITCODE -eq 0 -and $servicePid -match '^[0-9]+$') { docker exec $Container kill $servicePid 2>$null | Out-Null }
}
