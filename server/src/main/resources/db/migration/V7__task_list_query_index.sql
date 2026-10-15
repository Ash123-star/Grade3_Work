-- 任务列表按公司、截止时间和 ID 稳定分页；不修改任务业务数据。
CREATE INDEX tasks_company_deadline_id ON tasks(company_id, deadline, id);
