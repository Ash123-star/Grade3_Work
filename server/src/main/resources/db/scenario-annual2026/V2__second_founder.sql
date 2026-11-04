-- 多创始人互审演示：年度场景主公司追加第二位在职创始人（账号 boss2）。
-- 在 V1 之后执行；只追加成员，不修改已有成员、汇报关系或历史审核。
DO $founder$
DECLARE
    c text := 'annual-cm';
BEGIN
    LOCK TABLE users IN SHARE ROW EXCLUSIVE MODE;
    IF NOT EXISTS(SELECT 1 FROM users WHERE id='annual-founder' AND company_id=c AND role='FOUNDER') THEN
        RAISE EXCEPTION '年度场景创始人缺失，拒绝追加第二位创始人';
    END IF;
    IF EXISTS(SELECT 1 FROM users WHERE id='annual-cofounder' OR account='boss2') THEN
        RAISE EXCEPTION '第二位创始人ID或账号boss2已被占用，整批回滚';
    END IF;
    INSERT INTO users(id,company_id,account,password_hash,name,role,status,must_change_password,
      dispatch_enabled,company_reviewer,profile,email,employment_start_date,created_at)
    SELECT 'annual-cofounder',c,'boss2','${scenarioPasswordHash}','钟以宁','FOUNDER','ACTIVE',false,true,false,
      jsonb_build_object('introduction','钟以宁负责客户合作与经营复核，与创始团队共同评审关键变更。','seedSource','annual-2026-v2'),
      'boss2@chengming.example',f.employment_start_date,f.created_at
    FROM users f WHERE f.id='annual-founder';
    INSERT INTO user_roles VALUES('annual-cofounder','FOUNDER');
    INSERT INTO audit_records(company_id,actor_id,type,object_id,before_value,after_value,reason)
      VALUES(c,'annual-cofounder','SCENARIO_SECOND_FOUNDER_ADDED','annual-cofounder','{}',
        jsonb_build_object('account','boss2','role','FOUNDER'),'年度场景V2：解除单创始人演示限制，用于创始人互审');
END
$founder$;
