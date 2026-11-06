-- 仅补齐年度虚构场景；不覆盖用户已填资料，不改变角色、状态或汇报链。
-- Flyway 事务与历史保证整批回滚及只执行一次。000 前缀电话是不可拨打的示例。
DO $enrich$
DECLARE
    person record;
    slot integer;
    tid text;
    label_id text;
    issuer text;
    task_title text;
    content jsonb;
    starts timestamptz := timestamptz '2026-11-06 09:00+08';
    dispatched timestamptz := LEAST(now(), timestamptz '2026-11-06 08:00+08');
    finishes timestamptz;
    titles text[] := ARRAY['核对本周交付清单','补充任务验收材料','整理跨团队协作问题','复核关键字段口径',
                           '跟进本期未关闭事项','准备阶段评审材料','核对异常处理记录','更新下周执行计划'];
BEGIN
    LOCK TABLE users IN SHARE ROW EXCLUSIVE MODE;
    IF NOT EXISTS (SELECT 1 FROM users WHERE id='annual-founder' AND company_id='annual-cm' AND role='FOUNDER') THEN
        RAISE EXCEPTION '年度主创始人缺失，拒绝补齐场景';
    END IF;
    IF EXISTS (SELECT 1 FROM tasks WHERE id LIKE 'annual-calendar-overflow-%') THEN
        RAISE EXCEPTION '月历溢出场景ID已存在，拒绝覆盖';
    END IF;
    INSERT INTO departments(id,company_id,name)
        VALUES('annual-management','annual-cm','综合管理部');
    INSERT INTO teams(id,company_id,department_id,name) VALUES
        ('annual-management-team','annual-cm','annual-management','综合管理组'),
        ('annual-peer-team','annual-peer','annual-peer-dept','运营协作组');

    -- 已有团队不得跨公司或跨部门；缺少部门时只能使用本公司的既有团队部门。
    IF EXISTS (SELECT 1 FROM users u JOIN teams t ON t.id=u.team_id
               WHERE u.company_id IN ('annual-cm','annual-peer') AND u.id LIKE 'annual-%'
                 AND (u.company_id<>t.company_id OR (u.department_id IS NOT NULL AND u.department_id<>t.department_id))) THEN
        RAISE EXCEPTION '场景成员已有归属冲突，拒绝覆盖';
    END IF;
    UPDATE users u SET department_id=t.department_id,version=u.version+1
      FROM teams t WHERE u.team_id=t.id AND u.department_id IS NULL
        AND u.company_id=t.company_id AND u.company_id IN ('annual-cm','annual-peer') AND u.id LIKE 'annual-%';
    UPDATE users SET department_id=CASE company_id WHEN 'annual-cm' THEN 'annual-management' ELSE 'annual-peer-dept' END,
                     version=version+1
      WHERE company_id IN ('annual-cm','annual-peer') AND id LIKE 'annual-%' AND department_id IS NULL;
    UPDATE users SET team_id=CASE department_id
            WHEN 'annual-product' THEN 'annual-product-team'
            WHEN 'annual-engineering' THEN 'annual-backend-team'
            WHEN 'annual-delivery' THEN 'annual-delivery-team'
            WHEN 'annual-management' THEN 'annual-management-team'
            WHEN 'annual-peer-dept' THEN 'annual-peer-team' END,
        version=version+1
      WHERE company_id IN ('annual-cm','annual-peer') AND id LIKE 'annual-%' AND team_id IS NULL;
    IF EXISTS (SELECT 1 FROM users u LEFT JOIN teams t ON t.id=u.team_id
               WHERE u.company_id IN ('annual-cm','annual-peer') AND u.id LIKE 'annual-%'
                 AND (t.id IS NULL OR t.company_id<>u.company_id OR t.department_id<>u.department_id)) THEN
        RAISE EXCEPTION '场景成员无法匹配同部门团队，整批回滚';
    END IF;

    FOR person IN SELECT u.*,row_number() OVER (ORDER BY u.id) AS n FROM users u
                  WHERE u.company_id IN ('annual-cm','annual-peer') AND u.id LIKE 'annual-%' LOOP
        UPDATE users SET
            phone=COALESCE(NULLIF(btrim(phone),''),'0002026'||lpad(person.n::text,4,'0')),
            email=COALESCE(NULLIF(btrim(email),''),account||'@chengming.example'),
            gender=COALESCE(NULLIF(btrim(gender),''),CASE WHEN id IN ('annual-chen','annual-he','annual-tang',
                'annual-design-lead','annual-delivery-lead','annual-admin','annual-pending-delivery') THEN '女' ELSE '男' END),
            age=COALESCE(age,25+(abs(hashtext(id)::bigint)%18)::integer),
            employment_start_date=CASE WHEN status='PENDING' THEN employment_start_date ELSE
                COALESCE(employment_start_date,CASE WHEN id IN ('annual-pending','annual-pending-delivery')
                    THEN date '2026-11-06' ELSE date '2026-05-18' END) END,
            profile=CASE WHEN NULLIF(btrim(profile->>'introduction'),'') IS NULL
                THEN profile||jsonb_build_object('introduction',name||'负责团队日常协作、任务跟进与阶段交付。') ELSE profile END,
            version=version+1
          WHERE id=person.id AND (NULLIF(btrim(phone),'') IS NULL OR NULLIF(btrim(email),'') IS NULL
            OR NULLIF(btrim(gender),'') IS NULL OR age IS NULL
            OR (status<>'PENDING' AND employment_start_date IS NULL)
            OR NULLIF(btrim(profile->>'introduction'),'') IS NULL);
    END LOOP;

    FOR person IN SELECT * FROM users WHERE company_id='annual-cm' AND id LIKE 'annual-%'
                    AND role='EMPLOYEE' AND status='ACTIVE' ORDER BY id LOOP
        SELECT id INTO issuer FROM users WHERE company_id=person.company_id AND team_id=person.team_id
            AND role='LEADER' AND status='ACTIVE' ORDER BY id LIMIT 1;
        IF issuer IS NULL THEN RAISE EXCEPTION '员工 % 缺少同组在职负责人',person.id; END IF;
        label_id := CASE person.department_id WHEN 'annual-product' THEN 'annual-cm-label-product'
            WHEN 'annual-engineering' THEN 'annual-cm-label-quality' ELSE 'annual-cm-label-delivery' END;
        FOR slot IN 1..8 LOOP
            tid := 'annual-calendar-overflow-'||person.id||'-'||slot;
            task_title := titles[slot];
            finishes := GREATEST(starts,person.employment_start_date::timestamptz)+make_interval(days=>3+(slot%3))+interval '8 hours';
            content := jsonb_build_object('title',task_title,'participants',jsonb_build_array(person.id),
                'startAt',GREATEST(starts,person.employment_start_date::timestamptz),'deadline',finishes,
                'urgency','NORMAL','group','阶段交付','labelId',label_id,'attachments','[]'::jsonb,
                'content','围绕本期工作整理输入、核对执行结果并提交可复核材料，与组内负责人同步进展。',
                'seedSource','annual-2026-v5','fictional',true);
            INSERT INTO tasks(id,company_id,owner_id,issuer_id,title,start_at,deadline,body,phase,version,created_at)
                VALUES(tid,person.company_id,person.id,issuer,task_title,
                    GREATEST(starts,person.employment_start_date::timestamptz),finishes,content,'DISPATCHED',1,dispatched);
            INSERT INTO task_participants(task_id,user_id,company_id,created_at) VALUES(tid,person.id,person.company_id,dispatched);
            INSERT INTO task_assignees(task_id,user_id,kind,company_id) VALUES(tid,person.id,'PRIMARY',person.company_id);
            INSERT INTO task_label_links(task_id,label_id,company_id,created_at) VALUES(tid,label_id,person.company_id,dispatched);
            INSERT INTO task_events(company_id,task_id,actor_id,type,body,from_phase,to_phase,task_version,created_at)
                VALUES(person.company_id,tid,issuer,'DISPATCHED',content,NULL,'DISPATCHED',1,dispatched);
        END LOOP;
    END LOOP;
    INSERT INTO audit_records(company_id,actor_id,type,object_id,before_value,after_value,reason)
        VALUES('annual-cm','annual-founder','ANNUAL_SCENARIO_ENRICHED','annual-cm','{}',
            jsonb_build_object('seedSource','annual-2026-v5','fictional',true,'tasksPerEmployee',8),
            '补齐虚构成员空资料、同公司团队归属与月历重叠计划；保留角色、状态、审核链与已有资料');
END
$enrich$;
