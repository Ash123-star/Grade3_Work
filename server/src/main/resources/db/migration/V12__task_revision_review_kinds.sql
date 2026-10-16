-- 任务转派、改期沿用既有复核流程；V4 约束发布时尚未包含这两种专用申请类型。
-- V10/V11 已由长期记忆使用；保留 MEMORY，避免收窄主线已支持的类型。
ALTER TABLE review_requests DROP CONSTRAINT review_requests_kind_valid;
ALTER TABLE review_requests ADD CONSTRAINT review_requests_kind_valid CHECK (kind IN (
    'MEMBERSHIP', 'REVIEWER', 'POLICY', 'USER', 'DEPARTMENT', 'TEAM',
    'COMPANY_ITEM', 'LOG', 'TASK', 'TASK_REASSIGN', 'TASK_RESCHEDULE', 'MEMORY'
));
