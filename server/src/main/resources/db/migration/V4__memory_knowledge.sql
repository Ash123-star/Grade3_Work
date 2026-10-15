CREATE TABLE memory_items (
 id text PRIMARY KEY, company_id text NOT NULL REFERENCES companies,
 domain text NOT NULL CHECK(domain IN ('PERSONAL','ORGANIZATION')),
 owner_id text NOT NULL, scope_type text NOT NULL CHECK(scope_type IN ('SELF','TEAM','DEPARTMENT','COMPANY')),
 scope_id text NOT NULL, category text NOT NULL CHECK(category IN ('EXPERIENCE','OUTCOME','GOAL','PREFERENCE','LESSON','SKILL')),
 claim_type text NOT NULL CHECK(claim_type IN ('FACT','OBSERVATION','HYPOTHESIS')),
 status text NOT NULL CHECK(status IN ('CANDIDATE','ACTIVE','DISPUTED','SUPERSEDED','INVALIDATED','DELETED')),
 version int NOT NULL DEFAULT 1, content text NOT NULL,
 source_type text NOT NULL CHECK(source_type IN ('LOG','TASK','ITEM','MANUAL')),
 source_id text NOT NULL, source_version int NOT NULL, locator text NOT NULL,
 provenance text NOT NULL, selection_reason text NOT NULL DEFAULT '',
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(company_id,id), FOREIGN KEY(company_id,owner_id) REFERENCES users(company_id,id),
 CHECK((domain='PERSONAL' AND scope_type='SELF' AND scope_id=owner_id) OR (domain='ORGANIZATION' AND scope_type<>'SELF')),
 UNIQUE(company_id,domain,scope_type,scope_id,source_type,source_id,source_version,locator)
);
CREATE TABLE memory_versions (
 company_id text NOT NULL, memory_id text NOT NULL, version int NOT NULL, content text NOT NULL,
 claim_type text NOT NULL, provenance text NOT NULL, status text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(company_id,memory_id,version),
 FOREIGN KEY(company_id,memory_id) REFERENCES memory_items(company_id,id)
);
CREATE TABLE memory_sources (
 company_id text NOT NULL, memory_id text NOT NULL, memory_version int NOT NULL,
 source_type text NOT NULL, source_id text NOT NULL, source_version int NOT NULL, evidence_locator text NOT NULL,
 PRIMARY KEY(company_id,memory_id,memory_version,source_type,source_id,evidence_locator),
 FOREIGN KEY(company_id,memory_id,memory_version) REFERENCES memory_versions(company_id,memory_id,version)
);
CREATE TABLE memory_relations (
 id text PRIMARY KEY, company_id text NOT NULL, from_id text NOT NULL, to_id text NOT NULL,
 relation_type text NOT NULL DEFAULT 'SUPPORTS_OBSERVATION', status text NOT NULL DEFAULT 'ACTIVE', version int NOT NULL DEFAULT 1,
 UNIQUE(company_id,id), UNIQUE(company_id,from_id,to_id), CHECK(from_id<>to_id),
 FOREIGN KEY(company_id,from_id) REFERENCES memory_items(company_id,id),
 FOREIGN KEY(company_id,to_id) REFERENCES memory_items(company_id,id)
);
CREATE TABLE memory_relation_sources (
 company_id text NOT NULL, relation_id text NOT NULL, memory_id text NOT NULL,
 PRIMARY KEY(company_id,relation_id,memory_id), FOREIGN KEY(company_id,relation_id) REFERENCES memory_relations(company_id,id) ON DELETE CASCADE,
 FOREIGN KEY(company_id,memory_id) REFERENCES memory_items(company_id,id)
);
CREATE TABLE memory_preferences (
 company_id text NOT NULL, owner_id text NOT NULL, explicit_goals text NOT NULL DEFAULT '', response_preferences text NOT NULL DEFAULT '',
 version int NOT NULL DEFAULT 1, PRIMARY KEY(company_id,owner_id), FOREIGN KEY(company_id,owner_id) REFERENCES users(company_id,id)
);
CREATE TABLE memory_exclusions (
 company_id text NOT NULL, actor_id text NOT NULL, domain text NOT NULL, scope_id text NOT NULL,
 source_type text NOT NULL, source_id text NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(company_id,domain,scope_id,source_type,source_id), FOREIGN KEY(company_id,actor_id) REFERENCES users(company_id,id)
);
CREATE TABLE knowledge_chunks (
 id text PRIMARY KEY, company_id text NOT NULL, memory_id text NOT NULL, memory_version int NOT NULL,
 source_type text NOT NULL, source_id text NOT NULL, source_version int NOT NULL, locator text NOT NULL,
 chunk_text text NOT NULL, content_hash text NOT NULL, chunker_version text NOT NULL DEFAULT 'v1',
 search_text tsvector NOT NULL, index_state text NOT NULL DEFAULT 'READY',
 UNIQUE(company_id,id), UNIQUE(company_id,memory_id,memory_version,locator,chunker_version),
 FOREIGN KEY(company_id,memory_id,memory_version) REFERENCES memory_versions(company_id,memory_id,version)
);
CREATE INDEX knowledge_fulltext ON knowledge_chunks USING gin(search_text);
CREATE INDEX memory_scope ON memory_items(company_id,domain,owner_id,status);
CREATE TABLE knowledge_index_jobs (
 id text PRIMARY KEY, company_id text NOT NULL, memory_id text NOT NULL, memory_version int NOT NULL,
 state text NOT NULL DEFAULT 'QUEUED', error text, created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(company_id,memory_id,memory_version), FOREIGN KEY(company_id,memory_id) REFERENCES memory_items(company_id,id)
);
CREATE TABLE memory_projection_state (
 company_id text PRIMARY KEY REFERENCES companies, projected_revision text NOT NULL DEFAULT '', state text NOT NULL DEFAULT 'PENDING', last_error text,
 updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE memory_forget_jobs (
 id text PRIMARY KEY, company_id text NOT NULL, owner_id text NOT NULL, memory_id text NOT NULL,
 state text NOT NULL DEFAULT 'PENDING', error text, created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(company_id,id), FOREIGN KEY(company_id,owner_id) REFERENCES users(company_id,id),
 FOREIGN KEY(company_id,memory_id) REFERENCES memory_items(company_id,id)
);
CREATE TABLE development_analyses (
 id text PRIMARY KEY, company_id text NOT NULL, owner_id text NOT NULL,
 domain text NOT NULL, scope_type text NOT NULL, scope_id text NOT NULL,
 state text NOT NULL DEFAULT 'QUEUED' CHECK(state IN ('QUEUED','RUNNING','SUCCEEDED','FAILED','CANCELLED','STALE')),
 memory_revision text NOT NULL, permission_fingerprint text NOT NULL, input_manifest jsonb NOT NULL DEFAULT '{}',
 output jsonb, error text, tokens int NOT NULL DEFAULT 0, prompt_version text NOT NULL DEFAULT 'development-v1',
 request_key text NOT NULL, request_hash text NOT NULL, created_at timestamptz NOT NULL DEFAULT now(), finished_at timestamptz,
 UNIQUE(company_id,id), UNIQUE(company_id,owner_id,request_key), FOREIGN KEY(company_id,owner_id) REFERENCES users(company_id,id)
);
CREATE TABLE rag_retrieval_runs (
 company_id text NOT NULL, analysis_id text NOT NULL, memory_revision text NOT NULL, index_revision text NOT NULL,
 retriever_version text NOT NULL DEFAULT 'rag-v1', selected_chunk_ids jsonb NOT NULL, source_manifest jsonb NOT NULL, degraded_reason text,
 PRIMARY KEY(company_id,analysis_id), FOREIGN KEY(company_id,analysis_id) REFERENCES development_analyses(company_id,id)
);
CREATE TABLE memory_feedback (
 id text PRIMARY KEY, company_id text NOT NULL, analysis_id text NOT NULL, actor_id text NOT NULL,
 item_key text NOT NULL, type text NOT NULL, comment text NOT NULL DEFAULT '', request_key text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(company_id,actor_id,request_key),
 FOREIGN KEY(company_id,analysis_id) REFERENCES development_analyses(company_id,id), FOREIGN KEY(company_id,actor_id) REFERENCES users(company_id,id)
);
CREATE INDEX development_queue ON development_analyses(created_at) WHERE state='QUEUED';
CREATE TABLE memory_model_calls (
 id text PRIMARY KEY, company_id text NOT NULL, owner_id text NOT NULL, purpose text NOT NULL,
 request_hash text NOT NULL, state text NOT NULL DEFAULT 'RUNNING', tokens int NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(), FOREIGN KEY(company_id,owner_id) REFERENCES users(company_id,id)
);
CREATE TABLE memory_extraction_jobs (
 company_id text NOT NULL, source_type text NOT NULL, source_id text NOT NULL, source_version int NOT NULL,
 owner_id text NOT NULL, state text NOT NULL DEFAULT 'QUEUED', error text,
 PRIMARY KEY(company_id,source_type,source_id,source_version), FOREIGN KEY(company_id,owner_id) REFERENCES users(company_id,id)
);

-- 业务与提取事件同事务提交；草稿不进入队列。消费者和消息投递使用独立类型。
CREATE FUNCTION enqueue_memory_source() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE rowdata jsonb; sourcekind text; own text; sid text; v int; eid text;
BEGIN
 rowdata := to_jsonb(NEW);
 IF TG_TABLE_NAME='daily_logs' THEN
   IF NOT NEW.submitted THEN RETURN NEW; END IF;
   sourcekind := 'LOG'; own := NEW.owner_id; sid := NEW.id; v := NEW.version;
 ELSIF TG_TABLE_NAME='tasks' THEN
   sourcekind := 'TASK'; own := NEW.owner_id; sid := NEW.id; v := NEW.version;
 ELSE
   IF NEW.archived THEN
     UPDATE memory_items SET status='INVALIDATED',updated_at=now() WHERE company_id=NEW.company_id AND source_type='ITEM' AND source_id=NEW.id AND status NOT IN ('DELETED','SUPERSEDED');
     RETURN NEW;
   END IF;
   sourcekind := 'ITEM'; own := NEW.owner_id; sid := NEW.id; v := NEW.version;
 END IF;
 eid := md5(NEW.company_id || ':' || sourcekind || ':' || sid || ':' || v);
 INSERT INTO outbox_events(id,company_id,recipient_id,type,object_id,body,dedup_key)
 VALUES(eid,NEW.company_id,own,'MEMORY_SOURCE',sid,jsonb_build_object('sourceType',sourcekind,'version',v),'memory:' || eid)
 ON CONFLICT(dedup_key) DO NOTHING;
 UPDATE memory_items SET status='SUPERSEDED',updated_at=now()
 WHERE company_id=NEW.company_id AND source_type=sourcekind AND source_id=sid AND source_version<>v AND status NOT IN ('DELETED','SUPERSEDED');
 RETURN NEW;
END $$;
CREATE TRIGGER logs_memory_event AFTER INSERT OR UPDATE OF body,submitted,version ON daily_logs FOR EACH ROW EXECUTE FUNCTION enqueue_memory_source();
CREATE TRIGGER tasks_memory_event AFTER INSERT OR UPDATE OF body,phase,version ON tasks FOR EACH ROW EXECUTE FUNCTION enqueue_memory_source();
CREATE TRIGGER items_memory_event AFTER INSERT OR UPDATE OF body,archived,version ON dashboard_items FOR EACH ROW EXECUTE FUNCTION enqueue_memory_source();
