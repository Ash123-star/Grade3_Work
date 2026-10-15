-- 日报列表按公司、提交状态和业务日期读取；不修改存量日报或版本历史。
CREATE INDEX daily_logs_company_submitted_date_id ON daily_logs(company_id, submitted, business_date DESC, id);
