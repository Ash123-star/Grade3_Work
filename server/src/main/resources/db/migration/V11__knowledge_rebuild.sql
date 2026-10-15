ALTER TABLE knowledge_index_jobs ADD COLUMN chunker_version text NOT NULL DEFAULT 'v1';
ALTER TABLE knowledge_index_jobs DROP CONSTRAINT knowledge_index_jobs_company_id_memory_id_memory_version_key;
ALTER TABLE knowledge_index_jobs ADD CONSTRAINT knowledge_index_job_version UNIQUE(company_id,memory_id,memory_version,chunker_version);

CREATE TABLE knowledge_rebuild_jobs (
 id text PRIMARY KEY, company_id text NOT NULL REFERENCES companies,
 request_key text NOT NULL, target_version text NOT NULL,
 state text NOT NULL CHECK(state IN ('BUILDING','SUCCEEDED','FAILED')),
 cursor_id text NOT NULL DEFAULT '', processed int NOT NULL DEFAULT 0,
 error text, created_at timestamptz NOT NULL DEFAULT now(), finished_at timestamptz,
 UNIQUE(company_id,id), UNIQUE(company_id,request_key), UNIQUE(company_id,target_version)
);

CREATE TABLE knowledge_index_state (
 company_id text PRIMARY KEY REFERENCES companies,
 active_version text NOT NULL DEFAULT 'v1', building_version text,
 rebuild_id text, cursor_id text NOT NULL DEFAULT '', scan_done boolean NOT NULL DEFAULT false,
 state text NOT NULL DEFAULT 'READY' CHECK(state IN ('READY','BUILDING','FAILED')),
 updated_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(company_id,rebuild_id) REFERENCES knowledge_rebuild_jobs(company_id,id)
);
INSERT INTO knowledge_index_state(company_id) SELECT id FROM companies;
CREATE INDEX knowledge_index_queue ON knowledge_index_jobs(company_id,chunker_version,created_at) WHERE state='QUEUED';
