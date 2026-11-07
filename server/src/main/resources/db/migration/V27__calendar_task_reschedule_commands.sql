-- 改期幂等结果与审核同事务保存；保留期不短于审核记录，不按客户端超时清理。
CREATE TABLE task_reschedule_commands (
    company_id text NOT NULL,
    actor_id text NOT NULL,
    idempotency_key varchar(128) NOT NULL CHECK (idempotency_key ~ '^[!-~]{1,128}$'),
    task_id text NOT NULL,
    review_id text NOT NULL,
    request_hash text NOT NULL,
    hash_version integer NOT NULL CHECK (hash_version = 1),
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (company_id,actor_id,idempotency_key),
    FOREIGN KEY (company_id,actor_id) REFERENCES users(company_id,id),
    FOREIGN KEY (company_id,task_id) REFERENCES tasks(company_id,id),
    FOREIGN KEY (company_id,review_id) REFERENCES review_requests(company_id,id)
);
CREATE INDEX review_pending_task_move ON review_requests(company_id,target_id,expected_version)
    WHERE kind='TASK_RESCHEDULE' AND status='PENDING' AND candidate->>'scheduleMode'='MOVE';
CREATE INDEX tasks_calendar_interval ON tasks(company_id,deadline,start_at,id);
