-- 全部测试数据在事务末尾回滚，不污染正式数据。
BEGIN;
DO $test$
DECLARE
    company_a uuid := '00000000-0000-0000-0000-000000000001';
    company_b uuid := gen_random_uuid();
    user_a uuid := gen_random_uuid();
    user_b uuid := gen_random_uuid();
    user_c uuid := gen_random_uuid();
    department_a uuid;
    department_other uuid;
    team_a uuid := gen_random_uuid();
    task_a uuid := gen_random_uuid();
    review_a uuid := gen_random_uuid();
BEGIN
    SELECT id INTO department_a FROM departments WHERE company_id = company_a AND name = '产品部';
    SELECT id INTO department_other FROM departments WHERE company_id = company_a AND name = '市场部';
    INSERT INTO teams(id, company_id, department_id, name) VALUES (team_a, company_a, department_a, '验证团队');
    INSERT INTO companies(id, name) VALUES (company_b, 'verification-only');
    INSERT INTO roles(company_id, code, name, data_scope) VALUES (company_b, 'employee', '员工', 'self');
    INSERT INTO users(id, company_id, username, password_hash, phone, display_name, department_id)
    VALUES (user_a, company_a, 'verify-' || user_a, 'test-only-not-a-login-hash', '19900000001', '验证A', department_a),
           (user_b, company_a, 'verify-' || user_b, 'test-only-not-a-login-hash', '19900000002', '验证B', department_a);
    INSERT INTO users(id, company_id, username, password_hash, phone, display_name)
    VALUES (user_c, company_b, 'verify-' || user_c, 'test-only-not-a-login-hash', '19900000003', '验证C');
    IF NOT EXISTS (SELECT 1 FROM users WHERE id = user_a AND membership_status = 'pending')
       OR NOT EXISTS (SELECT 1 FROM user_roles ur JOIN roles r ON r.id = ur.role_id
                      WHERE ur.user_id = user_a AND r.code = 'employee') THEN
        RAISE EXCEPTION 'default pending employee assertion failed';
    END IF;

    BEGIN
        UPDATE users SET department_id = department_a WHERE id = user_c;
        RAISE EXCEPTION 'cross-company department accepted';
    EXCEPTION WHEN foreign_key_violation THEN NULL; END;
    BEGIN
        UPDATE users SET department_id = department_other, team_id = team_a WHERE id = user_a;
        RAISE EXCEPTION 'team outside selected department accepted';
    EXCEPTION WHEN foreign_key_violation THEN NULL; END;
    BEGIN
        INSERT INTO users(company_id, username, password_hash, phone, display_name)
        VALUES (company_b, 'duplicate-phone', 'test-only', '19900000001', '重复手机号');
        RAISE EXCEPTION 'duplicate phone accepted';
    EXCEPTION WHEN unique_violation THEN NULL; END;

    INSERT INTO reporting_relations(company_id, employee_id, manager_id) VALUES (company_a, user_a, user_b);
    BEGIN
        INSERT INTO reporting_relations(company_id, employee_id, manager_id) VALUES (company_a, user_b, user_a);
        RAISE EXCEPTION 'reporting cycle accepted';
    EXCEPTION WHEN check_violation THEN NULL; END;

    INSERT INTO daily_logs(company_id, user_id, business_date) VALUES (company_a, user_a, DATE '2099-01-01');
    BEGIN
        INSERT INTO daily_logs(company_id, user_id, business_date) VALUES (company_a, user_a, DATE '2099-01-01');
        RAISE EXCEPTION 'duplicate daily log accepted';
    EXCEPTION WHEN unique_violation THEN NULL; END;

    INSERT INTO tasks(id, company_id, title, due_at, created_by, primary_assignee_id, idempotency_key)
    VALUES (task_a, company_a, '验证任务', now() + interval '1 day', user_a, user_b, 'verify-key');
    BEGIN
        INSERT INTO tasks(company_id, title, due_at, created_by, primary_assignee_id, idempotency_key)
        VALUES (company_a, '重复任务', now(), user_a, user_b, 'verify-key');
        RAISE EXCEPTION 'duplicate dispatch key accepted';
    EXCEPTION WHEN unique_violation THEN NULL; END;
    BEGIN
        INSERT INTO task_assignees(company_id, task_id, user_id) VALUES (company_a, task_a, user_c);
        RAISE EXCEPTION 'cross-company collaborator accepted';
    EXCEPTION WHEN foreign_key_violation THEN NULL; END;

    INSERT INTO review_requests(id, company_id, applicant_id, object_type, object_id, base_version, candidate_value, reason)
    VALUES (review_a, company_a, user_a, 'task', task_a, 1, '{"title":"修改建议"}', '验证复核');
    BEGIN
        INSERT INTO review_steps(company_id, review_request_id, applicant_id, reviewer_id, step_order)
        VALUES (company_a, review_a, user_a, user_a, 1);
        RAISE EXCEPTION 'self-review accepted';
    EXCEPTION WHEN check_violation THEN NULL; END;
    BEGIN
        -- 不能伪造申请人字段绕过自审约束。
        INSERT INTO review_steps(company_id, review_request_id, applicant_id, reviewer_id, step_order)
        VALUES (company_a, review_a, user_b, user_a, 1);
        RAISE EXCEPTION 'forged applicant accepted';
    EXCEPTION WHEN foreign_key_violation THEN NULL; END;
    INSERT INTO review_steps(company_id, review_request_id, applicant_id, reviewer_id, step_order)
    VALUES (company_a, review_a, user_a, user_b, 1);
    BEGIN
        UPDATE review_steps SET status = 'rejected', decided_at = now()
        WHERE company_id = company_a AND review_request_id = review_a;
        RAISE EXCEPTION 'rejection without reason accepted';
    EXCEPTION WHEN check_violation THEN NULL; END;

    INSERT INTO dashboard_items(company_id, audience, item_type, title, pinned_position, created_by)
    VALUES (company_a, 'company', 'highlight', '验证重点', 1, user_a);
    BEGIN
        INSERT INTO dashboard_items(company_id, audience, item_type, title, pinned_position, created_by)
        VALUES (company_a, 'company', 'highlight', '重复置顶位置', 1, user_a);
        RAISE EXCEPTION 'duplicate pinned position accepted';
    EXCEPTION WHEN unique_violation THEN NULL; END;
    BEGIN
        INSERT INTO dashboard_items(company_id, audience, item_type, title, pinned_position, created_by)
        VALUES (company_a, 'company', 'highlight', '超额置顶', 11, user_a);
        RAISE EXCEPTION 'pin beyond ten accepted';
    EXCEPTION WHEN check_violation THEN NULL; END;
    RAISE NOTICE 'business integrity checks passed (12 negative cases plus employee defaults)';
END
$test$;
ROLLBACK;
