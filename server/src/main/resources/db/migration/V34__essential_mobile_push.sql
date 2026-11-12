-- V32/V33 are reserved by the parallel integration branch; additive, no historical push replay.
CREATE TABLE push_preferences (
 user_id text PRIMARY KEY, company_id text NOT NULL,
 enabled boolean NOT NULL DEFAULT false, tasks boolean NOT NULL DEFAULT true,
 deadlines boolean NOT NULL DEFAULT true, reviews boolean NOT NULL DEFAULT true,
 quiet_enabled boolean NOT NULL DEFAULT true, quiet_start int NOT NULL DEFAULT 22 CHECK(quiet_start BETWEEN 0 AND 23),
 quiet_end int NOT NULL DEFAULT 8 CHECK(quiet_end BETWEEN 0 AND 23),
 version int NOT NULL DEFAULT 1 CHECK(version>0),
 FOREIGN KEY(company_id,user_id) REFERENCES users(company_id,id), CHECK(quiet_start<>quiet_end)
);
CREATE TABLE push_devices (
 id text PRIMARY KEY, device_id text NOT NULL UNIQUE CHECK(length(device_id) BETWEEN 8 AND 200),
 company_id text NOT NULL, user_id text NOT NULL,
 session_hash text NOT NULL REFERENCES sessions(token_hash) ON DELETE CASCADE,
 binding text NOT NULL, updated_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(company_id,user_id) REFERENCES users(company_id,id)
);
CREATE INDEX push_devices_recipient ON push_devices(company_id,user_id);
CREATE TABLE push_deliveries (
 id text PRIMARY KEY, notification_id text NOT NULL REFERENCES notifications(id),
 device_id text NOT NULL REFERENCES push_devices(id) ON DELETE CASCADE,
 binding text NOT NULL, category text NOT NULL CHECK(category IN ('tasks','deadlines','reviews')),
 task_version int, expires_at timestamptz NOT NULL,
 state text NOT NULL DEFAULT 'PENDING' CHECK(state IN ('PENDING','ACCEPTED','CANCELLED','FAILED')),
 attempts int NOT NULL DEFAULT 0 CHECK(attempts BETWEEN 0 AND 5), next_attempt_at timestamptz NOT NULL DEFAULT now(),
 provider_id text, error_code text, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(notification_id,device_id,binding)
);
CREATE INDEX push_deliveries_pending ON push_deliveries(next_attempt_at) WHERE state='PENDING';
CREATE INDEX push_reminder_deadlines ON tasks(deadline) WHERE phase IN ('DISPATCHED','RECEIVED');
