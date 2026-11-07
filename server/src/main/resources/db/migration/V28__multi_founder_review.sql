-- 多创始人互审：同公司存在其他有效创始人时，创始人的非 MEMBERSHIP 申请由另一位创始人审核。
-- 只新增模式/来源枚举并处理仍待审的记录；已决历史（含 FOUNDER_EXEMPT）不修改，历史候选不自动应用。

-- 1. 模式与决定来源增加 FOUNDER_PEER。
ALTER TABLE review_requests
    DROP CONSTRAINT review_requests_approval_mode_valid,
    DROP CONSTRAINT review_requests_decision_source_valid;
ALTER TABLE review_requests
    ADD CONSTRAINT review_requests_approval_mode_valid
        CHECK (approval_mode IN ('DIRECT_MANAGER', 'ADMIN_MEMBERSHIP', 'FOUNDER_PEER', 'LEGACY')),
    ADD CONSTRAINT review_requests_decision_source_valid
        CHECK (decision_source IS NULL OR decision_source IN ('DIRECT_MANAGER', 'ADMIN_MEMBERSHIP', 'FOUNDER_PEER', 'FOUNDER_EXEMPT'));

-- 2. 有效创始人申请人且公司另有有效创始人的待审申请改为创始人互审；原待审步骤作废保留审计。
CREATE TEMP TABLE v24_peer_requests ON COMMIT DROP AS
SELECT r.id
FROM review_requests r
JOIN users applicant ON applicant.id = r.applicant_id AND applicant.company_id = r.company_id
WHERE r.status = 'PENDING' AND r.kind NOT IN ('MEMBERSHIP', 'LOG')
  AND applicant.role = 'FOUNDER' AND applicant.status = 'ACTIVE' AND NOT applicant.must_change_password
  AND EXISTS (
      SELECT 1 FROM users peer
      WHERE peer.company_id = r.company_id AND peer.id <> r.applicant_id AND peer.role = 'FOUNDER'
        AND peer.status = 'ACTIVE' AND NOT peer.must_change_password);

UPDATE review_steps s
SET state = 'SUPERSEDED', reason = 'V24 创始人申请改为创始人互审', decided_at = now()
FROM v24_peer_requests p
WHERE s.request_id = p.id AND s.state = 'PENDING';

UPDATE review_requests r SET approval_mode = 'FOUNDER_PEER'
FROM v24_peer_requests p WHERE r.id = p.id;

-- 3. 其余待审申请中审核人已停用、待改密或不再满足所属模式的步骤作废。
UPDATE review_steps s
SET state = 'SUPERSEDED', reason = 'V24 审核人失效', decided_at = now()
FROM review_requests r, users reviewer
WHERE r.id = s.request_id AND r.status = 'PENDING' AND s.state = 'PENDING'
  AND reviewer.id = s.reviewer_id AND reviewer.company_id = s.company_id
  AND r.approval_mode <> 'FOUNDER_PEER'
  AND (reviewer.status <> 'ACTIVE' OR reviewer.must_change_password
       OR (r.kind = 'MEMBERSHIP' AND (reviewer.role <> 'ADMIN' OR NOT reviewer.company_reviewer))
       OR (r.kind <> 'MEMBERSHIP' AND NOT EXISTS (
           SELECT 1 FROM reporting_relations relation
           WHERE relation.company_id = r.company_id AND relation.employee_id = r.applicant_id
             AND relation.manager_id = reviewer.id)));

-- 仍有效的待审步骤不重复通知；只通知本迁移新分配的步骤。
CREATE TEMP TABLE v24_existing_steps ON COMMIT DROP AS
SELECT id FROM review_steps WHERE state = 'PENDING';

-- 4. 为没有待审步骤的申请重新分配唯一审核人。
-- 4.1 创始人互审：优先直属上级（若为有效创始人），否则按 id 取其他有效创始人。
INSERT INTO review_steps(request_id, reviewer_id, applicant_id, position, company_id, state)
SELECT r.id, peer.id, r.applicant_id,
       COALESCE((SELECT max(s.position) + 1 FROM review_steps s WHERE s.request_id = r.id), 1),
       r.company_id, 'PENDING'
FROM review_requests r
CROSS JOIN LATERAL (
    SELECT u.id FROM users u
    LEFT JOIN reporting_relations relation
      ON relation.company_id = r.company_id AND relation.employee_id = r.applicant_id AND relation.manager_id = u.id
    WHERE u.company_id = r.company_id AND u.id <> r.applicant_id AND u.role = 'FOUNDER'
      AND u.status = 'ACTIVE' AND NOT u.must_change_password
    ORDER BY (relation.manager_id IS NULL), u.id
    LIMIT 1
) peer
WHERE r.status = 'PENDING' AND r.approval_mode = 'FOUNDER_PEER'
  AND NOT EXISTS (SELECT 1 FROM review_steps s WHERE s.request_id = r.id AND s.state = 'PENDING');

