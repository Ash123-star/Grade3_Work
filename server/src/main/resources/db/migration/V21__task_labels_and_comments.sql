-- 标签、每任务唯一标签关联，以及只追加的公开任务评论。
CREATE TABLE task_labels (
    id text PRIMARY KEY,
    company_id text NOT NULL REFERENCES companies(id),
    department_id text REFERENCES departments(id),
    name text NOT NULL,
    category text NOT NULL,
    color text NOT NULL,
    creator_id text NOT NULL REFERENCES users(id),
    status text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','DISABLED')),
    version int NOT NULL DEFAULT 1 CHECK (version > 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(company_id,department_id,name)
);
CREATE INDEX task_labels_scope ON task_labels(company_id,department_id,status,name);

CREATE TABLE task_label_links (
    task_id text PRIMARY KEY REFERENCES tasks(id),
    label_id text NOT NULL REFERENCES task_labels(id),
    company_id text NOT NULL REFERENCES companies(id),
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX task_label_links_label ON task_label_links(company_id,label_id,task_id);

CREATE TABLE task_comments (
    id text PRIMARY KEY,
    company_id text NOT NULL REFERENCES companies(id),
    task_id text NOT NULL REFERENCES tasks(id),
    author_id text NOT NULL REFERENCES users(id),
    parent_id text REFERENCES task_comments(id),
    body text NOT NULL CHECK (btrim(body) <> ''),
    client_key text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(task_id,author_id,client_key)
);
CREATE INDEX task_comments_timeline ON task_comments(task_id,created_at,id);

CREATE FUNCTION task_comments_append_only() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'task_comments 只允许追加' USING ERRCODE = 'restrict_violation';
END;
$$;
CREATE TRIGGER task_comments_no_update BEFORE UPDATE OR DELETE ON task_comments
FOR EACH ROW EXECUTE FUNCTION task_comments_append_only();
