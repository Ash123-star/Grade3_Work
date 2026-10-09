CREATE TABLE companies (id text PRIMARY KEY, name text NOT NULL);
INSERT INTO companies VALUES ('default', '企业协作');
CREATE TABLE departments (id text PRIMARY KEY, company_id text NOT NULL REFERENCES companies, name text NOT NULL, version int NOT NULL DEFAULT 1, UNIQUE(company_id,name));
INSERT INTO departments(id,company_id,name) VALUES ('product','default','产品部'),('marketing','default','市场部'),('engineering','default','技术部');
CREATE TABLE teams (id text PRIMARY KEY, company_id text NOT NULL REFERENCES companies, department_id text NOT NULL REFERENCES departments, name text NOT NULL, version int NOT NULL DEFAULT 1);
CREATE TABLE roles (id text PRIMARY KEY);
INSERT INTO roles VALUES ('ADMIN'),('FOUNDER'),('DIRECTOR'),('LEADER'),('EMPLOYEE');
CREATE TABLE permissions (id text PRIMARY KEY);
INSERT INTO permissions VALUES ('DISPATCH'),('COMPANY_REVIEW');
CREATE TABLE users (
 id text PRIMARY KEY, company_id text NOT NULL REFERENCES companies, account text NOT NULL UNIQUE,
 password_hash text NOT NULL, phone text NOT NULL UNIQUE, name text NOT NULL,
 department_id text REFERENCES departments, team_id text REFERENCES teams,
 role text NOT NULL REFERENCES roles, status text NOT NULL CHECK(status IN ('PENDING','ACTIVE','DISABLED')),
 must_change_password boolean NOT NULL DEFAULT false, dispatch_enabled boolean NOT NULL DEFAULT true,
 company_reviewer boolean NOT NULL DEFAULT false, version int NOT NULL DEFAULT 1,
 profile jsonb NOT NULL DEFAULT '{}', created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE user_roles (user_id text REFERENCES users PRIMARY KEY, role_id text NOT NULL REFERENCES roles);
CREATE TABLE reporting_relations (employee_id text PRIMARY KEY REFERENCES users, manager_id text NOT NULL REFERENCES users, company_id text NOT NULL REFERENCES companies, CHECK(employee_id<>manager_id));
CREATE TABLE sessions (token_hash text PRIMARY KEY, user_id text NOT NULL REFERENCES users, expires_at timestamptz NOT NULL);
CREATE TABLE dashboard_items (id text PRIMARY KEY, company_id text NOT NULL REFERENCES companies, owner_id text NOT NULL REFERENCES users, kind text NOT NULL CHECK(kind IN ('COMPANY','PERSONAL')), title text NOT NULL, body jsonb NOT NULL, pinned boolean NOT NULL DEFAULT false, archived boolean NOT NULL DEFAULT false, position int NOT NULL DEFAULT 0, version int NOT NULL DEFAULT 1, created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE private_notes (id text PRIMARY KEY, company_id text NOT NULL REFERENCES companies, owner_id text NOT NULL REFERENCES users, resource text NOT NULL, object_id text NOT NULL, text text NOT NULL, version int NOT NULL DEFAULT 1, UNIQUE(owner_id,resource,object_id));
CREATE TABLE tasks (id text PRIMARY KEY, company_id text NOT NULL REFERENCES companies, owner_id text NOT NULL REFERENCES users, issuer_id text NOT NULL REFERENCES users, title text NOT NULL, deadline timestamptz NOT NULL, body jsonb NOT NULL, phase text NOT NULL DEFAULT 'DISPATCHED', version int NOT NULL DEFAULT 1, created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE task_assignees (task_id text REFERENCES tasks, user_id text REFERENCES users, kind text NOT NULL, PRIMARY KEY(task_id,user_id));
CREATE TABLE task_events (sequence bigserial PRIMARY KEY, company_id text NOT NULL REFERENCES companies, task_id text NOT NULL REFERENCES tasks, actor_id text NOT NULL REFERENCES users, type text NOT NULL, body jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE daily_logs (id text PRIMARY KEY, company_id text NOT NULL REFERENCES companies, owner_id text NOT NULL REFERENCES users, business_date date NOT NULL, body jsonb NOT NULL, submitted boolean NOT NULL DEFAULT false, version int NOT NULL DEFAULT 1, created_at timestamptz NOT NULL DEFAULT now(), submitted_at timestamptz, UNIQUE(owner_id,business_date));
CREATE TABLE log_versions (id bigserial PRIMARY KEY, company_id text NOT NULL REFERENCES companies, log_id text NOT NULL REFERENCES daily_logs, version int NOT NULL, body jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(log_id,version));
CREATE TABLE log_reads (log_id text REFERENCES daily_logs, reader_id text REFERENCES users, read_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(log_id,reader_id));
CREATE TABLE log_comments (id text PRIMARY KEY, company_id text NOT NULL REFERENCES companies, log_id text NOT NULL REFERENCES daily_logs, actor_id text NOT NULL REFERENCES users, text text NOT NULL, created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE review_requests (id text PRIMARY KEY, company_id text NOT NULL REFERENCES companies, applicant_id text NOT NULL REFERENCES users, kind text NOT NULL, target_id text NOT NULL, expected_version int NOT NULL, before_value jsonb NOT NULL, candidate jsonb NOT NULL, reason text NOT NULL, status text NOT NULL DEFAULT 'PENDING', created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE review_steps (id bigserial PRIMARY KEY, request_id text NOT NULL REFERENCES review_requests, reviewer_id text NOT NULL REFERENCES users, position int NOT NULL, state text NOT NULL DEFAULT 'PENDING', reason text, decided_at timestamptz, UNIQUE(request_id,position));
CREATE TABLE audit_records (id bigserial PRIMARY KEY, company_id text NOT NULL REFERENCES companies, actor_id text NOT NULL REFERENCES users, type text NOT NULL, object_id text NOT NULL, before_value jsonb NOT NULL, after_value jsonb NOT NULL, reason text NOT NULL, created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE outbox_events (id text PRIMARY KEY, company_id text NOT NULL REFERENCES companies, recipient_id text NOT NULL REFERENCES users, type text NOT NULL, object_id text NOT NULL, body jsonb NOT NULL, dedup_key text NOT NULL UNIQUE, created_at timestamptz NOT NULL DEFAULT now(), delivered_at timestamptz);
CREATE TABLE notifications (sequence bigserial PRIMARY KEY, id text NOT NULL UNIQUE REFERENCES outbox_events, company_id text NOT NULL REFERENCES companies, recipient_id text NOT NULL REFERENCES users, type text NOT NULL, object_id text NOT NULL, body jsonb NOT NULL, is_read boolean NOT NULL DEFAULT false, created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE idempotency_keys (company_id text NOT NULL, actor_id text NOT NULL REFERENCES users, key text NOT NULL, request_hash text NOT NULL, task_id text NOT NULL, PRIMARY KEY(actor_id,key));
CREATE TABLE attachments (id text PRIMARY KEY, company_id text NOT NULL REFERENCES companies, owner_id text NOT NULL REFERENCES users, filename text NOT NULL, content_type text NOT NULL, data bytea NOT NULL, task_id text REFERENCES tasks, created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE ai_jobs (id text PRIMARY KEY, company_id text NOT NULL REFERENCES companies, owner_id text NOT NULL REFERENCES users, state text NOT NULL DEFAULT 'QUEUED', input jsonb NOT NULL, output jsonb, partial text NOT NULL DEFAULT '', error text, tokens int NOT NULL DEFAULT 0, version int NOT NULL DEFAULT 1, created_at timestamptz NOT NULL DEFAULT now(), finished_at timestamptz);
CREATE TABLE ai_map_nodes (id text PRIMARY KEY, company_id text NOT NULL REFERENCES companies, owner_id text NOT NULL REFERENCES users, job_id text REFERENCES ai_jobs, body jsonb NOT NULL);
CREATE TABLE ai_map_edges (id text PRIMARY KEY, company_id text NOT NULL REFERENCES companies, owner_id text NOT NULL REFERENCES users, source_id text NOT NULL REFERENCES ai_map_nodes, target_id text NOT NULL REFERENCES ai_map_nodes, body jsonb NOT NULL);
CREATE INDEX users_scope ON users(company_id,department_id,team_id,status);
CREATE INDEX tasks_scope ON tasks(company_id,owner_id,deadline);
CREATE INDEX logs_scope ON daily_logs(company_id,owner_id,business_date);
CREATE INDEX notices_scope ON notifications(recipient_id,sequence);
CREATE INDEX outbox_pending ON outbox_events(created_at) WHERE delivered_at IS NULL;
CREATE INDEX review_scope ON review_requests(company_id,status);
