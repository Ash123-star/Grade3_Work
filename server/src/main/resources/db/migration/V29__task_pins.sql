-- 个人任务置顶：只影响本人任务管理列表，不改变任务版本，不走审核。
CREATE TABLE task_pins (
    user_id text NOT NULL,
    task_id text NOT NULL,
    company_id text NOT NULL,
    pinned_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, task_id),
    FOREIGN KEY (company_id, user_id) REFERENCES users(company_id, id) ON DELETE CASCADE,
    FOREIGN KEY (company_id, task_id) REFERENCES tasks(company_id, id) ON DELETE CASCADE
);
CREATE INDEX task_pins_user_recent ON task_pins(user_id, pinned_at DESC);
