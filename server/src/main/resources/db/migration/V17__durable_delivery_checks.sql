CREATE TABLE task_delivery_check_jobs (
 id text PRIMARY KEY, company_id text NOT NULL, task_id text NOT NULL, owner_id text NOT NULL,
 request jsonb NOT NULL, state text NOT NULL DEFAULT 'QUEUED' CHECK(state IN ('QUEUED','RUNNING','SUCCEEDED','FAILED')),
 fence bigint NOT NULL DEFAULT 0, attempts int NOT NULL DEFAULT 0, lease_until timestamptz,
 next_run_at timestamptz NOT NULL DEFAULT now(), report_id text, error_code text,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(company_id,task_id) REFERENCES tasks(company_id,id),
 FOREIGN KEY(company_id,owner_id) REFERENCES users(company_id,id),
 FOREIGN KEY(company_id,report_id) REFERENCES task_delivery_checks(company_id,id)
);
CREATE INDEX delivery_check_queue ON task_delivery_check_jobs(next_run_at,id) WHERE state IN ('QUEUED','RUNNING');
CREATE INDEX delivery_check_resume ON task_delivery_check_jobs(company_id,owner_id,task_id,created_at DESC);
