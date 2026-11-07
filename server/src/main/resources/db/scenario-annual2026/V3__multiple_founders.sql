-- 年度场景增量：增加多创始人账户，仅用于组织目录、标签和任务验收。
-- 不修改正式 Flyway、审核策略或既有年度 V1 数据。
DO $multi_founders$
DECLARE
    c constant text := 'annual-cm';
    launched_at constant timestamptz := timestamptz '2026-10-15 09:00+08';
    task_body jsonb;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM users WHERE id='annual-founder' AND company_id=c AND role='FOUNDER' AND status='ACTIVE') THEN
        RAISE EXCEPTION '年度主创始人缺失，拒绝写入多创始人场景数据';
    END IF;
    IF EXISTS (SELECT 1 FROM users WHERE id IN ('annual-founder-product','annual-founder-delivery')
               OR account IN ('founder-product','founder-delivery')) THEN
        RAISE EXCEPTION '多创始人场景账号已存在，拒绝覆盖';
    END IF;

    INSERT INTO users(id,company_id,account,password_hash,name,role,status,must_change_password,dispatch_enabled,company_reviewer,profile,email,employment_start_date,created_at)
    VALUES
      ('annual-founder-product',c,'founder-product','${scenarioPasswordHash}','林知衡','FOUNDER','ACTIVE',false,true,false,
       '{"seedSource":"annual-2026-v2","responsibility":"产品与资源协同"}','founder-product@chengming.example',date '2026-05-18',launched_at),
      ('annual-founder-delivery',c,'founder-delivery','${scenarioPasswordHash}','周予安','FOUNDER','ACTIVE',false,true,false,
       '{"seedSource":"annual-2026-v2","responsibility":"交付与试点验收"}','founder-delivery@chengming.example',date '2026-05-18',launched_at);
    INSERT INTO user_roles(user_id,role_id) VALUES
      ('annual-founder-product','FOUNDER'),('annual-founder-delivery','FOUNDER');

    INSERT INTO task_labels(id,company_id,name,category,color,creator_id,created_at)
    VALUES
      ('annual-label-founder-product',c,'创始人产品协同','公司','#6A5ACD','annual-founder-product',launched_at),
      ('annual-label-founder-delivery',c,'创始人交付协同','公司','#2F855A','annual-founder-delivery',launched_at);

    task_body := jsonb_build_object(
      'title','创始人联合核对年度场景验收范围',
      'participants',jsonb_build_array('annual-founder-product','annual-founder-delivery'),
      'startAt',launched_at,
      'deadline',launched_at + interval '5 days',
      'urgency','NORMAL',
      'group','年度场景验收',
      'content','虚构场景任务：两名创始人联合核对组织目录、标签和任务数据，仅用于验收。',
      'labelId','annual-label-founder-product',
      'attachments','[]'::jsonb
    );
    INSERT INTO tasks(id,company_id,owner_id,issuer_id,title,start_at,deadline,body,phase,version,created_at)
      VALUES('annual-founder-collaboration-task',c,'annual-founder-product','annual-founder-product',
        '创始人联合核对年度场景验收范围',launched_at,launched_at + interval '5 days',task_body,'DISPATCHED',1,launched_at);
    INSERT INTO task_participants(task_id,user_id,company_id,created_at) VALUES
      ('annual-founder-collaboration-task','annual-founder-product',c,launched_at),
      ('annual-founder-collaboration-task','annual-founder-delivery',c,launched_at);
    -- 保留历史兼容表；客户端仍以 task_participants 为参与人事实来源。
    INSERT INTO task_assignees(task_id,user_id,kind,company_id) VALUES
      ('annual-founder-collaboration-task','annual-founder-product','PRIMARY',c),
      ('annual-founder-collaboration-task','annual-founder-delivery','COLLABORATOR',c);
    INSERT INTO task_label_links(task_id,label_id,company_id,created_at)
      VALUES('annual-founder-collaboration-task','annual-label-founder-product',c,launched_at);
    INSERT INTO task_events(company_id,task_id,actor_id,type,body,from_phase,to_phase,task_version,created_at)
      VALUES(c,'annual-founder-collaboration-task','annual-founder-product','DISPATCHED',task_body,NULL,'DISPATCHED',1,launched_at);
    INSERT INTO review_requests(id,company_id,applicant_id,kind,target_id,expected_version,before_value,candidate,reason,status,approval_mode,decision_source,created_at)
      VALUES('annual-founder-collaboration-task-review',c,'annual-founder-product','TASK_CREATE','annual-founder-collaboration-task',0,'{}',task_body,
        '年度虚构场景：按既有创始人权限记录任务创建结果','APPROVED','DIRECT_MANAGER','FOUNDER_EXEMPT',launched_at - interval '1 hour');
    INSERT INTO audit_records(company_id,actor_id,type,object_id,before_value,after_value,reason)
      VALUES(c,'annual-founder-product','ANNUAL_SCENARIO_MULTI_FOUNDER_INITIALIZED',c,'{}',
        jsonb_build_object('accounts',jsonb_build_array('founder-product','founder-delivery'),'taskId','annual-founder-collaboration-task','fictional',true),
        '年度场景V2：新增两名虚构创始人及最小协作验收数据；不改变审核规则');
END
$multi_founders$;
