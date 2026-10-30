-- 年度新场景：仅空业务库。正式V1–V23先执行，独立历史保证只初始化一次。
-- 日期、姓名、企业均为虚构夹具；不表示历史真实HTTP操作。
DO $annual$
DECLARE
    c text := 'annual-cm';
    cutoff timestamptz := LEAST(now(), timestamptz '2026-11-30 23:59:59+08');
    today date := (LEAST(now(), timestamptz '2026-11-30 23:59:59+08') AT TIME ZONE 'Asia/Shanghai')::date;
    person record; item record; linked record;
    uid text; issuer text; manager text; peer text; tid text; previous_id text; label text;
    company text; focus text; title text; lid text; phase text; prior text; action text;
    month_no int; slot int; salt int; duration int; v int; idx int;
    day date; begin_day date; end_day date; work_day date;
    start_time timestamptz; end_time timestamptz; dispatched timestamptz; event_time timestamptz;
    log_time timestamptz; note text; actions text[]; names text[];
    participants jsonb; content jsonb; log_body jsonb; linked_ids jsonb;
BEGIN
    IF today < date '2026-06-01' THEN RAISE EXCEPTION '年度场景起点尚未到达'; END IF;
    -- 只允许AuthBootstrap产生的默认维护管理员存在；未知业务一律拒绝。
    LOCK TABLE users IN SHARE ROW EXCLUSIVE MODE;
    IF EXISTS(SELECT 1 FROM users WHERE company_id<>'default' OR role<>'ADMIN')
       OR EXISTS(SELECT 1 FROM companies WHERE id<>'default')
       OR EXISTS(SELECT 1 FROM tasks) OR EXISTS(SELECT 1 FROM daily_logs)
       OR EXISTS(SELECT 1 FROM dashboard_items) OR EXISTS(SELECT 1 FROM task_labels)
       OR EXISTS(SELECT 1 FROM review_requests)
       OR EXISTS(SELECT 1 FROM attachments) OR EXISTS(SELECT 1 FROM ai_jobs)
       OR EXISTS(SELECT 1 FROM private_notes)
       OR to_regclass('public.flyway_scenario_history') IS NOT NULL THEN
        RAISE EXCEPTION 'annual-2026只接受空业务库；请新建数据库，不清表、不覆盖旧数据';
    END IF;

    INSERT INTO companies(id,name) VALUES(c,'澄明数字科技（年度虚构场景）'),
      ('annual-peer','远帆供应链（隔离虚构场景）');
    INSERT INTO departments(id,company_id,name) VALUES
      ('annual-product',c,'产品体验部'),('annual-engineering',c,'技术研发部'),
      ('annual-delivery',c,'客户交付部'),('annual-peer-dept','annual-peer','运营部');
    INSERT INTO teams(id,company_id,department_id,name) VALUES
      ('annual-product-team',c,'annual-product','产品策划组'),
      ('annual-design-team',c,'annual-product','交互设计组'),
      ('annual-backend-team',c,'annual-engineering','业务研发组'),
      ('annual-delivery-team',c,'annual-delivery','客户实施组');

    CREATE TEMP TABLE annual_people ON COMMIT DROP AS
    SELECT * FROM (VALUES
      ('founder','boss','顾明远','FOUNDER',NULL,NULL,NULL,'ACTIVE','确认阶段目标|协调跨部门资源|复核试点风险|评审发布条件|确认推广预算|整理经营复盘'),
      ('admin','admin','许安宁','ADMIN',NULL,NULL,'founder','ACTIVE','核对成员入职资料|确认组织归属|复核账号权限|更新培训名单|清理停用授权|归档权限台账'),
      ('product-director','pdir','沈嘉禾','DIRECTOR','product',NULL,'founder','ACTIVE','确认用户调研范围|评审指标优先级|协调版本边界|复核验收口径|整理试点反馈|评审下一轮需求'),
      ('engineering-director','rdir','陆承宇','DIRECTOR','engineering',NULL,'founder','ACTIVE','评审接口技术方案|协调研发依赖|核对安全风险|评审发布回滚|复核性能基线|整理稳定性复盘'),
      ('delivery-director','ddir','宋知远','DIRECTOR','delivery',NULL,'founder','ACTIVE','确认门店分批清单|安排交付资源|协调环境准备|评审验收风险|确认推广节奏|整理客户交付复盘'),
      ('product-lead','plead','方亦宁','LEADER','product','product-team','product-director','ACTIVE','拆分阶段需求|统一指标字典|组织接口评审|核对验收样本|跟进试点差异|整理需求关闭清单'),
      ('design-lead','dlead','程以晴','LEADER','product','design-team','product-director','ACTIVE','评审关键操作流程|交付页面原型|组织设计走查|复核异常状态|确认体验改进|整理设计交接材料'),
      ('backend-lead','rlead','蒋文博','LEADER','engineering','backend-team','engineering-director','ACTIVE','拆分接口联调事项|评审数据一致性|组织缺陷定位|核验权限边界|检查发布依赖|整理研发复盘'),
      ('delivery-lead','tlead','杜晓棠','LEADER','delivery','delivery-team','delivery-director','ACTIVE','核对门店环境|安排导入批次|准备培训日程|组织现场验收|分派回访问题|整理交付移交清单'),
      ('chen','chen','陈知夏','EMPLOYEE','product','product-team','product-lead','ACTIVE','整理商户访谈证据|补充指标口径|核对交互流程|完善验收样本|复核试点反馈|更新需求差异清单'),
      ('lin','lin','林予安','EMPLOYEE','product','product-team','product-lead','ACTIVE','熟悉指标说明|整理门店问题清单|核对页面文案|补充验收截图|跟进待确认事项|归档产品交接材料'),
      ('he','he01','何书瑶','EMPLOYEE','product','design-team','design-lead','ACTIVE','梳理任务操作流程|设计列表交互原型|完善空数据提示|走查研发还原效果|修订弱网反馈|整理设计验收记录'),
      ('xu','xu01','徐景行','EMPLOYEE','product','design-team','design-lead','ACTIVE','整理用户操作观察|核对表单可用性|设计异常态说明|复核标签可读性|走查多尺寸页面|归档体验问题证据'),
      ('zhou','zhou','周启航','EMPLOYEE','engineering','backend-team','backend-lead','ACTIVE','核对订单数据字段|实现增量同步接口|修复退款聚合偏差|补齐接口权限校验|优化经营汇总查询|整理联调问题闭环'),
      ('zhao','zhao','赵星澜','EMPLOYEE','engineering','backend-team','backend-lead','ACTIVE','接入任务列表接口|完善登录会话恢复|联调日志任务关联|修复附件失败重试|走查月历任务布局|整理客户端发布检查'),
      ('tang','tang','唐可欣','EMPLOYEE','delivery','delivery-team','delivery-lead','ACTIVE','核对试点门店环境|编写操作培训材料|组织门店试用培训|收集现场验收问题|回访门店使用情况|整理客户交接说明'),
      ('luo','luo','罗思齐','EMPLOYEE','delivery','delivery-team','delivery-lead','ACTIVE','清洗门店订单样本|核对导入字段映射|执行小批量试导入|复核退款差异|汇总导入失败记录|归档数据核对结果'),
      ('pending','new1','叶知秋','EMPLOYEE','engineering',NULL,NULL,'PENDING','待确认成员'),
      ('pending-delivery','new2','温言','EMPLOYEE','delivery',NULL,NULL,'PENDING','待确认成员'),
      ('disabled','off1','邵维','EMPLOYEE','delivery','delivery-team','delivery-lead','DISABLED','整理历史门店档案|核对交付材料|回收旧账号权限|补充移交说明|核验归档附件|完成离岗交接'),
      ('outsider','other','江亦辰','FOUNDER',NULL,NULL,NULL,'ACTIVE','核对供应商资料|整理补货需求|确认到货计划|复核库存差异|跟进供应商反馈|整理采购复盘')
    ) AS p(key,account,name,role,dept,team,manager,status,work_titles);

    FOR person IN SELECT * FROM annual_people LOOP
        uid:='annual-'||person.key;
        company:=CASE WHEN person.key='outsider' THEN 'annual-peer' ELSE c END;
        INSERT INTO users(id,company_id,account,password_hash,name,role,status,department_id,team_id,
          must_change_password,dispatch_enabled,company_reviewer,profile,email,employment_start_date,created_at)
        VALUES(uid,company,person.account,'${scenarioPasswordHash}',person.name,person.role,person.status,
          CASE WHEN person.key='outsider' THEN 'annual-peer-dept' WHEN person.dept IS NOT NULL THEN 'annual-'||person.dept END,
          CASE WHEN person.team IS NOT NULL THEN 'annual-'||person.team END,false,person.role<>'EMPLOYEE',person.role='ADMIN',
          jsonb_build_object('introduction',person.name||'负责'||split_part(person.work_titles,'|',1)||'，交付内容与上下游同事协同。',
            'seedSource','annual-2026-v1'),person.account||'@chengming.example',
          CASE WHEN person.status='PENDING' OR person.key='xu' THEN NULL
               WHEN person.key='lin' THEN date '2026-10-01' ELSE date '2026-05-18' END,
          CASE WHEN person.status='PENDING' THEN cutoff-interval '1 day'
               WHEN person.key='lin' THEN timestamptz '2026-10-01 09:00+08' ELSE timestamptz '2026-05-18 09:00+08' END);
        INSERT INTO user_roles VALUES(uid,person.role);
    END LOOP;
    INSERT INTO reporting_relations(employee_id,manager_id,company_id)
      SELECT 'annual-'||p.key,'annual-'||p.manager,c FROM annual_people p WHERE p.manager IS NOT NULL;

    FOR company IN SELECT unnest(ARRAY[c,'annual-peer']) LOOP
        INSERT INTO task_labels(id,company_id,name,category,color,creator_id,created_at)
        SELECT company||'-label-'||k,company,n,cat,color,
          CASE WHEN company=c THEN 'annual-founder' ELSE 'annual-outsider' END,timestamptz '2026-06-01 09:00+08'
        FROM (VALUES ('important','公司重点','公司','#FFD9A8'),('product','产品体验','部门','#CFE5FF'),
          ('quality','研发质量','部门','#DCE8F7'),('delivery','客户交付','部门','#F5DDC6'),
          ('operations','运营计划','个人','#E7D4FF')) AS labels(k,n,cat,color);
    END LOOP;

    FOR item IN SELECT * FROM (VALUES
      (1,'完成首批商户需求调研','形成访谈纪要、问题分级及可复核证据。'),
      (2,'统一经营指标与统计口径','确认退款归属日、订单去重与看板导出的一致口径。'),
      (3,'完成移动端核心交互设计','覆盖列表、表单、空数据、弱网和错误反馈。'),
      (4,'建立订单同步与退款核对链路','具备增量同步、异常重试和差异复核材料。'),
      (5,'完成组织权限与稳定登录','验证组织范围、停用限制和跨次启动会话恢复。'),
      (6,'落地任务日志与审核协作','打通派发、日志关联、直属审核及反馈闭环。'),
      (7,'完成首批试点门店上线','完成环境核验、数据导入、培训和首轮回访。'),
      (8,'提升看板性能与数据准确性','关闭慢查询和退款差异，保留优化前后依据。'),
      (9,'推进第二批门店推广','按批次核对数据、安排培训并跟踪验收差异。'),
      (10,'完成季度复盘与下一阶段规划','汇总经营结果、交付风险和下一阶段资源计划。')
    ) AS goals(n,title,description) LOOP
        INSERT INTO dashboard_items(id,company_id,owner_id,kind,title,body,pinned,position,created_at)
          VALUES('annual-focus-'||item.n,c,'annual-founder','COMPANY',item.title,
            jsonb_build_object('text',item.description),true,item.n-1,timestamptz '2026-06-01 09:00+08');
    END LOOP;

    FOR person IN SELECT * FROM annual_people WHERE status<>'PENDING' ORDER BY key LOOP
        uid:='annual-'||person.key;
        company:=CASE WHEN person.key='outsider' THEN 'annual-peer' ELSE c END;
        issuer:=CASE WHEN person.key='outsider' THEN uid WHEN person.manager IS NULL THEN 'annual-founder'
          ELSE 'annual-'||person.manager END;
        -- 跨团队交接由创始人派发，其他任务由当前直属上级派发。
        peer:=CASE person.key WHEN 'chen' THEN 'annual-zhou' WHEN 'zhou' THEN 'annual-luo'
          WHEN 'zhao' THEN 'annual-he' WHEN 'tang' THEN 'annual-chen' WHEN 'luo' THEN 'annual-zhao' ELSE NULL END;
        salt:=get_byte(decode(md5(person.key),'hex'),0);
        names:=string_to_array(person.work_titles,'|'); previous_id:=NULL;
        FOR month_no IN 6..11 LOOP
            IF person.key='lin' AND month_no<10 THEN CONTINUE; END IF;
            IF person.status='DISABLED' AND month_no>8 THEN CONTINUE; END IF;
            focus:=(ARRAY['需求调研与口径','订单同步与权限','任务日志协作','首批试点上线','第二批门店准备','推广验收与复盘'])[month_no-5];
            IF person.key='outsider' THEN focus:='供应链月度协作'; END IF;
            FOR slot IN 1..6 LOOP
                -- 同月不同用户/任务拥有不同开始日和工期；第2/3和第5/6项可交叉。
                begin_day:=make_date(2026,month_no,1)+(ARRAY[0,4,6,12,20,23])[slot]+((salt+slot+month_no)%3);
                IF extract(isodow FROM begin_day)=6 THEN begin_day:=begin_day+2;
                ELSIF extract(isodow FROM begin_day)=7 THEN begin_day:=begin_day+1; END IF;
                duration:=CASE WHEN (salt+slot+month_no)%11=0 THEN 8 ELSE 1+(salt+slot*3+month_no)%5 END;
                end_day:=begin_day+duration;
                IF person.status='DISABLED' AND end_day>date '2026-08-28' THEN end_day:=date '2026-08-28'; END IF;
                IF end_day>date '2026-11-30' THEN end_day:=date '2026-11-30'; END IF;
                start_time:=(begin_day+make_time(9+(salt+slot)%3,(slot%2)*30,0)) AT TIME ZONE 'Asia/Shanghai';
                end_time:=(end_day+make_time(16+slot%3,(salt%2)*30,0)) AT TIME ZONE 'Asia/Shanghai';
                dispatched:=LEAST(start_time-interval '1 day',cutoff-interval '3 hours');
                tid:=uid||'-'||month_no||'-'||slot;
                title:=focus||'：'||names[slot];
                label:=company||'-label-'||CASE WHEN slot=1 THEN 'important' WHEN slot=6 THEN 'operations'
                  WHEN (slot+salt)%3=0 THEN 'product' WHEN (slot+salt)%3=1 THEN 'quality' ELSE 'delivery' END;
                participants:=jsonb_build_array(uid);
                IF slot=4 AND peer IS NOT NULL THEN participants:=participants||jsonb_build_array(peer); END IF;
                content:=jsonb_build_object('title',title,'participants',participants,'startAt',start_time,
                  'deadline',end_time,'urgency',CASE WHEN slot=3 AND month_no=10 THEN 'URGENT' ELSE 'NORMAL' END,
                  'group',focus,'content',person.name||'负责'||names[slot]||'。交付可复核清单与差异记录。'||
                    CASE WHEN previous_id IS NULL THEN '作为本阶段首项工作，先确认输入材料。'
                      ELSE '承接任务['||previous_id||']的材料，检查未关闭项并在评论记录交接。' END||
                    CASE WHEN slot=4 AND peer IS NOT NULL THEN '协作成员['||peer||']提供样本或复核结果。' ELSE '' END,
                  'labelId',label,'attachments','[]'::jsonb);
                IF person.key='zhou' AND month_no=10 AND slot<=3 THEN
                    content:=jsonb_set(content,'{attachments}',jsonb_build_array(tid||'-file'));
                END IF;
                actions:=ARRAY['DISPATCHED'];
                IF start_time+interval '2 hours'<=cutoff THEN actions:=actions||ARRAY['RECEIVED']; END IF;
                IF end_time-interval '2 hours'<=cutoff THEN
                    IF (salt+slot)%9=0 THEN actions:=actions||ARRAY['FEEDBACK','RETURNED'];
                    ELSE actions:=actions||ARRAY['FEEDBACK']; END IF;
                END IF;
                IF end_time+interval '1 hour'<=cutoff AND actions[array_length(actions,1)]='FEEDBACK' THEN
                    actions:=actions||ARRAY['ACCEPTED'];
                    IF end_time+interval '1 day'<=cutoff AND (salt+slot)%3<>0 THEN actions:=actions||ARRAY['ARCHIVED']; END IF;
                END IF;
                phase:=CASE WHEN actions[array_length(actions,1)]='RETURNED' THEN 'RECEIVED' ELSE actions[array_length(actions,1)] END;
                INSERT INTO tasks(id,company_id,owner_id,issuer_id,title,start_at,deadline,body,phase,version,created_at)
                  VALUES(tid,company,uid,CASE WHEN slot=4 AND peer IS NOT NULL THEN 'annual-founder' ELSE issuer END,
                    title,start_time,end_time,content,phase,array_length(actions,1),dispatched);
                INSERT INTO task_participants(task_id,user_id,company_id,created_at)
                  SELECT tid,value,company,dispatched FROM jsonb_array_elements_text(participants);
                INSERT INTO task_assignees(task_id,user_id,kind,company_id)
                  SELECT tid,value,CASE WHEN value=uid THEN 'PRIMARY' ELSE 'COLLABORATOR' END,company
                  FROM jsonb_array_elements_text(participants);
                INSERT INTO task_label_links(task_id,label_id,company_id,created_at) VALUES(tid,label,company,dispatched);
                prior:=NULL; v:=0;
                FOREACH action IN ARRAY actions LOOP
                    v:=v+1;
                    event_time:=CASE action WHEN 'DISPATCHED' THEN dispatched WHEN 'RECEIVED' THEN start_time+interval '2 hours'
                      WHEN 'FEEDBACK' THEN end_time-interval '2 hours' WHEN 'RETURNED' THEN end_time-interval '1 hour'
                      WHEN 'ACCEPTED' THEN end_time+interval '1 hour' ELSE end_time+interval '1 day' END;
                    INSERT INTO task_events(company_id,task_id,actor_id,type,body,from_phase,to_phase,task_version,created_at)
                      VALUES(company,tid,CASE WHEN action IN('RECEIVED','FEEDBACK') THEN uid
                        WHEN slot=4 AND peer IS NOT NULL THEN 'annual-founder' ELSE issuer END,
                        action,CASE WHEN action='DISPATCHED' THEN content ELSE jsonb_build_object('text',
                          CASE action WHEN 'RETURNED' THEN '请补充异常样本和核对依据，保留当前交付并继续处理。'
                            WHEN 'FEEDBACK' THEN names[slot]||'已整理材料，差异项见交接清单。'
                            WHEN 'ACCEPTED' THEN '已按交付清单复核，材料与口径一致。' ELSE '年度虚构场景阶段记录。' END) END,
                        prior,CASE WHEN action='RETURNED' THEN 'RECEIVED' ELSE action END,v,event_time);
                    prior:=CASE WHEN action='RETURNED' THEN 'RECEIVED' ELSE action END;
                END LOOP;
                -- 已发布任务历史审核；隔离公司负责人同样走创始人免审，不伪造自审步骤。
                    SELECT t.issuer_id INTO manager FROM tasks t WHERE t.id=tid;
                    SELECT r.manager_id INTO note FROM reporting_relations r WHERE r.employee_id=manager;
                    INSERT INTO review_requests(id,company_id,applicant_id,kind,target_id,expected_version,before_value,candidate,
                      reason,status,approval_mode,decision_source,created_at)
                      VALUES(tid||'-review',company,manager,'TASK_CREATE',tid,0,'{}',content,'年度历史夹具：已确认任务范围与交付物',
                        'APPROVED','DIRECT_MANAGER',CASE WHEN manager IN('annual-founder','annual-outsider') THEN 'FOUNDER_EXEMPT' ELSE 'DIRECT_MANAGER' END,
                        dispatched-interval '2 hours');
                    IF manager NOT IN('annual-founder','annual-outsider') THEN
                        INSERT INTO review_steps(request_id,reviewer_id,position,state,reason,decided_at,company_id,applicant_id)
                          VALUES(tid||'-review',note,1,'APPROVED','目标清晰，按约定范围派发。',dispatched-interval '1 hour',company,manager);
                    END IF;
                INSERT INTO task_comments(id,company_id,task_id,author_id,body,client_key,created_at)
                  VALUES(tid||'-handoff',company,tid,uid,
                    CASE WHEN previous_id IS NULL THEN '已收到阶段材料，将先核对输入与交付标准。'
                      ELSE '已参考['||previous_id||']整理本次输入，未关闭项继续跟进。' END,
                    tid||'-handoff',dispatched+interval '15 minutes');
                IF slot=4 AND peer IS NOT NULL AND start_time+interval '3 hours'<=cutoff THEN
                    INSERT INTO task_comments(id,company_id,task_id,author_id,parent_id,body,client_key,created_at)
                      VALUES(tid||'-reply',company,tid,peer,tid||'-handoff','已提供本轮样本，将协助核对异常项和交接结果。',tid||'-reply',start_time+interval '3 hours');
                END IF;
                IF dispatched>=cutoff-interval '7 days' THEN
                    INSERT INTO outbox_events(id,company_id,recipient_id,type,object_id,body,dedup_key,created_at)
                      VALUES(tid||'-notice',company,uid,'TASK_DISPATCHED',tid,'{}',tid||'-notice',dispatched);
                END IF;
                previous_id:=tid;
            END LOOP;
        END LOOP;
    END LOOP;

    -- 每人每日唯一日志；工作日为主，不强制每天有记录；当前日保留草稿。
    FOR person IN SELECT * FROM annual_people WHERE status<>'PENDING' LOOP
        uid:='annual-'||person.key; company:=CASE WHEN person.key='outsider' THEN 'annual-peer' ELSE c END;
        salt:=get_byte(decode(md5(person.key),'hex'),0);
        FOR day IN SELECT generate_series(date '2026-06-01',today,interval '1 day')::date LOOP
            IF person.key='lin' AND day<date '2026-10-01' THEN CONTINUE; END IF;
            IF person.status='DISABLED' AND day>date '2026-08-28' THEN CONTINUE; END IF;
            IF (extract(isodow FROM day)>5 AND (day-date '2026-06-01'+salt)%23<>0)
              OR (day-date '2026-06-01'+salt)%13=0 THEN CONTINUE; END IF;
            work_day:=day;
            linked_ids:='[]'; note:=''; idx:=0;
            FOR linked IN SELECT t.* FROM tasks t JOIN task_participants p ON p.task_id=t.id
              WHERE p.user_id=uid AND t.company_id=company
                AND (t.start_at AT TIME ZONE 'Asia/Shanghai')::date<=work_day
                AND t.start_at<=cutoff
              ORDER BY CASE WHEN (t.deadline AT TIME ZONE 'Asia/Shanghai')::date>=work_day THEN 0 ELSE 1 END,
                t.start_at DESC,t.id LIMIT 1+(salt+extract(day FROM work_day)::int)%3 LOOP
                idx:=idx+1; linked_ids:=linked_ids||jsonb_build_array(linked.id);
                note:=note||idx||'. '||CASE WHEN (linked.deadline AT TIME ZONE 'Asia/Shanghai')::date<work_day
                  THEN '复核“'||linked.title||'”交接材料，补充差异解释及后续跟踪记录。'
                  ELSE '推进“'||linked.title||'”，核对本轮样本、记录差异并同步协作同事。' END||E'\n';
            END LOOP;
            IF idx=0 THEN CONTINUE; END IF;
            lid:=uid||'-log-'||to_char(work_day,'YYYYMMDD');
            log_time:=LEAST((work_day+make_time(17+(salt%2),15+(salt%4)*10,0)) AT TIME ZONE 'Asia/Shanghai',cutoff-interval '1 minute');
            log_body:=jsonb_build_object('work',note,
              'blockers',CASE WHEN (salt+extract(day FROM work_day)::int)%7=0 THEN '部分样本尚待同事补充，已在任务评论同步，不影响已核对部分。' ELSE '暂无新增阻碍。' END,
              'tomorrow','跟进未关闭差异，核对下一阶段输入并更新交接材料。',
              'hours',5.5+((salt+extract(day FROM work_day)::int)%5)*0.5,'taskIds',linked_ids);
            INSERT INTO daily_logs(id,company_id,owner_id,business_date,body,submitted,version,created_at,submitted_at)
              VALUES(lid,company,uid,work_day,log_body,work_day<today,CASE WHEN work_day<today THEN 2 ELSE 1 END,
                log_time-interval '2 hours',CASE WHEN work_day<today THEN log_time END);
            INSERT INTO log_tasks(company_id,log_id,task_id) SELECT company,lid,value FROM jsonb_array_elements_text(linked_ids);
            IF work_day<today THEN
                INSERT INTO log_versions(company_id,log_id,version,body,created_at) VALUES(company,lid,2,log_body,log_time);
                IF person.manager IS NOT NULL AND (salt+extract(day FROM work_day)::int)%17=0 THEN
                    INSERT INTO log_comments(id,company_id,log_id,actor_id,text,created_at)
                      VALUES(lid||'-comment',company,lid,'annual-'||person.manager,
                        '请把核对依据同步到对应任务，后续按交接清单继续跟进。',LEAST(log_time+interval '1 hour',cutoff));
                END IF;
            END IF;
        END LOOP;
        IF person.status='ACTIVE' THEN
            INSERT INTO dashboard_items(id,company_id,owner_id,kind,title,body,pinned,position,created_at)
              VALUES(uid||'-personal',company,uid,'PERSONAL','本周优先关闭交接差异',
                jsonb_build_object('text','按本人任务清单核对未关闭差异，补充材料并及时同步直属上级。'),true,0,cutoff-interval '1 day');
        END IF;
    END LOOP;

    FOR person IN SELECT * FROM annual_people WHERE status='PENDING' LOOP
        uid:='annual-'||person.key;
        INSERT INTO review_requests(id,company_id,applicant_id,kind,target_id,expected_version,before_value,candidate,reason,approval_mode)
          VALUES(uid||'-membership',c,uid,'MEMBERSHIP',uid,1,'{}',
            jsonb_build_object('departmentId','annual-'||person.dept),'申请确认组织归属','ADMIN_MEMBERSHIP');
        INSERT INTO review_steps(request_id,reviewer_id,position,company_id,applicant_id)
          VALUES(uid||'-membership','annual-admin',1,c,uid);
        INSERT INTO outbox_events(id,company_id,recipient_id,type,object_id,body,dedup_key,created_at)
          VALUES(uid||'-membership-notice',c,'annual-admin','REVIEW_PENDING',uid||'-membership','{}',uid||'-membership-notice',cutoff);
    END LOOP;

    -- 两条独立的改期候选覆盖待审和驳回，任务本身仍保持原版本/原排期。
    idx:=0;
    FOR item IN SELECT t.* FROM tasks t WHERE t.owner_id='annual-zhou'
      AND t.phase='DISPATCHED' ORDER BY t.start_at,t.id LIMIT 2 LOOP
        idx:=idx+1;
        SELECT r.manager_id INTO manager FROM reporting_relations r WHERE r.employee_id=item.issuer_id;
        INSERT INTO review_requests(id,company_id,applicant_id,kind,target_id,expected_version,before_value,candidate,
          reason,status,approval_mode,decision_source,created_at)
          VALUES(item.id||'-reschedule',c,item.issuer_id,'TASK_RESCHEDULE',item.id,item.version,item.body,
            jsonb_build_object('deadline',item.deadline+interval '2 days'),'补充门店样本需要调整核对时间',
            CASE WHEN idx=1 THEN 'PENDING' ELSE 'REJECTED' END,'DIRECT_MANAGER',
            CASE WHEN idx=2 THEN 'DIRECT_MANAGER' END,cutoff-interval '30 minutes');
        INSERT INTO review_steps(request_id,reviewer_id,position,state,reason,decided_at,company_id,applicant_id)
          VALUES(item.id||'-reschedule',manager,1,CASE WHEN idx=1 THEN 'PENDING' ELSE 'REJECTED' END,
            CASE WHEN idx=2 THEN '先完成已有样本的核对，缩小待补充范围后再申请。' END,
            CASE WHEN idx=2 THEN cutoff-interval '10 minutes' END,c,item.issuer_id);
    END LOOP;

    -- 真正可下载的文本材料；仅追加附件关联，不伪造外部文件地址。
    FOR item IN SELECT t.* FROM tasks t WHERE t.owner_id='annual-zhou' AND t.id LIKE '%-10-%' ORDER BY t.start_at LIMIT 3 LOOP
        INSERT INTO attachments(id,company_id,owner_id,filename,content_type,data,task_id,file_hash,created_at)
          VALUES(item.id||'-file',c,item.owner_id,'阶段核对清单.txt','text/plain',
            convert_to('年度虚构场景：'||item.title||E'\n核对项：输入样本、异常分支、交接依据、权限范围。','UTF8'),item.id,
            encode(sha256(convert_to('年度虚构场景：'||item.title||E'\n核对项：输入样本、异常分支、交接依据、权限范围。','UTF8')),'hex'),item.created_at);
    END LOOP;
    INSERT INTO audit_records(company_id,actor_id,type,object_id,before_value,after_value,reason)
      VALUES(c,'annual-admin','ANNUAL_SCENARIO_INITIALIZED',c,'{}',
        jsonb_build_object('source','db/scenario-annual2026 V1','cutoff',cutoff,'fictional',true),
        '用户显式选择空库年度历史夹具；非真实客户数据，不表示历史HTTP调用');
END
$annual$;
