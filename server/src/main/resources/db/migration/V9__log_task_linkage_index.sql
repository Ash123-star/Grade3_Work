-- 下属已提交日报按负责人和业务日期读取；草稿不进入该部分索引。
CREATE INDEX daily_logs_submitted_owner_date_id ON daily_logs(company_id, owner_id, business_date DESC, id) WHERE submitted;
