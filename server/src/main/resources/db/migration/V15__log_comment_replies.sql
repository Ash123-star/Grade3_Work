ALTER TABLE log_comments ADD COLUMN parent_id text;
ALTER TABLE log_comments ADD CONSTRAINT log_comment_log_id_unique UNIQUE (company_id,log_id,id);
ALTER TABLE log_comments ADD CONSTRAINT log_comment_parent_same_log FOREIGN KEY (company_id,log_id,parent_id) REFERENCES log_comments(company_id,log_id,id);
CREATE INDEX log_comments_log_time ON log_comments(log_id,created_at,id);
