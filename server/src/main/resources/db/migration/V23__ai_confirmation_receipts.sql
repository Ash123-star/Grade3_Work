-- AI确认命令回执：和任务/审核写入同事务，版本冲突不产生部分数据。
ALTER TABLE ai_jobs ADD CONSTRAINT ai_jobs_confirmation_owner_key UNIQUE(company_id,owner_id,id);
CREATE TABLE ai_task_confirmations (
    id text PRIMARY KEY,
    company_id text NOT NULL,
    owner_id text NOT NULL,
    job_id text NOT NULL,
    client_key text NOT NULL CHECK(length(client_key) BETWEEN 1 AND 128),
    job_version integer NOT NULL CHECK(job_version >= 0),
    action_index integer NOT NULL CHECK(action_index BETWEEN 0 AND 2),
    request_hash text NOT NULL,
    source_refs jsonb NOT NULL CHECK(jsonb_typeof(source_refs)='object'),
    response jsonb NOT NULL CHECK(jsonb_typeof(response)='object'),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(owner_id,job_id,client_key),
    FOREIGN KEY(company_id,owner_id,job_id) REFERENCES ai_jobs(company_id,owner_id,id)
);
