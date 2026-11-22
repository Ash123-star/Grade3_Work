-- Forward-only: preserve all old modes and decisions. The additional modes only apply to TASK_CREATE.
ALTER TABLE review_requests DROP CONSTRAINT review_requests_approval_mode_valid, DROP CONSTRAINT review_requests_decision_source_valid;
ALTER TABLE review_requests ADD CONSTRAINT review_requests_approval_mode_valid CHECK (
  approval_mode IN ('DIRECT_MANAGER','ADMIN_MEMBERSHIP','FOUNDER_PEER','LEGACY') OR (kind='TASK_CREATE' AND approval_mode IN ('TASK_MANAGER','TASK_RECIPIENT'))),
 ADD CONSTRAINT review_requests_decision_source_valid CHECK (decision_source IS NULL OR decision_source IN ('DIRECT_MANAGER','ADMIN_MEMBERSHIP','FOUNDER_PEER','FOUNDER_EXEMPT') OR (kind='TASK_CREATE' AND decision_source IN ('TASK_MANAGER','TASK_RECIPIENT')));
