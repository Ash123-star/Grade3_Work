-- 自动办理只增加独立存储，历史 AI 作业和正式业务不自动迁移/执行。
ALTER TABLE attachments ADD CONSTRAINT attachments_company_id_id_key UNIQUE(company_id,id);
ALTER TABLE attachments ADD COLUMN file_hash text;
ALTER TABLE attachments ADD COLUMN detected_type text;
ALTER TABLE attachments ADD COLUMN expires_at timestamptz;
ALTER TABLE task_events ADD CONSTRAINT task_events_company_sequence UNIQUE(company_id,task_id,sequence);
CREATE TABLE ai_work_items (
 id text PRIMARY KEY, company_id text NOT NULL, owner_id text NOT NULL,
 state text NOT NULL DEFAULT 'QUEUED' CHECK(state IN ('QUEUED','PREPARING','READY','EXECUTING','SUCCEEDED','WAITING_INPUT','WAITING_CONFIRMATION','WAITING_REVIEW','PARTIAL','FAILED','RECONCILING','CANCEL_REQUESTED','CANCELLED')),
 title text NOT NULL DEFAULT '新的事项', version int NOT NULL DEFAULT 1 CHECK(version>0), plan_version int NOT NULL DEFAULT 0 CHECK(plan_version>=0),
 result jsonb NOT NULL DEFAULT '{}', error_code text, deleted_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(company_id,id), FOREIGN KEY(company_id,owner_id) REFERENCES users(company_id,id)
);
CREATE INDEX ai_work_owner ON ai_work_items(company_id,owner_id,updated_at DESC,id) WHERE deleted_at IS NULL;
CREATE TABLE ai_work_messages (
 id text PRIMARY KEY, company_id text NOT NULL, work_id text NOT NULL, sequence int NOT NULL CHECK(sequence>0),
 body jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(company_id,work_id,sequence),
 FOREIGN KEY(company_id,work_id) REFERENCES ai_work_items(company_id,id)
);
CREATE TABLE ai_work_plans (
 company_id text NOT NULL, work_id text NOT NULL, version int NOT NULL CHECK(version>0),
 body jsonb NOT NULL, hash text NOT NULL, permission_fingerprint text NOT NULL, expires_at timestamptz NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(company_id,work_id,version),
 FOREIGN KEY(company_id,work_id) REFERENCES ai_work_items(company_id,id)
);
CREATE TABLE ai_work_steps (
 id text PRIMARY KEY, company_id text NOT NULL, work_id text NOT NULL, plan_version int NOT NULL, step_key text NOT NULL,
 action text NOT NULL, payload jsonb NOT NULL DEFAULT '{}', dependencies jsonb NOT NULL DEFAULT '[]',
 state text NOT NULL DEFAULT 'PENDING' CHECK(state IN ('PENDING','RUNNING','SUCCEEDED','WAITING','FAILED','SKIPPED','CANCELLED','UNKNOWN')),
 lease_until timestamptz, fence bigint NOT NULL DEFAULT 0, attempts int NOT NULL DEFAULT 0,
 next_run_at timestamptz NOT NULL DEFAULT now(), result jsonb NOT NULL DEFAULT '{}', error_code text,
 UNIQUE(company_id,work_id,plan_version,step_key), FOREIGN KEY(company_id,work_id) REFERENCES ai_work_items(company_id,id)
);
CREATE INDEX ai_work_queue ON ai_work_steps(next_run_at,id) WHERE state IN ('PENDING','RUNNING');
CREATE TABLE ai_action_receipts (
 company_id text NOT NULL, actor_id text NOT NULL, work_id text NOT NULL, plan_version int NOT NULL, step_key text NOT NULL,
 request_hash text NOT NULL, result jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(company_id,actor_id,work_id,plan_version,step_key),
 FOREIGN KEY(company_id,actor_id) REFERENCES users(company_id,id), FOREIGN KEY(company_id,work_id) REFERENCES ai_work_items(company_id,id)
);
CREATE TABLE ai_work_events (
 sequence bigserial PRIMARY KEY, company_id text NOT NULL, work_id text NOT NULL, version int NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(), FOREIGN KEY(company_id,work_id) REFERENCES ai_work_items(company_id,id)
);
CREATE INDEX ai_work_event_replay ON ai_work_events(company_id,work_id,sequence);
CREATE TABLE ai_request_keys (
 company_id text NOT NULL, actor_id text NOT NULL, operation text NOT NULL, key text NOT NULL,
 request_hash text NOT NULL, result jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(company_id,actor_id,operation,key), FOREIGN KEY(company_id,actor_id) REFERENCES users(company_id,id)
);
CREATE TABLE ai_work_authorizations (
 id text PRIMARY KEY, company_id text NOT NULL, owner_id text NOT NULL, action text NOT NULL CHECK(action IN ('CREATE_TASK','SUBMIT_DELIVERY')),
 scope jsonb NOT NULL, expires_at timestamptz NOT NULL, revoked_at timestamptz, version int NOT NULL DEFAULT 1 CHECK(version>0),
 created_at timestamptz NOT NULL DEFAULT now(), FOREIGN KEY(company_id,owner_id) REFERENCES users(company_id,id)
);
CREATE TABLE ai_work_confirmations (
 id text PRIMARY KEY, company_id text NOT NULL, work_id text NOT NULL, plan_version int NOT NULL,
 plan_hash text NOT NULL, consumed_at timestamptz, expires_at timestamptz NOT NULL,
 FOREIGN KEY(company_id,work_id,plan_version) REFERENCES ai_work_plans(company_id,work_id,version)
);
CREATE TABLE ai_file_extractions (
 id text PRIMARY KEY, company_id text NOT NULL, owner_id text NOT NULL, attachment_id text NOT NULL,
 file_hash text NOT NULL, parser_version text NOT NULL, body jsonb NOT NULL, expires_at timestamptz NOT NULL DEFAULT now()+interval '7 days',
 UNIQUE(company_id,owner_id,attachment_id,file_hash,parser_version),
 FOREIGN KEY(company_id,owner_id) REFERENCES users(company_id,id), FOREIGN KEY(company_id,attachment_id) REFERENCES attachments(company_id,id)
);
CREATE TABLE procedure_documents (
 id text PRIMARY KEY, company_id text NOT NULL, owner_id text NOT NULL, type text NOT NULL CHECK(type IN ('POLICY','PROCEDURE','TEMPLATE')),
 title text NOT NULL, scope_kind text NOT NULL CHECK(scope_kind IN ('COMPANY','DEPARTMENT','TEAM')), scope_id text,
 version int NOT NULL DEFAULT 1 CHECK(version>0), active_version int, state text NOT NULL DEFAULT 'DRAFT' CHECK(state IN ('DRAFT','PUBLISHED','WITHDRAWN')),
 created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(company_id,id),
 FOREIGN KEY(company_id,owner_id) REFERENCES users(company_id,id)
);
CREATE TABLE procedure_versions (
 company_id text NOT NULL, document_id text NOT NULL, version int NOT NULL CHECK(version>0), body jsonb NOT NULL,
 effective_from timestamptz NOT NULL DEFAULT now(), effective_to timestamptz, created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(company_id,document_id,version), FOREIGN KEY(company_id,document_id) REFERENCES procedure_documents(company_id,id),
 CHECK(effective_to IS NULL OR effective_to>effective_from)
);
CREATE TABLE procedure_chunks (
 company_id text NOT NULL, document_id text NOT NULL, version int NOT NULL, locator text NOT NULL, content text NOT NULL,
 search_text tsvector GENERATED ALWAYS AS (to_tsvector('simple',content)) STORED,
 PRIMARY KEY(company_id,document_id,version,locator), FOREIGN KEY(company_id,document_id,version) REFERENCES procedure_versions(company_id,document_id,version)
);
CREATE INDEX procedure_search ON procedure_chunks USING gin(search_text);
CREATE TABLE task_acceptance_items (
 company_id text NOT NULL, task_id text NOT NULL, version int NOT NULL CHECK(version>0), item_id text NOT NULL,
 body jsonb NOT NULL, PRIMARY KEY(company_id,task_id,version,item_id), FOREIGN KEY(company_id,task_id) REFERENCES tasks(company_id,id)
);
CREATE TABLE task_delivery_checks (
 id text PRIMARY KEY, company_id text NOT NULL, task_id text NOT NULL, owner_id text NOT NULL,
 version int NOT NULL DEFAULT 1, task_version int NOT NULL, fingerprint text NOT NULL,
 state text NOT NULL CHECK(state IN ('PASS','NEEDS_FIX','UNVERIFIABLE')), manifest jsonb NOT NULL, body jsonb NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(company_id,id),
 FOREIGN KEY(company_id,task_id) REFERENCES tasks(company_id,id), FOREIGN KEY(company_id,owner_id) REFERENCES users(company_id,id)
);
CREATE TABLE task_delivery_findings (
 company_id text NOT NULL, check_id text NOT NULL, position int NOT NULL, body jsonb NOT NULL,
 PRIMARY KEY(company_id,check_id,position), FOREIGN KEY(company_id,check_id) REFERENCES task_delivery_checks(company_id,id)
);
CREATE TABLE task_deliveries (
 id text PRIMARY KEY, company_id text NOT NULL, task_id text NOT NULL, actor_id text NOT NULL, check_id text NOT NULL,
 event_sequence bigint NOT NULL, mode text NOT NULL CHECK(mode IN ('CHECKED','MANUAL')),
 text text NOT NULL, created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(company_id,id),
 FOREIGN KEY(company_id,task_id) REFERENCES tasks(company_id,id), FOREIGN KEY(company_id,check_id) REFERENCES task_delivery_checks(company_id,id),
 FOREIGN KEY(company_id,actor_id) REFERENCES users(company_id,id),
 FOREIGN KEY(company_id,task_id,event_sequence) REFERENCES task_events(company_id,task_id,sequence)
);
CREATE TABLE task_delivery_files (
 company_id text NOT NULL, delivery_id text NOT NULL, attachment_id text NOT NULL, file_hash text NOT NULL,
 PRIMARY KEY(company_id,delivery_id,attachment_id), FOREIGN KEY(company_id,delivery_id) REFERENCES task_deliveries(company_id,id),
 FOREIGN KEY(company_id,attachment_id) REFERENCES attachments(company_id,id)
);
CREATE TABLE attachment_bindings (
 company_id text NOT NULL, attachment_id text NOT NULL, resource_type text NOT NULL CHECK(resource_type IN ('WORK','PROCEDURE','DELIVERY')),
 resource_id text NOT NULL, created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(company_id,attachment_id,resource_type,resource_id),
 FOREIGN KEY(company_id,attachment_id) REFERENCES attachments(company_id,id)
);
CREATE INDEX delivery_task_history ON task_deliveries(company_id,task_id,created_at);
ALTER TABLE review_requests DROP CONSTRAINT review_requests_kind_valid;
ALTER TABLE review_requests ADD CONSTRAINT review_requests_kind_valid CHECK(kind IN ('MEMBERSHIP','REVIEWER','POLICY','USER','DEPARTMENT','TEAM','COMPANY_ITEM','LOG','TASK','TASK_REASSIGN','TASK_RESCHEDULE','MEMORY','PROCEDURE'));
CREATE INDEX delivery_check_owner ON task_delivery_checks(company_id,owner_id,task_id,created_at DESC);
ALTER TABLE task_delivery_checks ADD CHECK(version>0 AND task_version>0);
ALTER TABLE ai_work_authorizations ADD CHECK(expires_at>created_at);
CREATE FUNCTION ai_work_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'immutable work evidence' USING ERRCODE='restrict_violation'; END;
$$;
CREATE TRIGGER ai_work_message_no_update BEFORE UPDATE ON ai_work_messages FOR EACH ROW EXECUTE FUNCTION ai_work_immutable();
CREATE TRIGGER ai_work_plan_no_update BEFORE UPDATE ON ai_work_plans FOR EACH ROW EXECUTE FUNCTION ai_work_immutable();
CREATE TRIGGER procedure_version_no_update BEFORE UPDATE ON procedure_versions FOR EACH ROW EXECUTE FUNCTION ai_work_immutable();
