-- 用户确认：旧创始人互审待审全部作废，申请人重新提交。已决历史和业务对象不变。
CREATE TEMP TABLE v31_retired_reviews ON COMMIT DROP AS
SELECT id,company_id,applicant_id FROM review_requests
WHERE approval_mode='FOUNDER_PEER' AND status='PENDING' FOR UPDATE;
UPDATE review_steps SET state='SUPERSEDED',reason='创始人互审规则停用，请重新提交',decided_at=now()
WHERE state='PENDING' AND request_id IN (SELECT id FROM v31_retired_reviews);
UPDATE review_requests SET status='SUPERSEDED' WHERE id IN (SELECT id FROM v31_retired_reviews);
INSERT INTO audit_records(company_id,actor_id,type,object_id,before_value,after_value,reason)
SELECT company_id,applicant_id,'REVIEW_SUPERSEDED',id,'{"status":"PENDING"}'::jsonb,'{"status":"SUPERSEDED","migration":"V31"}'::jsonb,'系统规则迁移：创始人互审停用，申请人须重新提交' FROM v31_retired_reviews;
INSERT INTO outbox_events(id,company_id,recipient_id,type,object_id,body,dedup_key)
SELECT 'v31-retired-'||id,company_id,applicant_id,'REVIEW_SUPERSEDED',id,'{"message":"旧创始人互审申请已作废，请重新提交"}'::jsonb,'review-retired-v31:'||id FROM v31_retired_reviews ON CONFLICT(dedup_key) DO NOTHING;
