-- 恢复库必须保持离线。先导入最新独立 memory_exclusions 账本，再执行本脚本。
-- 此文件不是 Flyway 迁移；保留业务来源，只清理被排除的派生记忆。
BEGIN;
CREATE TEMP TABLE restore_excluded_memories ON COMMIT DROP AS
SELECT m.id, m.company_id, m.owner_id
FROM memory_items m JOIN memory_exclusions e
 ON e.company_id=m.company_id AND e.domain=m.domain AND e.scope_id=m.scope_id
 AND e.source_type=m.source_type AND e.source_id=m.source_id;

UPDATE memory_items m SET status='DELETED',content='',version=version+1,updated_at=now()
FROM restore_excluded_memories x WHERE m.id=x.id AND m.company_id=x.company_id
 AND (m.status<>'DELETED' OR m.content<>'');
UPDATE memory_versions v SET content=''
FROM restore_excluded_memories x WHERE v.company_id=x.company_id AND v.memory_id=x.id;
DELETE FROM knowledge_chunks c USING restore_excluded_memories x
WHERE c.company_id=x.company_id AND c.memory_id=x.id;
UPDATE memory_relations r SET status='DELETED',version=version+1
FROM restore_excluded_memories x WHERE r.company_id=x.company_id
 AND (r.from_id=x.id OR r.to_id=x.id) AND r.status<>'DELETED';
UPDATE development_analyses a SET
 state=CASE WHEN state IN ('QUEUED','RUNNING','SUCCEEDED') THEN 'STALE' ELSE state END,
 output=NULL,input_manifest='{}',error='恢复时重放遗忘记录'
WHERE a.company_id IN (SELECT company_id FROM memory_exclusions);
DELETE FROM rag_retrieval_runs r WHERE r.company_id IN (SELECT company_id FROM memory_exclusions);
INSERT INTO memory_projection_state(company_id,state)
SELECT DISTINCT company_id,'PENDING' FROM memory_exclusions
ON CONFLICT(company_id) DO UPDATE SET state='PENDING';
INSERT INTO memory_forget_jobs(id,company_id,owner_id,memory_id,state)
SELECT md5('restore-forget:'||company_id||':'||id),company_id,owner_id,id,'PENDING'
FROM restore_excluded_memories
ON CONFLICT(id) DO UPDATE SET state='PENDING',error=NULL;
COMMIT;
