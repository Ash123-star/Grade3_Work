-- 任务治理：参与人集合、开始时间和审核后生效的创建/删除。
-- 仅新增结构和前向扩展；V1-V15 已发布迁移不得修改。
ALTER TABLE tasks ADD COLUMN start_at timestamptz;

CREATE TABLE task_participants (
    task_id text NOT NULL REFERENCES tasks(id),
    user_id text NOT NULL REFERENCES users(id),
    company_id text NOT NULL REFERENCES companies(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (task_id, user_id)
);

-- 历史负责人、协作人统一回填为无角色参与人集合；主键负责去重。
INSERT INTO task_participants(task_id,user_id,company_id)
SELECT id, owner_id, company_id FROM tasks
ON CONFLICT (task_id,user_id) DO NOTHING;

INSERT INTO task_participants(task_id,user_id,company_id)
SELECT t.id, a.user_id, t.company_id
FROM tasks t JOIN task_assignees a ON a.task_id=t.id
ON CONFLICT (task_id,user_id) DO NOTHING;

CREATE INDEX task_participants_user_scope ON task_participants(company_id,user_id,task_id);

-- idempotency_keys.task_id 对创建申请保存预分配的未来任务 ID；review_id 表示申请本身。
ALTER TABLE idempotency_keys ADD COLUMN review_id text;
CREATE UNIQUE INDEX idempotency_keys_review_id ON idempotency_keys(review_id) WHERE review_id IS NOT NULL;

ALTER TABLE review_requests DROP CONSTRAINT review_requests_kind_valid;
ALTER TABLE review_requests ADD CONSTRAINT review_requests_kind_valid CHECK (kind IN (
    'MEMBERSHIP', 'REVIEWER', 'POLICY', 'USER', 'DEPARTMENT', 'TEAM',
    'COMPANY_ITEM', 'LOG', 'TASK', 'TASK_REASSIGN', 'TASK_RESCHEDULE',
    'MEMORY', 'TASK_CREATE', 'TASK_DELETE'
));
