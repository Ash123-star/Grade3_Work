-- Private daily todos: optional end date and per-item bar colour.
ALTER TABLE personal_todos ADD COLUMN end_date date;
UPDATE personal_todos SET end_date = business_date;
ALTER TABLE personal_todos ALTER COLUMN end_date SET NOT NULL;
ALTER TABLE personal_todos ADD CONSTRAINT personal_todos_date_range CHECK (end_date >= business_date);
ALTER TABLE personal_todos ADD COLUMN color varchar(7) NOT NULL DEFAULT '#F3A45D';
ALTER TABLE personal_todos ADD CONSTRAINT personal_todos_color_hex CHECK (color ~ '^#[0-9A-Fa-f]{6}$');
CREATE INDEX personal_todos_span_idx ON personal_todos(company_id,owner_id,business_date,end_date)
    WHERE deleted_at IS NULL;
