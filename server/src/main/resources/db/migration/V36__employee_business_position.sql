-- 业务职位与系统角色独立；该标记不授予管理员权限，不自动改变现有汇报关系。
ALTER TABLE users ADD COLUMN business_position text NOT NULL DEFAULT 'NONE';
ALTER TABLE users ADD CONSTRAINT users_business_position_valid
    CHECK (business_position IN ('NONE','GENERAL_MANAGER','DEPUTY_GENERAL_MANAGER'));
