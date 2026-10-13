-- 固化后端运行数据库的业务完整性；V1-V3 不再修改。
CREATE TABLE log_tasks (
    company_id text NOT NULL REFERENCES companies(id),
    log_id text NOT NULL,
    task_id text NOT NULL,
    PRIMARY KEY (company_id, log_id, task_id),
    FOREIGN KEY (company_id, log_id) REFERENCES daily_logs(company_id, id),
    FOREIGN KEY (company_id, task_id) REFERENCES tasks(company_id, id)
);

INSERT INTO log_tasks(company_id, log_id, task_id)
SELECT l.company_id, l.id, value
FROM daily_logs l
CROSS JOIN LATERAL jsonb_array_elements_text(
    CASE WHEN jsonb_typeof(l.body->'taskIds') = 'array'
         THEN l.body->'taskIds' ELSE '[]'::jsonb END
) AS ids(value);

CREATE INDEX log_tasks_task ON log_tasks(company_id, task_id, log_id);

CREATE FUNCTION prevent_reporting_cycle() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    PERFORM 1 FROM companies WHERE id = NEW.company_id FOR UPDATE;
    IF EXISTS (
        WITH RECURSIVE ancestors(id) AS (
            SELECT NEW.manager_id
            UNION
            SELECT r.manager_id FROM reporting_relations r
            JOIN ancestors a ON r.employee_id = a.id
            WHERE r.company_id = NEW.company_id
        ) SELECT 1 FROM ancestors WHERE id = NEW.employee_id
    ) THEN
        RAISE EXCEPTION 'reporting relation cycle' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER reporting_cycle_guard BEFORE INSERT OR UPDATE ON reporting_relations
FOR EACH ROW EXECUTE FUNCTION prevent_reporting_cycle();

ALTER TABLE review_requests ADD CONSTRAINT review_requests_company_id_applicant_key UNIQUE (company_id, id, applicant_id);
ALTER TABLE review_steps ADD COLUMN applicant_id text;
UPDATE review_steps s SET applicant_id = r.applicant_id FROM review_requests r WHERE r.id = s.request_id;
ALTER TABLE review_steps ALTER COLUMN applicant_id SET NOT NULL;
ALTER TABLE review_steps
    ADD CONSTRAINT review_steps_not_self_review CHECK (reviewer_id <> applicant_id),
    ADD CONSTRAINT review_steps_request_applicant_fk FOREIGN KEY (company_id, request_id, applicant_id) REFERENCES review_requests(company_id, id, applicant_id),
    ADD CONSTRAINT review_steps_rejection_reason CHECK (state <> 'REJECTED' OR btrim(coalesce(reason, '')) <> '');

ALTER TABLE tasks ADD CONSTRAINT tasks_body_object CHECK (jsonb_typeof(body) = 'object'), ADD CONSTRAINT tasks_version_positive CHECK (version > 0);
ALTER TABLE task_events ADD CONSTRAINT task_events_type_valid CHECK (type IN ('DISPATCHED','RECEIVED','FEEDBACK','ACCEPTED','ARCHIVED','WITHDRAWN','REVISED')), ADD CONSTRAINT task_events_body_object CHECK (jsonb_typeof(body) = 'object');
ALTER TABLE daily_logs ADD CONSTRAINT daily_logs_body_object CHECK (jsonb_typeof(body) = 'object'), ADD CONSTRAINT daily_logs_submission_consistent CHECK ((submitted AND submitted_at IS NOT NULL) OR (NOT submitted AND submitted_at IS NULL));
ALTER TABLE log_versions ADD CONSTRAINT log_versions_body_object CHECK (jsonb_typeof(body) = 'object'), ADD CONSTRAINT log_versions_version_positive CHECK (version > 0);
ALTER TABLE review_requests ADD CONSTRAINT review_requests_kind_valid CHECK (kind IN ('MEMBERSHIP','REVIEWER','POLICY','USER','DEPARTMENT','TEAM','COMPANY_ITEM','LOG','TASK')), ADD CONSTRAINT review_requests_candidate_object CHECK (jsonb_typeof(candidate) = 'object'), ADD CONSTRAINT review_requests_before_object CHECK (jsonb_typeof(before_value) = 'object'), ADD CONSTRAINT review_requests_reason_nonempty CHECK (btrim(reason) <> '');
ALTER TABLE outbox_events ADD CONSTRAINT outbox_events_body_object CHECK (jsonb_typeof(body) = 'object');
ALTER TABLE ai_jobs ADD CONSTRAINT ai_jobs_input_object CHECK (jsonb_typeof(input) = 'object'), ADD CONSTRAINT ai_jobs_output_object CHECK (output IS NULL OR jsonb_typeof(output) = 'object'), ADD CONSTRAINT ai_jobs_tokens_nonnegative CHECK (tokens >= 0);
ALTER TABLE ai_map_nodes ADD CONSTRAINT ai_map_nodes_body_object CHECK (jsonb_typeof(body) = 'object');
ALTER TABLE ai_map_edges ADD CONSTRAINT ai_map_edges_body_object CHECK (jsonb_typeof(body) = 'object');

CREATE INDEX review_steps_pending ON review_steps(company_id, reviewer_id, state, position);
CREATE INDEX log_reads_reader ON log_reads(reader_id, log_id);
