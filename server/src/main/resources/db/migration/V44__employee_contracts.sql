CREATE TABLE hr_grants (
 company_id text NOT NULL REFERENCES companies, user_id text NOT NULL REFERENCES users,
 access text NOT NULL CHECK(access IN ('NONE','READ','MANAGE')), version int NOT NULL DEFAULT 1,
 PRIMARY KEY(company_id,user_id));
CREATE TABLE employee_duties (
 company_id text NOT NULL REFERENCES companies, employee_id text NOT NULL REFERENCES users,
 duties text NOT NULL, version int NOT NULL DEFAULT 1, PRIMARY KEY(company_id,employee_id));
CREATE TABLE employee_contracts (
 id text PRIMARY KEY, company_id text NOT NULL REFERENCES companies, employee_id text NOT NULL REFERENCES users,
 title text NOT NULL CHECK(length(title) BETWEEN 1 AND 200), starts_on date NOT NULL, ends_on date NOT NULL,
 attachment_id text NOT NULL UNIQUE REFERENCES attachments, version int NOT NULL DEFAULT 1,
 created_by text NOT NULL REFERENCES users, created_at timestamptz NOT NULL DEFAULT now(),
 CHECK(ends_on>=starts_on));
CREATE INDEX employee_contracts_expiry ON employee_contracts(ends_on,company_id);
CREATE TABLE contract_recipients (
 contract_id text NOT NULL REFERENCES employee_contracts, user_id text NOT NULL REFERENCES users,
 PRIMARY KEY(contract_id,user_id));

CREATE TABLE employee_contract_versions (
 contract_id text NOT NULL REFERENCES employee_contracts, version int NOT NULL,
 snapshot jsonb NOT NULL, changed_by text NOT NULL REFERENCES users,
 changed_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(contract_id,version));
