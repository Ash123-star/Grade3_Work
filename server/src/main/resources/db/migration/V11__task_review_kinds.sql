-- 任务转派和改期通过独立复核生效，保留全部历史复核类型。
ALTER TABLE review_requests DROP CONSTRAINT review_requests_kind_valid;
ALTER TABLE review_requests ADD CONSTRAINT review_requests_kind_valid CHECK (
    kind IN ('MEMBERSHIP','REVIEWER','POLICY','USER','DEPARTMENT','TEAM','COMPANY_ITEM','LOG','TASK','TASK_REASSIGN','TASK_RESCHEDULE')
);
