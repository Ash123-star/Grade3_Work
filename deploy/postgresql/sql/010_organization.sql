-- 组织和权限。公司组合外键防止跨租户引用；应用仍须逐次鉴权。
CREATE TABLE companies (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL CHECK (btrim(name) <> ''),
    timezone text NOT NULL DEFAULT 'Asia/Shanghai',
    version integer NOT NULL DEFAULT 1 CHECK (version > 0),
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE departments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES companies(id),
    name text NOT NULL CHECK (btrim(name) <> ''),
    version integer NOT NULL DEFAULT 1 CHECK (version > 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (company_id, id), UNIQUE (company_id, name)
);
CREATE TABLE teams (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES companies(id),
    department_id uuid NOT NULL,
    name text NOT NULL CHECK (btrim(name) <> ''),
    version integer NOT NULL DEFAULT 1 CHECK (version > 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (company_id, id), UNIQUE (company_id, department_id, id),
    UNIQUE (company_id, department_id, name),
    FOREIGN KEY (company_id, department_id) REFERENCES departments(company_id, id)
);
CREATE TABLE users (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES companies(id),
    username text NOT NULL CHECK (btrim(username) <> ''),
    password_hash text NOT NULL CHECK (btrim(password_hash) <> ''),
    phone text NOT NULL UNIQUE CHECK (phone ~ '^\+?[0-9]{7,15}$'),
    display_name text NOT NULL CHECK (btrim(display_name) <> ''),
    department_id uuid,
    team_id uuid,
    membership_status text NOT NULL DEFAULT 'pending'
        CHECK (membership_status IN ('pending', 'active', 'disabled')),
    must_change_password boolean NOT NULL DEFAULT false,
    session_version integer NOT NULL DEFAULT 1 CHECK (session_version > 0),
    avatar_url text, introduction text,
    version integer NOT NULL DEFAULT 1 CHECK (version > 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (team_id IS NULL OR department_id IS NOT NULL),
    UNIQUE (company_id, id), UNIQUE (company_id, username),
    FOREIGN KEY (company_id, department_id) REFERENCES departments(company_id, id),
    FOREIGN KEY (company_id, department_id, team_id) REFERENCES teams(company_id, department_id, id)
);
CREATE TABLE roles (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES companies(id),
    code text NOT NULL CHECK (code IN ('admin', 'founder', 'department_head', 'team_lead', 'employee')),
    name text NOT NULL,
    data_scope text NOT NULL CHECK (data_scope IN ('self', 'team', 'department', 'company')),
    UNIQUE (company_id, id), UNIQUE (company_id, code)
);
CREATE TABLE permissions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES companies(id),
    code text NOT NULL, name text NOT NULL,
    UNIQUE (company_id, id), UNIQUE (company_id, code)
);
CREATE TABLE role_permissions (
    company_id uuid NOT NULL REFERENCES companies(id),
    role_id uuid NOT NULL, permission_id uuid NOT NULL,
    PRIMARY KEY (company_id, role_id, permission_id),
    FOREIGN KEY (company_id, role_id) REFERENCES roles(company_id, id),
    FOREIGN KEY (company_id, permission_id) REFERENCES permissions(company_id, id)
);
CREATE TABLE user_roles (
    company_id uuid NOT NULL REFERENCES companies(id),
    user_id uuid NOT NULL, role_id uuid NOT NULL, granted_by uuid,
    granted_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (company_id, user_id, role_id),
    FOREIGN KEY (company_id, user_id) REFERENCES users(company_id, id),
    FOREIGN KEY (company_id, role_id) REFERENCES roles(company_id, id),
    FOREIGN KEY (company_id, granted_by) REFERENCES users(company_id, id)
);
CREATE TABLE reporting_relations (
    company_id uuid NOT NULL REFERENCES companies(id),
    employee_id uuid NOT NULL, manager_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (company_id, employee_id),
    CHECK (employee_id <> manager_id),
    FOREIGN KEY (company_id, employee_id) REFERENCES users(company_id, id),
    FOREIGN KEY (company_id, manager_id) REFERENCES users(company_id, id)
);

CREATE FUNCTION prevent_reporting_cycle() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    -- 公司行锁串行化关系修改，防止并发形成循环。
    PERFORM 1 FROM companies WHERE id = NEW.company_id FOR UPDATE;
    IF EXISTS (
        WITH RECURSIVE ancestors(id) AS (
            SELECT NEW.manager_id
            UNION
            SELECT r.manager_id FROM reporting_relations r JOIN ancestors a ON r.employee_id = a.id
            WHERE r.company_id = NEW.company_id
        ) SELECT 1 FROM ancestors WHERE id = NEW.employee_id
    ) THEN
        RAISE EXCEPTION 'reporting relation cycle' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER reporting_cycle_guard BEFORE INSERT OR UPDATE ON reporting_relations
    FOR EACH ROW EXECUTE FUNCTION prevent_reporting_cycle();

CREATE FUNCTION assign_default_employee_role() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE employee_role uuid;
BEGIN
    SELECT id INTO employee_role FROM roles WHERE company_id = NEW.company_id AND code = 'employee';
    IF employee_role IS NULL THEN
        RAISE EXCEPTION 'company employee role must be initialized first';
    END IF;
    INSERT INTO user_roles(company_id, user_id, role_id) VALUES (NEW.company_id, NEW.id, employee_role);
    RETURN NEW;
END $$;
CREATE TRIGGER user_default_employee AFTER INSERT ON users
    FOR EACH ROW EXECUTE FUNCTION assign_default_employee_role();
