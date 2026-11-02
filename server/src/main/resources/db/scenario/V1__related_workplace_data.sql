-- 仅由 ScenarioDataBootstrap 显式执行；独立历史表保证一次性，不属于正式结构迁移。
-- 全部公司、姓名、工作内容均为虚构场景；历史初始化不表示曾调用真实业务接口。
-- 不修改现有数据；任意固定前缀冲突均使整个迁移回滚。
DO $seed$
DECLARE
    c constant text := 'scenario-cm';
    d date := (now() AT TIME ZONE 'Asia/Shanghai')::date;
    origin timestamptz;
    person record;
    item record;
    i int; j int; n int; k int; v int;
    uid text; manager text; issuer text; tid text; lid text; phase text;
    label text; participants jsonb; content jsonb; ev text; next_phase text; prior text;
    event_at timestamptz; submitted_time timestamptz; work_date date; log_body jsonb;
    titles text[] := ARRAY[
      '确认商户经营看板指标口径','完成商户访谈与需求优先级','评审多门店筛选交互','补齐退款与实收金额说明',
      '交付移动端看板高保真设计','核对空数据与弱网提示','完善日报任务关联交互','整理管理者下属日志月历需求',
      '优化经营汇总SQL索引','实现订单增量同步检查点','修复跨日退款聚合偏差','补齐接口权限与版本校验',
      '联调经营趋势图接口','完成任务反馈附件上传','核对安卓登录会话恢复','排查列表分页重复记录',
      '编写商户上线培训材料','确认首批门店导入清单','组织试点门店验收','汇总试点运营异常',
      '演练看板发布回滚流程','完成客户账号权限核对','核验历史订单导入结果','回访试点门店使用反馈',
      '验收经营看板首屏性能','复核商户数据导出权限','评审下一期交付排期','确认跨部门上线检查表',
      '整理周会风险与依赖清单','归档商户经营看板上线材料'];
    actors text[] := ARRAY['scenario-chen','scenario-lin','scenario-he','scenario-xu','scenario-zhou','scenario-zhao','scenario-tang','scenario-luo'];
    leaders text[] := ARRAY['scenario-product-lead','scenario-product-lead','scenario-design-lead','scenario-design-lead',
      'scenario-backend-lead','scenario-backend-lead','scenario-delivery-lead','scenario-delivery-lead'];
    actions text[];
