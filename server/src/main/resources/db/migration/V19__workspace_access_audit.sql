CREATE TABLE workspace_access_audit (
    id bigserial PRIMARY KEY,
    created_at timestamptz NOT NULL DEFAULT now(),
    company_id text,
    actor_id text,
    method varchar(16) NOT NULL,
    endpoint varchar(32) NOT NULL,
    status integer NOT NULL CHECK (status IN (401,403)),
    trace_id text NOT NULL
);
CREATE INDEX workspace_access_audit_company_time ON workspace_access_audit(company_id,created_at);
