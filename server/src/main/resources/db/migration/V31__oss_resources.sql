-- 兼容历史bytea，新增写入只保存OSS引用。原有迁移保持不变。
ALTER TABLE attachments ALTER COLUMN data DROP NOT NULL;
ALTER TABLE attachments ADD COLUMN storage_provider text NOT NULL DEFAULT 'DATABASE' CHECK(storage_provider IN ('DATABASE','OSS'));
ALTER TABLE attachments ADD COLUMN object_key text UNIQUE;
ALTER TABLE attachments ADD COLUMN size_bytes bigint NOT NULL DEFAULT 0 CHECK(size_bytes>=0 AND size_bytes<=10485760);
ALTER TABLE attachments ADD COLUMN storage_state text NOT NULL DEFAULT 'READY' CHECK(storage_state IN ('PENDING','READY','DELETING','DELETED'));
ALTER TABLE attachments ADD COLUMN storage_version bigint NOT NULL DEFAULT 1;
ALTER TABLE attachments ADD COLUMN storage_updated_at timestamptz NOT NULL DEFAULT now();
UPDATE attachments SET size_bytes=octet_length(data),storage_state=CASE WHEN octet_length(data)>0 THEN 'READY' ELSE 'DELETED' END;
ALTER TABLE attachments ADD CONSTRAINT attachment_oss_reference CHECK(storage_provider<>'OSS' OR object_key IS NOT NULL);
CREATE INDEX attachments_storage_pending ON attachments(storage_updated_at) WHERE storage_state='PENDING';
CREATE TABLE storage_delete_jobs (
 object_key text PRIMARY KEY, attachment_id text REFERENCES attachments(id), attempts int NOT NULL DEFAULT 0,
 available_at timestamptz NOT NULL DEFAULT now(), created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE generated_files (
 id text PRIMARY KEY, company_id text NOT NULL, owner_id text NOT NULL, filename text NOT NULL,
 kind text NOT NULL CHECK(kind IN ('EXPORT','TEMPLATE')), sources jsonb NOT NULL,
 attachment_id text NOT NULL UNIQUE REFERENCES attachments(id), created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(company_id,owner_id) REFERENCES users(company_id,id)
);
CREATE TABLE asset_releases (
 id text PRIMARY KEY CHECK(id ~ '^[a-zA-Z0-9_-]{1,80}$'), manifest jsonb NOT NULL,
 manifest_hash text NOT NULL, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE asset_current (id int PRIMARY KEY CHECK(id=1), release_id text REFERENCES asset_releases(id), version bigint NOT NULL DEFAULT 0);
INSERT INTO asset_current(id) VALUES(1);
CREATE TABLE attachment_migrations (
 attachment_id text PRIMARY KEY REFERENCES attachments(id), object_key text NOT NULL UNIQUE,
 file_hash text NOT NULL, size_bytes bigint NOT NULL, expected_version bigint NOT NULL,
 state text NOT NULL CHECK(state IN ('PENDING','READY','CONFLICT')), updated_at timestamptz NOT NULL DEFAULT now()
);