BEGIN
    IF EXISTS(SELECT 1 FROM companies WHERE id LIKE 'scenario-%')
       OR EXISTS(SELECT 1 FROM users WHERE id LIKE 'scenario-%' OR account LIKE 'scenario.%') THEN
        RAISE EXCEPTION '场景前缀已存在，拒绝覆盖；请核对flyway_scenario_history与现有数据';
    END IF;
    origin := ((d-28)+time '09:00') AT TIME ZONE 'Asia/Shanghai';
    INSERT INTO companies(id,name) VALUES(c,'澄明数字科技（虚构场景）'),('scenario-peer','远帆供应链（隔离校验，虚构）');
    INSERT INTO departments(id,company_id,name) VALUES
      ('scenario-product',c,'产品体验部'),('scenario-engineering',c,'技术研发部'),('scenario-delivery',c,'客户交付部'),
      ('scenario-peer-dept','scenario-peer','运营部');
    INSERT INTO teams(id,company_id,department_id,name) VALUES
      ('scenario-product-team',c,'scenario-product','产品策划组'),('scenario-design-team',c,'scenario-product','交互设计组'),
      ('scenario-backend-team',c,'scenario-engineering','业务研发组'),('scenario-delivery-team',c,'scenario-delivery','客户实施组');

    FOR person IN SELECT * FROM (VALUES
      ('founder','顾明远','FOUNDER',NULL,NULL,NULL,'负责试点目标、资源投入及发布决策','ACTIVE'),
      ('admin','许安宁','ADMIN',NULL,NULL,'founder','负责成员确认与组织资料维护','ACTIVE'),
      ('product-director','沈嘉禾','DIRECTOR','product',NULL,'founder','负责指标定义、产品体验及需求取舍','ACTIVE'),
      ('engineering-director','陆承宇','DIRECTOR','engineering',NULL,'founder','负责数据一致性、架构与发布质量','ACTIVE'),
      ('delivery-director','宋知远','DIRECTOR','delivery',NULL,'founder','负责试点验收与客户交付','ACTIVE'),
      ('product-lead','方亦宁','LEADER','product','product-team','product-director','组织需求评审和指标口径核对','ACTIVE'),
      ('design-lead','程以晴','LEADER','product','design-team','product-director','负责交互评审与可用性检查','ACTIVE'),
      ('backend-lead','蒋文博','LEADER','engineering','backend-team','engineering-director','负责接口联调和数据管道','ACTIVE'),
      ('delivery-lead','杜晓棠','LEADER','delivery','delivery-team','delivery-director','安排门店培训与现场验收','ACTIVE'),
      ('chen','陈知夏','EMPLOYEE','product','product-team','product-lead','产品经理：商户指标与访谈','ACTIVE'),
      ('lin','林予安','EMPLOYEE','product','product-team','product-lead','产品助理：需求清单和验收标准','ACTIVE'),
      ('he','何书瑶','EMPLOYEE','product','design-team','design-lead','交互设计师：移动端看板体验','ACTIVE'),
      ('xu','徐景行','EMPLOYEE','product','design-team','design-lead','体验设计师：异常态和培训图示','ACTIVE'),
      ('zhou','周启航','EMPLOYEE','engineering','backend-team','backend-lead','后端工程师：经营汇总与权限接口','ACTIVE'),
      ('zhao','赵星澜','EMPLOYEE','engineering','backend-team','backend-lead','客户端工程师：任务日志和会话恢复','ACTIVE'),
      ('tang','唐可欣','EMPLOYEE','delivery','delivery-team','delivery-lead','实施顾问：试点门店培训','ACTIVE'),
      ('luo','罗思齐','EMPLOYEE','delivery','delivery-team','delivery-lead','数据实施专员：导入和对账','ACTIVE'),
      ('pending','叶知秋','EMPLOYEE','engineering',NULL,NULL,'待管理员确认的研发新同事','PENDING'),
      ('pending-delivery','温言','EMPLOYEE','delivery',NULL,NULL,'待管理员确认的交付新同事','PENDING'),
      ('disabled','邵维','EMPLOYEE','delivery','delivery-team',NULL,'已停用历史成员，不分配新任务','DISABLED')
    ) AS people(key,name,role,dept,team,manager,bio,status) LOOP
        uid := 'scenario-'||person.key;
        INSERT INTO users(id,company_id,account,password_hash,phone,name,department_id,team_id,role,status,
          must_change_password,dispatch_enabled,company_reviewer,profile,email,gender,age,employment_start_date,created_at)
        VALUES(uid,c,'scenario.'||person.key,'${scenarioPasswordHash}',NULL,person.name,
          CASE WHEN person.dept IS NULL THEN NULL ELSE 'scenario-'||person.dept END,
          CASE WHEN person.team IS NULL THEN NULL ELSE 'scenario-'||person.team END,person.role,person.status,
          false,person.role<>'EMPLOYEE',person.role='ADMIN',jsonb_build_object('bio',person.bio,'seedSource','flyway-scenario-v1'),
          person.key||'@chengming.example',NULL,NULL,
          CASE WHEN person.status<>'ACTIVE' OR person.key='xu' THEN NULL WHEN person.key='lin' THEN d-2 ELSE d-180 END,
          CASE WHEN person.key='lin' THEN ((d-2)+time '09:00') AT TIME ZONE 'Asia/Shanghai' ELSE origin-interval '180 days' END);
        INSERT INTO user_roles VALUES(uid,person.role);
        IF person.manager IS NOT NULL THEN
            INSERT INTO reporting_relations VALUES(uid,'scenario-'||person.manager,c);
        END IF;
    END LOOP;
    INSERT INTO users(id,company_id,account,password_hash,name,department_id,role,status,dispatch_enabled,profile)
      VALUES('scenario-outsider','scenario-peer','scenario.outsider','${scenarioPasswordHash}','江亦辰','scenario-peer-dept','EMPLOYEE','ACTIVE',false,'{"seedSource":"flyway-scenario-v1"}');
    INSERT INTO user_roles VALUES('scenario-outsider','EMPLOYEE');

    INSERT INTO task_labels(id,company_id,name,category,color,creator_id,created_at) VALUES
      ('scenario-label-product',c,'产品体验','PROJECT','#4F6BED','scenario-founder',origin),
      ('scenario-label-engineering',c,'研发联调','PROJECT','#008272','scenario-founder',origin),
      ('scenario-label-delivery',c,'试点交付','PROJECT','#C76B00','scenario-founder',origin);
    FOR i IN 1..30 LOOP
        n := CASE WHEN i<=8 THEN ((i-1)%4)+1 WHEN i<=16 THEN 5+(i%2) WHEN i<=24 THEN 7+(i%2) ELSE ((i-1)%8)+1 END;
        uid:=actors[n]; issuer:=CASE WHEN i>=25 THEN 'scenario-founder' ELSE leaders[n] END;
        tid:='scenario-task-'||lpad(i::text,2,'0');
        label:=CASE WHEN n<=4 THEN 'scenario-label-product' WHEN n<=6 THEN 'scenario-label-engineering' ELSE 'scenario-label-delivery' END;
        participants:=jsonb_build_array(uid);
        IF i%5=0 THEN participants:=participants||jsonb_build_array(actors[CASE WHEN n%2=1 THEN n+1 ELSE n-1 END]); END IF;
        event_at:=origin+make_interval(days=>i%12);
        actions:=CASE i%7
          WHEN 0 THEN ARRAY['DISPATCHED']
          WHEN 1 THEN ARRAY['DISPATCHED','RECEIVED']
          WHEN 2 THEN ARRAY['DISPATCHED','RECEIVED','FEEDBACK']
          WHEN 3 THEN ARRAY['DISPATCHED','RECEIVED','FEEDBACK','ACCEPTED']
          WHEN 4 THEN ARRAY['DISPATCHED','RECEIVED','FEEDBACK','ACCEPTED','ARCHIVED']
          WHEN 5 THEN ARRAY['DISPATCHED','WITHDRAWN']
          ELSE ARRAY['DISPATCHED','RECEIVED','FEEDBACK','RETURNED'] END;
        phase:=CASE WHEN actions[array_length(actions,1)]='RETURNED' THEN 'RECEIVED' ELSE actions[array_length(actions,1)] END;
        content:=jsonb_build_object('title',titles[i],'participants',participants,'startAt',event_at,'deadline',
          CASE WHEN i%4=0 THEN ((d-2)+time '18:00') AT TIME ZONE 'Asia/Shanghai' ELSE ((d+(i%10)+1)+time '18:00') AT TIME ZONE 'Asia/Shanghai' END,
          'urgency',CASE WHEN i%6=0 THEN 'URGENT' ELSE 'NORMAL' END,'group','商户经营看板上线',
          'content','目标：'||titles[i]||'。覆盖试点门店的正常、空数据和权限边界；交付可复核材料，评审结论由派发人确认。',
          'labelId',label,'attachments','[]'::jsonb);
        INSERT INTO tasks(id,company_id,owner_id,issuer_id,title,start_at,deadline,body,phase,version,created_at)
          VALUES(tid,c,uid,issuer,titles[i],event_at,(content->>'deadline')::timestamptz,content,phase,array_length(actions,1),event_at);
        INSERT INTO task_participants(task_id,user_id,company_id,created_at)
          SELECT tid,value,c,event_at FROM jsonb_array_elements_text(participants);
        -- 兼容内部旧事实表，不向客户端恢复负责人/协作人语义。
        INSERT INTO task_assignees(task_id,user_id,kind,company_id)
          SELECT tid,value,CASE WHEN value=uid THEN 'PRIMARY' ELSE 'COLLABORATOR' END,c FROM jsonb_array_elements_text(participants);
        INSERT INTO task_label_links(task_id,label_id,company_id,created_at) VALUES(tid,label,c,event_at);
        prior:=NULL; v:=0;
        FOREACH ev IN ARRAY actions LOOP
            v:=v+1; next_phase:=CASE WHEN ev='RETURNED' THEN 'RECEIVED' ELSE ev END;
            INSERT INTO task_events(company_id,task_id,actor_id,type,body,from_phase,to_phase,task_version,created_at)
              VALUES(c,tid,CASE WHEN ev IN('RECEIVED','FEEDBACK') THEN uid ELSE issuer END,ev,
                CASE WHEN ev='DISPATCHED' THEN content ELSE jsonb_build_object('text',CASE ev
                  WHEN 'FEEDBACK' THEN '已完成核对并提交评审材料，试点门店差异已记录。'
                  WHEN 'RETURNED' THEN '请补充空数据及跨日退款场景的验收证据后重新提交。'
                  WHEN 'WITHDRAWN' THEN '需求优先级调整，本期合并至后续统一交付。'
                  WHEN 'ACCEPTED' THEN '按验收清单复核通过，纳入试点发布。'
                  ELSE '已完成本节点工作。' END) END,prior,next_phase,v,event_at+make_interval(hours=>v-1));
            prior:=next_phase;
        END LOOP;
        INSERT INTO task_comments(id,company_id,task_id,author_id,body,client_key,created_at)
          VALUES(tid||'-comment',c,tid,issuer,'请按指标口径和验收清单推进，风险及时同步。',tid||'-seed',event_at+interval '15 minutes');
        INSERT INTO task_comments(id,company_id,task_id,author_id,parent_id,body,client_key,created_at)
          VALUES(tid||'-reply',c,tid,uid,tid||'-comment','收到，将在日报中关联本任务并同步核对结果。',tid||'-reply-seed',event_at+interval '30 minutes');
        SELECT manager_id INTO manager FROM reporting_relations WHERE employee_id=issuer;
        INSERT INTO review_requests(id,company_id,applicant_id,kind,target_id,expected_version,before_value,candidate,reason,status,approval_mode,decision_source,created_at)
          VALUES(tid||'-review',c,issuer,'TASK_CREATE',tid,0,'{}',content,'历史场景初始化：任务评审通过后派发','APPROVED','DIRECT_MANAGER',
            CASE WHEN issuer='scenario-founder' THEN 'FOUNDER_EXEMPT' ELSE 'DIRECT_MANAGER' END,event_at-interval '2 hours');
        IF issuer<>'scenario-founder' THEN
            INSERT INTO review_steps(request_id,reviewer_id,position,state,reason,decided_at,company_id,applicant_id)
              VALUES(tid||'-review',manager,1,'APPROVED','目标与范围清晰，同意派发',event_at-interval '1 hour',c,issuer);
        END IF;
        INSERT INTO outbox_events(id,company_id,recipient_id,type,object_id,body,dedup_key,created_at)
          SELECT tid||'-notice-'||value,c,value,'TASK_DISPATCHED',tid,'{}',tid||'-notice-'||value,event_at FROM jsonb_array_elements_text(participants);
    END LOOP;

    -- 可下载的真实字节材料，绑定任务而不是伪造外部AI结果。
    FOR i IN 1..6 LOOP
        tid:='scenario-task-'||lpad(i::text,2,'0');
        INSERT INTO attachments(id,company_id,owner_id,filename,content_type,data,task_id,file_hash,created_at)
          SELECT 'scenario-file-'||i,c,issuer_id,'看板验收清单-'||i||'.txt','text/plain',
            convert_to('虚构场景材料：商户经营看板。验收项：指标口径一致；空数据提示；跨日退款；组织权限；导出对账。','UTF8'),tid,
            encode(sha256(convert_to('虚构场景材料：商户经营看板。验收项：指标口径一致；空数据提示；跨日退款；组织权限；导出对账。','UTF8')),'hex'),created_at FROM tasks WHERE id=tid;
        UPDATE tasks SET body=jsonb_set(body,'{attachments}',jsonb_build_array('scenario-file-'||i)) WHERE id=tid;
    END LOOP;

    FOR person IN SELECT * FROM users WHERE company_id=c AND role='EMPLOYEE' AND status='ACTIVE' ORDER BY id LOOP
        FOR j IN 0..27 LOOP
            work_date:=d-j;
            IF extract(isodow FROM work_date)>5 OR (person.employment_start_date IS NOT NULL AND work_date<person.employment_start_date)
               OR (person.id='scenario-luo' AND j IN(1,4)) THEN CONTINUE; END IF;
            SELECT t.id,t.title INTO item FROM tasks t JOIN task_participants p ON p.task_id=t.id
              WHERE p.user_id=person.id AND t.created_at::date<=work_date ORDER BY t.created_at DESC,t.id LIMIT 1;
            IF NOT FOUND THEN CONTINUE; END IF;
            lid:='scenario-log-'||person.id||'-'||to_char(work_date,'YYYYMMDD');
            submitted_time:=(work_date+time '17:45') AT TIME ZONE 'Asia/Shanghai';
            IF work_date=d THEN submitted_time:=LEAST(now()-interval '5 minutes',submitted_time); END IF;
            log_body:=jsonb_build_object('work',(person.profile->>'bio')||'。推进“'||item.title||'”，核对试点数据与验收口径，记录差异并同步直属上级。',
              'blockers',CASE WHEN j%5=0 THEN '试点门店补充数据尚未齐全，已请实施同事跟进；不影响已确认部分。' ELSE '暂无新增阻碍。' END,
              'tomorrow','继续核对未关闭差异，补充验收材料并在任务评论同步。','hours',CASE WHEN j%4=0 THEN 6.5 ELSE 7.5 END,'taskIds',jsonb_build_array(item.id));
            INSERT INTO daily_logs(id,company_id,owner_id,business_date,body,submitted,version,created_at,submitted_at)
              VALUES(lid,c,person.id,work_date,log_body,true,2,submitted_time-interval '1 hour',submitted_time);
            INSERT INTO log_versions(company_id,log_id,version,body,created_at) VALUES(c,lid,2,log_body,submitted_time);
            INSERT INTO log_tasks VALUES(c,lid,item.id);
            IF j<=2 THEN
                SELECT manager_id INTO manager FROM reporting_relations WHERE employee_id=person.id;
                INSERT INTO log_comments(id,company_id,log_id,actor_id,text,created_at)
                  VALUES(lid||'-comment',c,lid,manager,'请将未关闭差异补到任务材料，次日站会一起确认。',LEAST(now(),submitted_time+interval '10 minutes'));
                INSERT INTO outbox_events(id,company_id,recipient_id,type,object_id,body,dedup_key,created_at)
                  VALUES(lid||'-notice',c,manager,'LOG_SUBMITTED',lid,'{}',lid||'-notice',submitted_time);
            END IF;
        END LOOP;
    END LOOP;
    -- 今日草稿与提交日志分属不同人员，便于验证草稿私密性。
    INSERT INTO daily_logs(id,company_id,owner_id,business_date,body,created_at)
      VALUES('scenario-draft',c,'scenario-product-lead',d,
        '{"work":"整理本轮指标评审的分歧，尚未确认的内容暂存草稿。","hours":2,"taskIds":[]}',now());

    FOR person IN SELECT * FROM users WHERE company_id=c AND status='PENDING' LOOP
        INSERT INTO review_requests(id,company_id,applicant_id,kind,target_id,expected_version,before_value,candidate,reason,approval_mode)
          VALUES(person.id||'-membership',c,person.id,'MEMBERSHIP',person.id,1,'{}',jsonb_build_object('departmentId',person.department_id),'申请加入所属部门','ADMIN_MEMBERSHIP');
        INSERT INTO review_steps(request_id,reviewer_id,position,company_id,applicant_id)
          VALUES(person.id||'-membership','scenario-admin',1,c,person.id);
        INSERT INTO outbox_events(id,company_id,recipient_id,type,object_id,body,dedup_key)
          VALUES(person.id||'-review-notice',c,'scenario-admin','REVIEW_PENDING',person.id||'-membership','{}',person.id||'-review-notice');
    END LOOP;
    FOR i IN 1..2 LOOP
        SELECT * INTO item FROM tasks WHERE id='scenario-task-'||lpad(i::text,2,'0');
        SELECT manager_id INTO manager FROM reporting_relations WHERE employee_id=item.issuer_id;
        INSERT INTO review_requests(id,company_id,applicant_id,kind,target_id,expected_version,before_value,candidate,reason,status,approval_mode,decision_source)
          VALUES('scenario-reschedule-'||i,c,item.issuer_id,'TASK_RESCHEDULE',item.id,item.version,item.body,
            jsonb_build_object('deadline',item.deadline+interval '3 days'),'试点门店数据补充需要额外核对时间',
            CASE WHEN i=1 THEN 'PENDING' ELSE 'REJECTED' END,'DIRECT_MANAGER',CASE WHEN i=1 THEN NULL ELSE 'DIRECT_MANAGER' END);
        INSERT INTO review_steps(request_id,reviewer_id,position,state,reason,decided_at,company_id,applicant_id)
          VALUES('scenario-reschedule-'||i,manager,1,CASE WHEN i=1 THEN 'PENDING' ELSE 'REJECTED' END,
            CASE WHEN i=1 THEN NULL ELSE '请先缩小范围完成当前可交付部分，再评估改期。' END,CASE WHEN i=1 THEN NULL ELSE now() END,c,item.issuer_id);
    END LOOP;
    INSERT INTO dashboard_items(id,company_id,owner_id,kind,title,body,pinned,position,created_at) VALUES
      ('scenario-company-goal',c,'scenario-founder','COMPANY','商户经营看板试点上线',
       '{"text":"首批门店完成指标对账、权限核验和培训；发布前保留回滚检查记录。"}',true,0,origin),
      ('scenario-personal-goal',c,'scenario-zhou','PERSONAL','优先关闭跨日退款聚合差异',
       '{"text":"先核对退款归属日期，再复核看板与导出的一致性。"}',true,0,now());
    INSERT INTO audit_records(company_id,actor_id,type,object_id,before_value,after_value,reason)
      VALUES(c,'scenario-admin','SCENARIO_INITIALIZED',c,'{}',
        jsonb_build_object('source','Flyway db/scenario V1','businessDate',d,'fictional',true),
        '显式启用的一次性历史场景初始化；非真实客户资料，不表示历史HTTP调用');
END
$seed$;
