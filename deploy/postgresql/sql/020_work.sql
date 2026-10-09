-- 任务、展示项和日报。派发页面不读取或呈现完成情况列。
CREATE TABLE tasks (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES companies(id),
    title text NOT NULL CHECK (btrim(title) <> ''),
    group_name text NOT NULL DEFAULT '未分组',
    content text NOT NULL DEFAULT '',
    due_at timestamptz NOT NULL,
    urgency text NOT NULL DEFAULT 'normal' CHECK (urgency IN ('urgent', 'normal', 'low')),
    progress_note text NOT NULL DEFAULT '',
    created_by uuid NOT NULL,
    primary_assignee_id uuid NOT NULL,
    parent_task_id uuid,
    idempotency_key text NOT NULL CHECK (btrim(idempotency_key) <> ''),
    attachments jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(attachments) = 'array'),
    version integer NOT NULL DEFAULT 1 CHECK (version > 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    archived_at timestamptz,
    UNIQUE (company_id, id), UNIQUE (company_id, created_by, idempotency_key),
    CHECK (parent_task_id IS NULL OR parent_task_id <> id),
    FOREIGN KEY (company_id, created_by) REFERENCES users(company_id, id),
    FOREIGN KEY (company_id, primary_assignee_id) REFERENCES users(company_id, id),
    FOREIGN KEY (company_id, parent_task_id) REFERENCES tasks(company_id, id)
);
CREATE TABLE task_assignees (
    company_id uuid NOT NULL REFERENCES companies(id), task_id uuid NOT NULL,
    user_id uuid NOT NULL,
    assigned_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (company_id, task_id, user_id),
    FOREIGN KEY (company_id, task_id) REFERENCES tasks(company_id, id),
    FOREIGN KEY (company_id, user_id) REFERENCES users(company_id, id)
);
COMMENT ON TABLE task_assignees IS '可选协作者；唯一主负责人在 tasks.primary_assignee_id';
CREATE TABLE task_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES companies(id), task_id uuid NOT NULL,
    actor_id uuid NOT NULL,
    event_type text NOT NULL CHECK (event_type IN
        ('dispatched', 'received', 'feedback', 'accepted', 'reassigned', 'withdrawn', 'deadline_changed', 'archived')),
    payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (company_id, id),
    FOREIGN KEY (company_id, task_id) REFERENCES tasks(company_id, id),
    FOREIGN KEY (company_id, actor_id) REFERENCES users(company_id, id)
);
CREATE TABLE dashboard_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES companies(id),
    owner_id uuid,
    audience text NOT NULL CHECK (audience IN ('company', 'department', 'team', 'personal')),
    department_id uuid, team_id uuid, task_id uuid,
    item_type text NOT NULL CHECK (item_type IN ('highlight', 'task')),
    title text NOT NULL CHECK (btrim(title) <> ''), content text NOT NULL DEFAULT '',
    pinned_position smallint CHECK (pinned_position BETWEEN 1 AND 10),
    created_by uuid NOT NULL,
    version integer NOT NULL DEFAULT 1 CHECK (version > 0),
    created_at timestamptz NOT NULL DEFAULT now(), archived_at timestamptz,
    CHECK ((audience = 'company' AND owner_id IS NULL AND department_id IS NULL AND team_id IS NULL)
        OR (audience = 'department' AND department_id IS NOT NULL AND team_id IS NULL AND owner_id IS NULL)
        OR (audience = 'team' AND team_id IS NOT NULL AND department_id IS NOT NULL AND owner_id IS NULL)
        OR (audience = 'personal' AND owner_id IS NOT NULL AND department_id IS NULL AND team_id IS NULL)),
    CHECK ((item_type = 'task') = (task_id IS NOT NULL)),
    UNIQUE (company_id, id),
    FOREIGN KEY (company_id, owner_id) REFERENCES users(company_id, id),
    FOREIGN KEY (company_id, created_by) REFERENCES users(company_id, id),
    FOREIGN KEY (company_id, department_id) REFERENCES departments(company_id, id),
    FOREIGN KEY (company_id, department_id, team_id) REFERENCES teams(company_id, department_id, id),
    FOREIGN KEY (company_id, task_id) REFERENCES tasks(company_id, id)
);
CREATE UNIQUE INDEX dashboard_pin_unique ON dashboard_items
    (company_id, audience, owner_id, department_id, team_id, item_type, pinned_position) NULLS NOT DISTINCT
    WHERE archived_at IS NULL AND pinned_position IS NOT NULL;
