-- 任务派发：幂等摘要版本、附件引用索引、事件时间线只追加。
-- 新列追加在末尾，旧代码按位置插入 idempotency_keys 仍兼容。
ALTER TABLE idempotency_keys ADD COLUMN created_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE idempotency_keys ADD COLUMN hash_version smallint NOT NULL DEFAULT 1;
ALTER TABLE idempotency_keys ADD CHECK (hash_version IN (1,2));

CREATE INDEX attachments_unbound ON attachments(company_id,owner_id) WHERE task_id IS NULL;

-- V4 已创建类型约束；在前向迁移中扩展为转派、改期事件，避免修改已应用迁移的校验和。
ALTER TABLE task_events DROP CONSTRAINT task_events_type_valid;
ALTER TABLE task_events ADD CONSTRAINT task_events_type_valid CHECK (type IN ('DISPATCHED','RECEIVED','FEEDBACK','ACCEPTED','ARCHIVED','WITHDRAWN','REVISED','TRANSFERRED','RESCHEDULED'));
CREATE INDEX task_events_timeline ON task_events(task_id,sequence);

CREATE FUNCTION task_events_append_only() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'task_events 只允许追加' USING ERRCODE = 'restrict_violation';
END;
$$;
CREATE TRIGGER task_events_no_update BEFORE UPDATE OR DELETE ON task_events FOR EACH ROW EXECUTE FUNCTION task_events_append_only();
CREATE TRIGGER task_events_no_truncate BEFORE TRUNCATE ON task_events FOR EACH STATEMENT EXECUTE FUNCTION task_events_append_only();
