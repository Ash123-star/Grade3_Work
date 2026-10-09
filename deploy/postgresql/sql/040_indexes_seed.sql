CREATE INDEX users_department_idx ON users(company_id, department_id, membership_status);
CREATE INDEX users_team_idx ON users(company_id, team_id, membership_status);
CREATE INDEX reporting_manager_idx ON reporting_relations(company_id, manager_id);
CREATE INDEX tasks_assignee_due_idx ON tasks(company_id, primary_assignee_id, due_at) WHERE archived_at IS NULL;
CREATE INDEX tasks_creator_idx ON tasks(company_id, created_by, created_at DESC);
CREATE INDEX task_events_timeline_idx ON task_events(company_id, task_id, created_at, id);
CREATE INDEX task_assignees_user_idx ON task_assignees(company_id, user_id);
CREATE INDEX daily_logs_range_idx ON daily_logs(company_id, business_date, user_id) WHERE status = 'submitted';
CREATE INDEX reviews_pending_idx ON review_requests(company_id, created_at) WHERE status = 'pending';
CREATE INDEX review_steps_reviewer_idx ON review_steps(company_id, reviewer_id) WHERE status = 'pending';
CREATE INDEX audit_records_time_idx ON audit_records(company_id, created_at DESC);
CREATE INDEX notifications_unread_idx ON notifications(company_id, recipient_id, created_at DESC) WHERE read_at IS NULL;
CREATE INDEX outbox_pending_idx ON outbox_events(available_at, created_at) WHERE published_at IS NULL;
CREATE INDEX ai_jobs_owner_idx ON ai_jobs(company_id, requested_by, created_at DESC);
CREATE INDEX ai_jobs_queue_idx ON ai_jobs(created_at) WHERE status = 'queued';
CREATE INDEX ai_map_nodes_owner_idx ON ai_map_nodes(company_id, owner_id);

-- 固定引导公司 ID；仅基础组织，不创建默认密码或演示业务数据。
INSERT INTO companies(id, name) VALUES ('00000000-0000-0000-0000-000000000001', '企业协作');
INSERT INTO departments(company_id, name)
SELECT '00000000-0000-0000-0000-000000000001'::uuid, name
FROM (VALUES ('产品部'), ('市场部'), ('技术部')) AS defaults(name);
INSERT INTO roles(company_id, code, name, data_scope)
SELECT '00000000-0000-0000-0000-000000000001'::uuid, code, name, scope
FROM (VALUES ('admin', '管理员', 'company'), ('founder', '创始人', 'company'),
    ('department_head', '部门老总', 'department'), ('team_lead', '团队长', 'team'),
    ('employee', '员工', 'self')) AS defaults(code, name, scope);
INSERT INTO permissions(company_id, code, name)
SELECT '00000000-0000-0000-0000-000000000001'::uuid, code, name
FROM (VALUES ('organization.manage', '组织配置'), ('role.manage', '角色授权'),
    ('task.dispatch', '任务派发'), ('task.feedback', '任务反馈'),
    ('log.write', '本人日志'), ('log.read_subordinates', '下属日志'),
    ('dashboard.publish', '公司内容发布'), ('review.decide', '独立复核'),
    ('analytics.read', '范围统计'), ('ai.use', 'AI建议')) AS defaults(code, name);
INSERT INTO role_permissions(company_id, role_id, permission_id)
SELECT r.company_id, r.id, p.id FROM roles r JOIN permissions p ON p.company_id = r.company_id
WHERE r.code = 'admin'
    OR (p.code IN ('task.feedback', 'log.write', 'ai.use'))
    OR (r.code IN ('founder', 'department_head', 'team_lead') AND p.code IN
        ('task.dispatch', 'log.read_subordinates', 'dashboard.publish', 'review.decide', 'analytics.read'));
INSERT INTO audit_records(company_id, action, object_type, object_id, reason, after_value)
VALUES ('00000000-0000-0000-0000-000000000001', 'bootstrap.schema', 'company',
    '00000000-0000-0000-0000-000000000001', 'V001 数据基础初始化；管理员由后续服务端安全初始化',
    '{"departments":3,"roles":5,"default_admin_created":false}'::jsonb);
