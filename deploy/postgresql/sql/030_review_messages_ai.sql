-- 复核保存候选版本；审核生效、版本比较与范围由后续服务端事务负责。
CREATE TABLE review_requests (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES companies(id), applicant_id uuid NOT NULL,
    object_type text NOT NULL CHECK (object_type IN ('organization', 'role', 'dashboard_item', 'task', 'daily_log')),
    object_id uuid NOT NULL,
    base_version integer NOT NULL CHECK (base_version >= 0),
    before_value jsonb NOT NULL DEFAULT '{}'::jsonb,
    candidate_value jsonb NOT NULL CHECK (jsonb_typeof(candidate_value) = 'object'),
    reason text NOT NULL CHECK (btrim(reason) <> ''),
    status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled')),
    version integer NOT NULL DEFAULT 1 CHECK (version > 0),
    created_at timestamptz NOT NULL DEFAULT now(), decided_at timestamptz,
    UNIQUE (company_id, id), UNIQUE (company_id, id, applicant_id),
    FOREIGN KEY (company_id, applicant_id) REFERENCES users(company_id, id)
);
CREATE TABLE review_steps (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES companies(id), review_request_id uuid NOT NULL,
    applicant_id uuid NOT NULL, reviewer_id uuid NOT NULL,
    step_order smallint NOT NULL CHECK (step_order > 0),
    status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'skipped')),
    comment text NOT NULL DEFAULT '', decided_at timestamptz,
    CHECK (reviewer_id <> applicant_id),
    CHECK (status <> 'rejected' OR btrim(comment) <> ''),
    CHECK ((status IN ('approved', 'rejected')) = (decided_at IS NOT NULL)),
    UNIQUE (company_id, id), UNIQUE (company_id, review_request_id, step_order),
    FOREIGN KEY (company_id, review_request_id, applicant_id) REFERENCES review_requests(company_id, id, applicant_id),
    FOREIGN KEY (company_id, reviewer_id) REFERENCES users(company_id, id)
);
CREATE TABLE audit_records (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES companies(id), actor_id uuid,
    action text NOT NULL, object_type text NOT NULL, object_id uuid,
    before_value jsonb, after_value jsonb,
    reason text NOT NULL, review_request_id uuid, trace_id text,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (company_id, id),
    FOREIGN KEY (company_id, actor_id) REFERENCES users(company_id, id),
    FOREIGN KEY (company_id, review_request_id) REFERENCES review_requests(company_id, id)
);
CREATE TABLE outbox_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES companies(id),
    event_type text NOT NULL, aggregate_type text NOT NULL, aggregate_id uuid NOT NULL,
    payload jsonb NOT NULL CHECK (jsonb_typeof(payload) = 'object'),
    dedup_key text NOT NULL,
    attempts integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    available_at timestamptz NOT NULL DEFAULT now(), published_at timestamptz,
    last_error text, created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (company_id, id), UNIQUE (company_id, dedup_key)
);
CREATE TABLE notifications (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES companies(id), recipient_id uuid NOT NULL,
    notification_type text NOT NULL CHECK (notification_type IN
        ('task_dispatch', 'task_deadline', 'review_pending', 'review_result', 'log_submitted', 'task_event')),
    title text NOT NULL, body text NOT NULL DEFAULT '', target_type text NOT NULL, target_id uuid NOT NULL,
    outbox_event_id uuid, dedup_key text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(), read_at timestamptz,
    UNIQUE (company_id, id), UNIQUE (company_id, recipient_id, dedup_key),
    FOREIGN KEY (company_id, recipient_id) REFERENCES users(company_id, id),
    FOREIGN KEY (company_id, outbox_event_id) REFERENCES outbox_events(company_id, id)
);
CREATE TABLE ai_jobs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES companies(id), requested_by uuid NOT NULL,
    job_type text NOT NULL CHECK (job_type IN ('daily_summary', 'weekly_summary', 'map_extract', 'risk_explain', 'task_draft')),
    status text NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'running', 'succeeded', 'failed', 'cancelled')),
    model text NOT NULL, input jsonb NOT NULL, output jsonb,
    sources jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(sources) = 'array'),
    input_tokens integer NOT NULL DEFAULT 0 CHECK (input_tokens >= 0),
    output_tokens integer NOT NULL DEFAULT 0 CHECK (output_tokens >= 0),
    cost numeric(14,6) NOT NULL DEFAULT 0 CHECK (cost >= 0),
    attempts integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    error_code text, error_message text, cancelled_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(), started_at timestamptz, finished_at timestamptz,
    UNIQUE (company_id, id),
    FOREIGN KEY (company_id, requested_by) REFERENCES users(company_id, id)
);
COMMENT ON TABLE ai_jobs IS '建议草稿及来源；不得保存 DeepSeek 密钥、手机号、密码或私人备注';
CREATE TABLE ai_map_nodes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES companies(id), owner_id uuid NOT NULL, ai_job_id uuid,
    node_type text NOT NULL CHECK (node_type IN ('goal', 'task', 'highlight', 'log', 'blocker', 'risk', 'action')),
    title text NOT NULL, content text NOT NULL DEFAULT '',
    task_id uuid, log_id uuid, dashboard_item_id uuid,
    sources jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(sources) = 'array'),
    is_suggestion boolean NOT NULL DEFAULT true,
    position_x numeric NOT NULL DEFAULT 0, position_y numeric NOT NULL DEFAULT 0,
    version integer NOT NULL DEFAULT 1 CHECK (version > 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (company_id, id), UNIQUE (company_id, owner_id, id),
    FOREIGN KEY (company_id, owner_id) REFERENCES users(company_id, id),
    FOREIGN KEY (company_id, ai_job_id) REFERENCES ai_jobs(company_id, id),
    FOREIGN KEY (company_id, task_id) REFERENCES tasks(company_id, id),
    FOREIGN KEY (company_id, log_id) REFERENCES daily_logs(company_id, id),
    FOREIGN KEY (company_id, dashboard_item_id) REFERENCES dashboard_items(company_id, id)
);
CREATE TABLE ai_map_edges (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES companies(id), owner_id uuid NOT NULL,
    source_node_id uuid NOT NULL, target_node_id uuid NOT NULL,
    edge_type text NOT NULL CHECK (edge_type IN ('depends_on', 'related_to', 'blocks', 'supports')),
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK (source_node_id <> target_node_id),
    UNIQUE (company_id, id), UNIQUE (company_id, owner_id, source_node_id, target_node_id, edge_type),
    FOREIGN KEY (company_id, owner_id) REFERENCES users(company_id, id),
    FOREIGN KEY (company_id, owner_id, source_node_id) REFERENCES ai_map_nodes(company_id, owner_id, id),
    FOREIGN KEY (company_id, owner_id, target_node_id) REFERENCES ai_map_nodes(company_id, owner_id, id)
);
