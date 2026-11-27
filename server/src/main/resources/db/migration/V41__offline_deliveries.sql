ALTER TABLE review_requests DROP CONSTRAINT review_requests_kind_valid;
ALTER TABLE review_requests ADD CONSTRAINT review_requests_kind_valid CHECK (kind IN (
    'MEMBERSHIP', 'REVIEWER', 'POLICY', 'USER', 'DEPARTMENT', 'TEAM',
    'COMPANY_ITEM', 'LOG', 'TASK', 'TASK_REASSIGN', 'TASK_RESCHEDULE',
    'MEMORY', 'PROCEDURE', 'TASK_CREATE', 'TASK_DELETE', 'OFFLINE_DELIVERY'
));

CREATE TABLE offline_deliveries (
    id text PRIMARY KEY,
    company_id text NOT NULL,
    customer_id text NOT NULL,
    owner_id text NOT NULL,
    kind text NOT NULL CHECK (kind IN ('PERFORMANCE','PRIVATE_BANQUET','COMPANY_VISIT','SALON')),
    title varchar(120) NOT NULL CHECK (btrim(title) <> ''),
    business_date date NOT NULL,
    activity_status text NOT NULL DEFAULT 'SCHEDULED' CHECK (activity_status IN ('SCHEDULED','ENDED')),
    delivery_status text NOT NULL DEFAULT 'PENDING' CHECK (delivery_status IN ('PENDING','DELIVERED')),
    ended_at timestamptz,
    delivered_at timestamptz,
    version integer NOT NULL DEFAULT 1 CHECK (version > 0),
    UNIQUE (company_id, id),
    FOREIGN KEY (company_id, customer_id) REFERENCES customers(company_id, id),
    FOREIGN KEY (company_id, owner_id) REFERENCES users(company_id, id),
    CHECK ((activity_status = 'ENDED') = (ended_at IS NOT NULL)),
    CHECK ((delivery_status = 'DELIVERED') = (delivered_at IS NOT NULL)),
    CHECK (delivered_at IS NULL OR (ended_at IS NOT NULL AND delivered_at >= ended_at))
);
CREATE INDEX offline_deliveries_customer_idx ON offline_deliveries(company_id, customer_id, business_date DESC, id);
CREATE INDEX offline_deliveries_owner_idx ON offline_deliveries(company_id, owner_id, business_date DESC, id);

CREATE TABLE offline_delivery_participants (
    company_id text NOT NULL,
    delivery_id text NOT NULL,
    employee_id text NOT NULL,
    PRIMARY KEY (company_id, delivery_id, employee_id),
    FOREIGN KEY (company_id, delivery_id) REFERENCES offline_deliveries(company_id, id),
    FOREIGN KEY (company_id, employee_id) REFERENCES users(company_id, id)
);
CREATE INDEX offline_delivery_participants_employee_idx ON offline_delivery_participants(company_id, employee_id, delivery_id);

CREATE UNIQUE INDEX offline_delivery_single_pending_idx ON review_requests(company_id, target_id)
    WHERE kind = 'OFFLINE_DELIVERY' AND status = 'PENDING';

CREATE TABLE offline_delivery_commands (
    company_id text NOT NULL,
    actor_id text NOT NULL,
    key varchar(128) NOT NULL,
    request_hash char(64) NOT NULL,
    receipt jsonb NOT NULL CHECK (jsonb_typeof(receipt) = 'object'),
    PRIMARY KEY (company_id, actor_id, key),
    FOREIGN KEY (company_id, actor_id) REFERENCES users(company_id, id)
);