CREATE TABLE private_notes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES companies(id), owner_id uuid NOT NULL,
    dashboard_item_id uuid, task_id uuid,
    content text NOT NULL DEFAULT '',
    version integer NOT NULL DEFAULT 1 CHECK (version > 0),
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (num_nonnulls(dashboard_item_id, task_id) = 1),
    UNIQUE (company_id, id),
    FOREIGN KEY (company_id, owner_id) REFERENCES users(company_id, id),
    FOREIGN KEY (company_id, dashboard_item_id) REFERENCES dashboard_items(company_id, id),
    FOREIGN KEY (company_id, task_id) REFERENCES tasks(company_id, id)
);
CREATE UNIQUE INDEX private_note_item_unique ON private_notes(company_id, owner_id, dashboard_item_id)
    WHERE dashboard_item_id IS NOT NULL;
CREATE UNIQUE INDEX private_note_task_unique ON private_notes(company_id, owner_id, task_id)
    WHERE task_id IS NOT NULL;
CREATE TABLE daily_logs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES companies(id), user_id uuid NOT NULL,
    business_date date NOT NULL,
    today_work text NOT NULL DEFAULT '', blockers text NOT NULL DEFAULT '', tomorrow_plan text NOT NULL DEFAULT '',
    work_hours numeric(4,2) CHECK (work_hours BETWEEN 0 AND 24),
    status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'submitted')),
    submitted_at timestamptz,
    version integer NOT NULL DEFAULT 1 CHECK (version > 0),
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK ((status = 'submitted') = (submitted_at IS NOT NULL)),
    UNIQUE (company_id, id), UNIQUE (company_id, user_id, business_date),
    FOREIGN KEY (company_id, user_id) REFERENCES users(company_id, id)
);
CREATE TABLE log_tasks (
    company_id uuid NOT NULL REFERENCES companies(id), log_id uuid NOT NULL, task_id uuid NOT NULL,
    PRIMARY KEY (company_id, log_id, task_id),
    FOREIGN KEY (company_id, log_id) REFERENCES daily_logs(company_id, id),
    FOREIGN KEY (company_id, task_id) REFERENCES tasks(company_id, id)
);
CREATE TABLE log_versions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES companies(id), log_id uuid NOT NULL,
    version integer NOT NULL CHECK (version > 0),
    content jsonb NOT NULL CHECK (jsonb_typeof(content) = 'object'),
    edited_by uuid NOT NULL, reason text NOT NULL DEFAULT '',
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (company_id, id), UNIQUE (company_id, log_id, version),
    FOREIGN KEY (company_id, log_id) REFERENCES daily_logs(company_id, id),
    FOREIGN KEY (company_id, edited_by) REFERENCES users(company_id, id)
);
CREATE TABLE log_reads (
    company_id uuid NOT NULL REFERENCES companies(id), log_id uuid NOT NULL,
    reader_id uuid NOT NULL, read_at timestamptz NOT NULL DEFAULT now(), comment text NOT NULL DEFAULT '',
    PRIMARY KEY (company_id, log_id, reader_id),
    FOREIGN KEY (company_id, log_id) REFERENCES daily_logs(company_id, id),
    FOREIGN KEY (company_id, reader_id) REFERENCES users(company_id, id)
);
