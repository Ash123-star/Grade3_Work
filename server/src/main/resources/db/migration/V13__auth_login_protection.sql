-- 登录失败状态独立于用户，未知账号也采用统一凭据失败行为；不保存账号明文或密码。
CREATE TABLE auth_login_state (
    account_hash VARCHAR(64) PRIMARY KEY CHECK (account_hash ~ '^[0-9a-f]{64}$'),
    failures INTEGER NOT NULL DEFAULT 0 CHECK (failures BETWEEN 0 AND 5),
    locked_until TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX auth_login_state_updated_at_idx ON auth_login_state(updated_at);
