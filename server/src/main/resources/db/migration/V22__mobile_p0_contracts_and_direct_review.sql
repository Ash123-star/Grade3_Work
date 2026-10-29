-- Mobile P0 契约与直属单级审核。
-- 只使用 server Flyway 路径；V1–V21 已发布，不得修改，本文件为尚未发布的追加迁移。
-- 历史员工的入职日期不从 created_at 或迁移时间推断，保持 NULL（月状态返回 UNKNOWN）。
-- 迁移只做结构与历史数据修补，不应用任何历史待审候选。

-- 1. 用户结构化资料列。phone 保持唯一约束但允许 NULL，以支持本人清空选填联系方式。
ALTER TABLE users ADD COLUMN email text;
ALTER TABLE users ADD COLUMN gender text;
ALTER TABLE users ADD COLUMN age integer;
ALTER TABLE users ADD COLUMN employment_start_date date;
ALTER TABLE users ALTER COLUMN phone DROP NOT NULL;
ALTER TABLE users
    ADD CONSTRAINT users_age_nonnegative CHECK (age IS NULL OR age >= 0),
    ADD CONSTRAINT users_gender_length CHECK (gender IS NULL OR length(gender) <= 32),
    ADD CONSTRAINT users_email_length CHECK (email IS NULL OR length(email) <= 320);

-- 2. 旧 profile JSONB 值只在通过当前契约校验并成功转写后才移除；非法/未知旧值原样保留。
--    结构化列已存在的值优先，不被 JSONB 覆盖；其余 profile 键（简介、头像、私人扩展）不触碰。
UPDATE users u
SET email = COALESCE(u.email, CASE
        WHEN jsonb_typeof(u.profile->'email') = 'string'
         AND length(u.profile->>'email') <= 320
         AND u.profile->>'email' ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
        THEN u.profile->>'email' END),
    gender = COALESCE(u.gender, CASE
        WHEN jsonb_typeof(u.profile->'gender') = 'string'
         AND btrim(u.profile->>'gender') <> ''
         AND length(u.profile->>'gender') <= 32
        THEN btrim(u.profile->>'gender') END),
    age = COALESCE(u.age, CASE
        WHEN jsonb_typeof(u.profile->'age') IN ('string', 'number')
         AND (u.profile->>'age') ~ '^[0-9]{1,10}$'
        THEN CASE WHEN (u.profile->>'age')::bigint <= 2147483647
                  THEN (u.profile->>'age')::integer END END)
WHERE (u.profile->'email') IS NOT NULL OR (u.profile->'gender') IS NOT NULL OR (u.profile->'age') IS NOT NULL;

UPDATE users SET profile = profile - 'email'
WHERE jsonb_typeof(profile->'email') = 'string'
  AND length(profile->>'email') <= 320
  AND profile->>'email' ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$';

UPDATE users SET profile = profile - 'gender'
WHERE jsonb_typeof(profile->'gender') = 'string'
  AND btrim(profile->>'gender') <> ''
  AND length(profile->>'gender') <= 32;

UPDATE users SET profile = profile - 'age'
WHERE jsonb_typeof(profile->'age') IN ('string', 'number')
  AND profile->>'age' = age::text;

-- 手机号权威列已存在；仅当旧 JSONB 值与列完全一致（重复转存）时才清理，
-- 与列冲突的旧值保留在 JSONB 中供人工核对，读取时以列为准。
UPDATE users SET profile = profile - 'phone'
WHERE jsonb_typeof(profile->'phone') = 'string' AND profile->>'phone' = phone;

-- 3. 审核模式、决定来源与步骤替代状态。已决历史保持可读，仅 PENDING 步骤被替代。
ALTER TABLE review_requests
    ADD COLUMN approval_mode text NOT NULL DEFAULT 'LEGACY',
    ADD COLUMN decision_source text;
ALTER TABLE review_requests
    ADD CONSTRAINT review_requests_approval_mode_valid
        CHECK (approval_mode IN ('DIRECT_MANAGER', 'ADMIN_MEMBERSHIP', 'LEGACY')),
    ADD CONSTRAINT review_requests_decision_source_valid
        CHECK (decision_source IS NULL OR decision_source IN ('DIRECT_MANAGER', 'ADMIN_MEMBERSHIP', 'FOUNDER_EXEMPT'));

-- V2 的匿名 CHECK 约束由 PostgreSQL 自动命名；只删除仅引用状态列的单列约束，
-- 避免误删同时引用 state/reason 的驳回理由约束。
DO $$
DECLARE constraint_name text;
BEGIN
    FOR constraint_name IN
        SELECT c.conname FROM pg_constraint c
        JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY (c.conkey)
        WHERE c.conrelid = 'review_requests'::regclass AND c.contype = 'c'
          AND a.attname = 'status' AND array_length(c.conkey, 1) = 1
    LOOP
        EXECUTE format('ALTER TABLE review_requests DROP CONSTRAINT %I', constraint_name);
    END LOOP;
    FOR constraint_name IN
        SELECT c.conname FROM pg_constraint c
        JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY (c.conkey)
        WHERE c.conrelid = 'review_steps'::regclass AND c.contype = 'c'
          AND a.attname = 'state' AND array_length(c.conkey, 1) = 1
    LOOP
        EXECUTE format('ALTER TABLE review_steps DROP CONSTRAINT %I', constraint_name);
    END LOOP;
END $$;

