CREATE TABLE commerce_imports (
    company_id text NOT NULL REFERENCES companies(id),
    id text NOT NULL,
    sha256 varchar(64) NOT NULL CHECK (sha256 ~ '^[0-9a-f]{64}$'),
    actor_id text NOT NULL,
    imported_at timestamptz NOT NULL DEFAULT now(),
    member_applied integer NOT NULL DEFAULT 0 CHECK (member_applied >= 0),
    member_unchanged integer NOT NULL DEFAULT 0 CHECK (member_unchanged >= 0),
    member_stale integer NOT NULL DEFAULT 0 CHECK (member_stale >= 0),
    order_applied integer NOT NULL DEFAULT 0 CHECK (order_applied >= 0),
    order_unchanged integer NOT NULL DEFAULT 0 CHECK (order_unchanged >= 0),
    order_stale integer NOT NULL DEFAULT 0 CHECK (order_stale >= 0),
    PRIMARY KEY (company_id, id),
    UNIQUE (company_id, sha256),
    FOREIGN KEY (company_id, actor_id) REFERENCES users(company_id, id)
);

CREATE TABLE commerce_members (
    company_id text NOT NULL REFERENCES companies(id),
    external_member_id varchar(200) NOT NULL CHECK (length(trim(external_member_id)) > 0),
    level varchar(100) NOT NULL,
    status varchar(16) NOT NULL CHECK (status IN ('ACTIVE', 'EXPIRED', 'DISABLED')),
    joined_at date,
    expires_at date,
    source_updated_at timestamptz NOT NULL,
    import_id text NOT NULL,
    source_row integer NOT NULL CHECK (source_row BETWEEN 1 AND 500),
    PRIMARY KEY (company_id, external_member_id),
    FOREIGN KEY (company_id, import_id) REFERENCES commerce_imports(company_id, id),
    CHECK (expires_at >= joined_at)
);

CREATE TABLE commerce_orders (
    company_id text NOT NULL REFERENCES companies(id),
    external_order_id varchar(200) NOT NULL CHECK (length(trim(external_order_id)) > 0),
    external_member_id varchar(200),
    status varchar(24) NOT NULL CHECK (status IN (
        'PENDING_PAYMENT', 'PAID', 'COMPLETED', 'CANCELLED', 'REFUNDED', 'PARTIALLY_REFUNDED'
    )),
    currency varchar(3) NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
    amount numeric(19,4) NOT NULL CHECK (amount >= 0),
    ordered_at timestamptz NOT NULL,
    source_updated_at timestamptz NOT NULL CHECK (source_updated_at >= ordered_at),
    import_id text NOT NULL,
    source_row integer NOT NULL CHECK (source_row BETWEEN 1 AND 500),
    PRIMARY KEY (company_id, external_order_id),
    FOREIGN KEY (company_id, external_member_id) REFERENCES commerce_members(company_id, external_member_id),
    FOREIGN KEY (company_id, import_id) REFERENCES commerce_imports(company_id, id)
);

CREATE INDEX commerce_orders_date_idx ON commerce_orders(company_id, ordered_at DESC, external_order_id);
CREATE INDEX commerce_orders_member_date_idx
    ON commerce_orders(company_id, external_member_id, ordered_at DESC, external_order_id);
