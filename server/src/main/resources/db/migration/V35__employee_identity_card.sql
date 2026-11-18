-- 身份证号属于受限员工身份资料，只由管理员维护；原有账号无需回填。
ALTER TABLE users ADD COLUMN id_card_number varchar(18);
ALTER TABLE users ADD CONSTRAINT users_id_card_number_format CHECK (id_card_number IS NULL OR id_card_number ~ '^[0-9]{17}[0-9X]$');
CREATE UNIQUE INDEX users_id_card_number_unique ON users(id_card_number) WHERE id_card_number IS NOT NULL;