ALTER TABLE review_requests ADD CONSTRAINT review_requests_status_check
    CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED', 'SUPERSEDED'));
ALTER TABLE review_steps ADD CONSTRAINT review_steps_state_check
    CHECK (state IN ('PENDING', 'APPROVED', 'REJECTED', 'SUPERSEDED'));

UPDATE review_requests
SET approval_mode = CASE
    WHEN status = 'PENDING' AND kind = 'MEMBERSHIP' THEN 'ADMIN_MEMBERSHIP'
    WHEN status = 'PENDING' THEN 'DIRECT_MANAGER'
    ELSE 'LEGACY'
END;

-- 旧待审步骤显式替代并保留原因与时间，作为审计历史；已决步骤（APPROVED/REJECTED）不修改。
UPDATE review_steps s
SET state = 'SUPERSEDED',
    reason = COALESCE(NULLIF(btrim(s.reason), ''), '旧待审步骤由当前单级审核规则替代'),
    decided_at = COALESCE(s.decided_at, now())
FROM review_requests r
WHERE r.id = s.request_id AND r.status = 'PENDING' AND s.state = 'PENDING';

-- 日报正文已经改为本人24小时直改；历史LOG候选不可在窗口外或新正文之后覆盖数据。
-- 所有旧步骤仍在，申请明确失效，不应用候选。
UPDATE review_requests SET status='SUPERSEDED'
WHERE kind='LOG' AND status='PENDING';

-- 4. 按当前规则重新分配唯一审核人；找不到有效审核人时保持 PENDING 且无可操作步骤。
--    注册成员确认（MEMBERSHIP）始终由当前有效的公司管理员审批，创始人申请也不例外。
INSERT INTO review_steps(request_id, reviewer_id, applicant_id, position, company_id, state)
SELECT r.id, reviewer.id, r.applicant_id,
       COALESCE((SELECT max(s.position) + 1 FROM review_steps s WHERE s.request_id = r.id), 1),
       r.company_id, 'PENDING'
FROM review_requests r
CROSS JOIN LATERAL (
    SELECT u.id
    FROM users u
    WHERE u.company_id = r.company_id
      AND u.status = 'ACTIVE'
      AND NOT u.must_change_password
      AND u.role = 'ADMIN'
      AND u.company_reviewer = true
      AND u.id <> r.applicant_id
    ORDER BY u.id
    LIMIT 1
) reviewer
WHERE r.status = 'PENDING' AND r.kind = 'MEMBERSHIP';

INSERT INTO review_steps(request_id, reviewer_id, applicant_id, position, company_id, state)
SELECT r.id, manager.id, r.applicant_id,
       COALESCE((SELECT max(s.position) + 1 FROM review_steps s WHERE s.request_id = r.id), 1),
       r.company_id, 'PENDING'
FROM review_requests r
JOIN users applicant
  ON applicant.id = r.applicant_id
 AND applicant.company_id = r.company_id
 AND applicant.status = 'ACTIVE'
JOIN reporting_relations relation
  ON relation.employee_id = applicant.id
 AND relation.company_id = r.company_id
JOIN users manager
  ON manager.id = relation.manager_id
 AND manager.company_id = r.company_id
 AND manager.status = 'ACTIVE'
 AND NOT manager.must_change_password
WHERE r.status = 'PENDING'
  AND r.kind <> 'MEMBERSHIP'
  AND relation.manager_id <> r.applicant_id
  AND NOT EXISTS (
      WITH RECURSIVE chain(id,path,cycle) AS (
          SELECT manager_id,ARRAY[employee_id,manager_id],employee_id=manager_id
          FROM reporting_relations WHERE company_id=r.company_id AND employee_id=r.applicant_id
          UNION ALL
          SELECT rr.manager_id,c.path||rr.manager_id,rr.manager_id=ANY(c.path)
          FROM reporting_relations rr JOIN chain c ON rr.employee_id=c.id WHERE rr.company_id=r.company_id AND NOT c.cycle
      ) SELECT 1 FROM chain WHERE cycle
  );

-- 5. 重新通知当前审核人；去重键稳定，重复执行不会产生重复待办。
INSERT INTO outbox_events(id, company_id, recipient_id, type, object_id, body, dedup_key)
SELECT 'review-migration:' || s.request_id || ':' || s.reviewer_id,
       r.company_id, s.reviewer_id, 'REVIEW_PENDING', r.id, '{}'::jsonb,
       'review-migration:' || s.request_id || ':' || s.reviewer_id
FROM review_requests r
JOIN review_steps s ON s.request_id = r.id AND s.state = 'PENDING'
WHERE r.status = 'PENDING'
ON CONFLICT (dedup_key) DO NOTHING;

-- 6. 每个申请最多一个可执行待审步骤；迁移后按当前审核人查询待办。
CREATE UNIQUE INDEX review_steps_one_pending_per_request
    ON review_steps(request_id) WHERE state = 'PENDING';
CREATE INDEX review_steps_current_reviewer
    ON review_steps(company_id, reviewer_id, request_id) WHERE state = 'PENDING';
CREATE INDEX users_employment_start
    ON users(company_id, employment_start_date, id) WHERE status = 'ACTIVE';

-- 支持跨区间查询与真实事件统计，不修改任何已有事件时间。
CREATE INDEX task_events_company_type_time ON task_events(company_id,type,created_at,task_id);
CREATE INDEX daily_logs_company_submitted_date ON daily_logs(company_id,business_date,owner_id) WHERE submitted;
