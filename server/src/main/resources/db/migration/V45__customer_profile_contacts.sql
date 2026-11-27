ALTER TABLE customers
    ADD COLUMN owner_id text,
    ADD COLUMN contacts jsonb NOT NULL DEFAULT '[]',
    ADD CONSTRAINT customers_owner_scope_fk FOREIGN KEY (company_id, owner_id) REFERENCES users(company_id, id),
    ADD CONSTRAINT customers_contacts_shape CHECK (
        jsonb_typeof(contacts) = 'array' AND jsonb_array_length(contacts) <= 30
        AND (kind = 'ENTERPRISE' OR contacts = '[]'::jsonb)
    );

CREATE INDEX customers_duplicate_name_idx ON customers(company_id, kind, lower(name)) WHERE status = 'ACTIVE';
CREATE INDEX customers_duplicate_phone_idx ON customers(company_id, phone) WHERE status = 'ACTIVE' AND phone <> '';
CREATE INDEX customers_duplicate_email_idx ON customers(company_id, lower(email)) WHERE status = 'ACTIVE' AND email <> '';
