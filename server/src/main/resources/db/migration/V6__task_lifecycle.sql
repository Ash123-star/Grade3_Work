-- 任务生命周期状态机：保留已有历史事件，仅为新事件增加状态与版本快照。
ALTER TABLE task_events
    ADD COLUMN from_phase text,
    ADD COLUMN to_phase text,
    ADD COLUMN task_version int;

-- V5 已允许直接转派/改期；保留 TRANSFERRED 仅用于历史兼容，之后由 REASSIGNED 表示复核生效的转派。
ALTER TABLE task_events DROP CONSTRAINT task_events_type_valid;
ALTER TABLE task_events ADD CONSTRAINT task_events_type_valid CHECK (type IN (
    'DISPATCHED', 'RECEIVED', 'FEEDBACK', 'ACCEPTED', 'RETURNED',
    'ARCHIVED', 'WITHDRAWN', 'REVISED', 'TRANSFERRED', 'REASSIGNED', 'RESCHEDULED'
));
