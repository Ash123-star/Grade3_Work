-- 二期 C：统一客户档案、商城会员、年卡权益、核销记录与服务进度。
CREATE TABLE customers (
    id text PRIMARY KEY,
    company_id text NOT NULL,
    kind varchar(16) NOT NULL CHECK (kind IN ('INDIVIDUAL','ENTERPRISE')),
    name varchar(200) NOT NULL CHECK (length(trim(name)) > 0),
    phone varchar(40) NOT NULL DEFAULT '',
    email varchar(200) NOT NULL DEFAULT '',
    external_id varchar(200),
    note varchar(2000) NOT NULL DEFAULT '',
    status varchar(16) NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','ARCHIVED')),
    version integer NOT NULL DEFAULT 1 CHECK (version > 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (company_id) REFERENCES companies(id),
    UNIQUE (company_id, id)
);
CREATE UNIQUE INDEX customers_external_idx ON customers(company_id, external_id)
    WHERE external_id IS NOT NULL AND external_id <> '';
CREATE INDEX customers_list_idx ON customers(company_id, status, kind, name, id);

CREATE TABLE customer_memberships (
    customer_id text PRIMARY KEY,
    company_id text NOT NULL,
    mall_member_id varchar(200) NOT NULL CHECK (length(trim(mall_member_id)) > 0),
    level varchar(100) NOT NULL DEFAULT '',
    joined_at date,
    expires_at date,
    status varchar(16) NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','EXPIRED','DISABLED')),
    version integer NOT NULL DEFAULT 1 CHECK (version > 0),
    updated_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (company_id, customer_id) REFERENCES customers(company_id, id)
);
CREATE UNIQUE INDEX customer_memberships_mall_idx ON customer_memberships(company_id, mall_member_id);

CREATE TABLE customer_benefits (
    id text PRIMARY KEY,
    company_id text NOT NULL,
    customer_id text NOT NULL,
    kind varchar(32) NOT NULL CHECK (kind IN ('ANNUAL_CARD','MALL_MEMBER','OTHER')),
    name varchar(200) NOT NULL CHECK (length(trim(name)) > 0),
    valid_from date NOT NULL,
    valid_to date NOT NULL,
    max_uses integer CHECK (max_uses IS NULL OR max_uses > 0),
    status varchar(16) NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','DISABLED')),
    version integer NOT NULL DEFAULT 1 CHECK (version > 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (valid_to >= valid_from),
    FOREIGN KEY (company_id, customer_id) REFERENCES customers(company_id, id)
);
CREATE INDEX customer_benefits_customer_idx ON customer_benefits(company_id, customer_id, valid_to, id);

CREATE TABLE customer_benefit_redemptions (
    id text PRIMARY KEY,
    company_id text NOT NULL,
    benefit_id text NOT NULL,
    customer_id text NOT NULL,
    event_key varchar(128) NOT NULL CHECK (length(trim(event_key)) > 0),
    redeemed_at timestamptz NOT NULL DEFAULT now(),
    note varchar(500) NOT NULL DEFAULT '',
    FOREIGN KEY (company_id, customer_id) REFERENCES customers(company_id, id),
    FOREIGN KEY (benefit_id) REFERENCES customer_benefits(id),
    UNIQUE (company_id, benefit_id, event_key)
);
CREATE INDEX customer_benefit_redemptions_benefit_idx ON customer_benefit_redemptions(company_id, benefit_id, redeemed_at);

CREATE TABLE customer_progress (
    id text PRIMARY KEY,
    company_id text NOT NULL,
    customer_id text NOT NULL,
    stage varchar(100) NOT NULL CHECK (length(trim(stage)) > 0),
    note varchar(1000) NOT NULL DEFAULT '',
    actor_id text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (company_id, customer_id) REFERENCES customers(company_id, id)
);
CREATE INDEX customer_progress_customer_idx ON customer_progress(company_id, customer_id, created_at, id);
