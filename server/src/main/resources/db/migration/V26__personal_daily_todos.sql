-- #63: independent private todos. V24/V25 are occupied by open PRs;
-- coordinate their merge/upgrade order before deploying V26.
CREATE TABLE personal_todos (
    id text PRIMARY KEY,
    company_id text NOT NULL,
    owner_id text NOT NULL,
    business_date date NOT NULL CHECK (business_date BETWEEN DATE '1900-01-01' AND DATE '2100-12-31'),
    title varchar(120) NOT NULL CHECK (length(trim(title)) > 0),
    note varchar(2000) NOT NULL DEFAULT '',
    completed boolean NOT NULL DEFAULT false,
    completed_at timestamptz,
    version integer NOT NULL DEFAULT 1 CHECK (version > 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    FOREIGN KEY (company_id,owner_id) REFERENCES users(company_id,id),
    CHECK (completed = (completed_at IS NOT NULL))
);
CREATE INDEX personal_todos_day_idx ON personal_todos(company_id,owner_id,business_date,completed,created_at,id)
    WHERE deleted_at IS NULL;

-- Private receipts are never read through organization audit/export APIs.
CREATE TABLE personal_todo_commands (
    company_id text NOT NULL,
    owner_id text NOT NULL,
    command_key varchar(128) NOT NULL,
    request_hash text NOT NULL,
    response jsonb NOT NULL,
    expires_at timestamptz NOT NULL DEFAULT now() + interval '24 hours',
    PRIMARY KEY (company_id,owner_id,command_key),
    FOREIGN KEY (company_id,owner_id) REFERENCES users(company_id,id)
);
CREATE INDEX personal_todo_commands_expiry_idx ON personal_todo_commands(expires_at);
