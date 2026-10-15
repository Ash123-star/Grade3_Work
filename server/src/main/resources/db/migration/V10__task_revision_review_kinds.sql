-- 任务转派、改期沿用既有复核流程；V4 约束发布时尚未包含这两种专用申请类型。
-- 使用前向迁移扩展白名单，不修改任何已发布迁移或既有复核记录。
ALTER TABLE review_requests DROP CONSTRAINT review_requests_kind_valid;
ALTER TABLE review_requests ADD CONSTRAINT review_requests_kind_valid CHECK (kind IN (
    'MEMBERSHIP', 'REVIEWER', 'POLICY', 'USER', 'DEPARTMENT', 'TEAM',
    'COMPANY_ITEM', 'LOG', 'TASK', 'TASK_REASSIGN', 'TASK_RESCHEDULE'
));
