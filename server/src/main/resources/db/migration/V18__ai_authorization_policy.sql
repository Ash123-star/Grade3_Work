-- 公司授权边界沿用 POLICY 独立复核；修订号使收紧前的个人授权永久失效，不随以后放宽自动复活。
ALTER TABLE companies ADD COLUMN ai_authorization_revision int NOT NULL DEFAULT 1 CHECK(ai_authorization_revision>0);
ALTER TABLE ai_work_authorizations ADD COLUMN policy_revision int NOT NULL DEFAULT 1 CHECK(policy_revision>0);
UPDATE companies SET review_policy='{"aiWorkCreateAuthorization":true,"aiWorkSubmitAuthorization":true,"aiWorkAuthorizationMaxDays":30,"aiWorkAuthorizationMaxObjects":100,"aiWorkAuthorizationMaxActions":5}'::jsonb || review_policy;
CREATE INDEX ai_authorization_active ON ai_work_authorizations(company_id,owner_id,action,policy_revision,expires_at) WHERE revoked_at IS NULL;
CREATE INDEX procedure_visible ON procedure_documents(company_id,state,scope_kind,scope_id,id);
