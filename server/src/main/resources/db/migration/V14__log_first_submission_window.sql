-- 撤回只改变可见状态，首次提交时间不能清空，否则可通过重提延长24小时窗口。
-- 仍要求已提交日志有时间；历史已发布迁移保持原样。
ALTER TABLE daily_logs DROP CONSTRAINT daily_logs_submission_consistent;
ALTER TABLE daily_logs ADD CONSTRAINT daily_logs_submission_consistent
    CHECK (NOT submitted OR submitted_at IS NOT NULL);