-- 4.2 成员确认：有效管理员审核人。
INSERT INTO review_steps(request_id, reviewer_id, applicant_id, position, company_id, state)
SELECT r.id, reviewer.id, r.applicant_id,
       COALESCE((SELECT max(s.position) + 1 FROM review_steps s WHERE s.request_id = r.id), 1),
       r.company_id, 'PENDING'
FROM review_requests r
CROSS JOIN LATERAL (
    SELECT u.id FROM users u
    WHERE u.company_id = r.company_id AND u.status = 'ACTIVE' AND NOT u.must_change_password
      AND u.role = 'ADMIN' AND u.company_reviewer = true AND u.id <> r.applicant_id
    ORDER BY u.id
    LIMIT 1
) reviewer
WHERE r.status = 'PENDING' AND r.kind = 'MEMBERSHIP'
  AND NOT EXISTS (SELECT 1 FROM review_steps s WHERE s.request_id = r.id AND s.state = 'PENDING');

-- 4.3 直属上级：与 V22 相同的有效关系与汇报环判断。
INSERT INTO review_steps(request_id, reviewer_id, applicant_id, position, company_id, state)
SELECT r.id, manager.id, r.applicant_id,
       COALESCE((SELECT max(s.position) + 1 FROM review_steps s WHERE s.request_id = r.id), 1),
       r.company_id, 'PENDING'
FROM review_requests r
JOIN users applicant
  ON applicant.id = r.applicant_id AND applicant.company_id = r.company_id AND applicant.status = 'ACTIVE'
JOIN reporting_relations relation
  ON relation.employee_id = applicant.id AND relation.company_id = r.company_id
JOIN users manager
  ON manager.id = relation.manager_id AND manager.company_id = r.company_id
 AND manager.status = 'ACTIVE' AND NOT manager.must_change_password
WHERE r.status = 'PENDING' AND r.kind <> 'MEMBERSHIP' AND r.approval_mode <> 'FOUNDER_PEER'
  AND relation.manager_id <> r.applicant_id
  AND NOT EXISTS (SELECT 1 FROM review_steps s WHERE s.request_id = r.id AND s.state = 'PENDING')
  AND NOT EXISTS (
      WITH RECURSIVE chain(id,path,cycle) AS (
          SELECT manager_id,ARRAY[employee_id,manager_id],employee_id=manager_id
          FROM reporting_relations WHERE company_id=r.company_id AND employee_id=r.applicant_id
          UNION ALL
          SELECT rr.manager_id,c.path||rr.manager_id,rr.manager_id=ANY(c.path)
          FROM reporting_relations rr JOIN chain c ON rr.employee_id=c.id WHERE rr.company_id=r.company_id AND NOT c.cycle
      ) SELECT 1 FROM chain WHERE cycle
  );

-- 5. 通知：新分配的审核人收到待审；仍无审核人的有效申请通知管理员与申请人。去重键稳定，可重复执行。
INSERT INTO outbox_events(id, company_id, recipient_id, type, object_id, body, dedup_key)
SELECT 'review-migration-v24:' || s.request_id || ':' || s.reviewer_id,
       r.company_id, s.reviewer_id, 'REVIEW_PENDING', r.id, '{}'::jsonb,
       'review-migration-v24:' || s.request_id || ':' || s.reviewer_id
FROM review_requests r
JOIN review_steps s ON s.request_id = r.id AND s.state = 'PENDING'
WHERE r.status = 'PENDING' AND NOT EXISTS (SELECT 1 FROM v24_existing_steps e WHERE e.id = s.id)
ON CONFLICT (dedup_key) DO NOTHING;

INSERT INTO outbox_events(id, company_id, recipient_id, type, object_id, body, dedup_key)
SELECT 'review-migration-v24-unassigned:' || r.id || ':' || recipient.id,
       r.company_id, recipient.id, 'REVIEW_UNASSIGNED', r.id, '{}'::jsonb,
       'review-migration-v24-unassigned:' || r.id || ':' || recipient.id
FROM review_requests r
JOIN users recipient ON recipient.company_id = r.company_id
WHERE r.status = 'PENDING' AND r.kind <> 'LOG'
  AND NOT EXISTS (SELECT 1 FROM review_steps s WHERE s.request_id = r.id AND s.state = 'PENDING')
  AND recipient.status = 'ACTIVE' AND NOT recipient.must_change_password
  AND (recipient.id = r.applicant_id OR recipient.role = 'ADMIN')
ON CONFLICT (dedup_key) DO NOTHING;
