-- 用户要求的测试账号简化；仅由显式启用的场景Flyway执行。
-- 密码来自部署SCENARIO_PASSWORD；不修改正式用户或已发布迁移。
DO $accounts$
DECLARE
    entry record;
    member users%ROWTYPE;
BEGIN
    -- 与并发注册串行化，冲突时整批回滚。
    LOCK TABLE users IN SHARE ROW EXCLUSIVE MODE;
    FOR entry IN SELECT * FROM (VALUES
      ('founder','boss'),('admin','admin'),
      ('product-director','pd'),('engineering-director','rd'),('delivery-director','dd'),
      ('product-lead','pl'),('design-lead','dl'),('backend-lead','bl'),('delivery-lead','tl'),
      ('chen','chen'),('lin','lin'),('he','he'),('xu','xu'),('zhou','zhou'),('zhao','zhao'),
      ('tang','tang'),('luo','luo'),('pending','new1'),('pending-delivery','new2'),
      ('disabled','off'),('outsider','other')
    ) AS names(key,login) LOOP
        SELECT * INTO member FROM users WHERE id='scenario-'||entry.key
          AND company_id=CASE WHEN entry.key='outsider' THEN 'scenario-peer' ELSE 'scenario-cm' END
          AND profile->>'seedSource'='flyway-scenario-v1'
          AND account='scenario.'||entry.key;
        IF NOT FOUND THEN
            RAISE EXCEPTION '场景成员缺失或已修改，拒绝覆盖: %',entry.key;
        END IF;
        IF EXISTS(SELECT 1 FROM users WHERE account=entry.login AND id<>member.id) THEN
            RAISE EXCEPTION '短账号已被占用，整批回滚: %',entry.login;
        END IF;
        UPDATE users SET account=entry.login,password_hash='${scenarioPasswordHash}'
          WHERE id=member.id;
        DELETE FROM sessions WHERE user_id=member.id;
        INSERT INTO audit_records(company_id,actor_id,type,object_id,before_value,after_value,reason)
          VALUES(member.company_id,member.id,'SCENARIO_LOGIN_SIMPLIFIED',member.id,
            jsonb_build_object('account',member.account),jsonb_build_object('account',entry.login),
            '场景V3：按用户要求简化测试账号并更新测试密码，撤销旧会话');
    END LOOP;
END
$accounts$;
