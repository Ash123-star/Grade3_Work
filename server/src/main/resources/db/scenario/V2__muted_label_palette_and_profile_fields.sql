-- 场景增量：九种低饱和标签；只处理未被用户修改的固定场景对象。
-- 不修改已执行V1，不重建数据库，不覆盖用户自定义标签。
DO $palette$
DECLARE
    entry record;
    task record;
    selected text;
    old_version int;
    kinds text[] := ARRAY['data','research','product','data','product','quality','product','product',
      'engineering','engineering','data','quality','engineering','engineering','quality','quality',
      'doc','delivery','delivery','research','release','quality','data','research',
      'quality','quality','coordination','release','coordination','doc'];
BEGIN
    FOR entry IN SELECT * FROM (VALUES
      ('product','产品体验','#C7D3DF'),('engineering','研发联调','#CBD8CF'),('delivery','试点交付','#E2D6CA'),
      ('data','数据核对','#D6CFE0'),('quality','质量验证','#E2CED2'),('doc','文档培训','#DEDAC6'),
      ('coordination','跨组协作','#C8DAD8'),('release','发布保障','#CDD2D7'),('research','用户调研','#D7DCCB')
    ) AS palette(key,name,color) LOOP
        IF entry.key IN ('product','engineering','delivery') THEN
            UPDATE task_labels SET color=entry.color,version=version+1,updated_at=now()
              WHERE id='scenario-label-'||entry.key AND company_id='scenario-cm' AND version=1;
        ELSE
            INSERT INTO task_labels(id,company_id,name,category,color,creator_id)
              VALUES('scenario-label-'||entry.key,'scenario-cm',entry.name,'PROJECT',entry.color,'scenario-founder');
        END IF;
    END LOOP;
    FOR task IN SELECT t.* FROM tasks t WHERE t.company_id='scenario-cm' AND t.id ~ '^scenario-task-[0-9]{2}$'
      AND NOT EXISTS(SELECT 1 FROM audit_records a WHERE a.company_id=t.company_id AND a.object_id=t.id)
    LOOP
        selected:='scenario-label-'||kinds[substring(task.id from '[0-9]+$')::int];
        IF selected IS NULL OR selected=task.body->>'labelId' THEN CONTINUE; END IF;
        old_version:=task.version;
        UPDATE task_label_links SET label_id=selected WHERE task_id=task.id AND company_id='scenario-cm';
        UPDATE tasks SET body=jsonb_set(body,'{labelId}',to_jsonb(selected)),version=version+1 WHERE id=task.id;
        INSERT INTO task_events(company_id,task_id,actor_id,type,body,from_phase,to_phase,task_version)
          VALUES('scenario-cm',task.id,'scenario-founder','REVISED',jsonb_build_object('labelId',selected,'source','scenario-palette-v2'),task.phase,task.phase,old_version+1);
        UPDATE review_requests SET expected_version=old_version+1,
            before_value=jsonb_set(before_value,'{labelId}',to_jsonb(selected))
          WHERE id='scenario-reschedule-1' AND target_id=task.id AND status='PENDING' AND expected_version=old_version;
        INSERT INTO audit_records(company_id,actor_id,type,object_id,before_value,after_value,reason)
          VALUES('scenario-cm','scenario-founder','SCENARIO_LABEL_REFINED',task.id,
            jsonb_build_object('labelId',task.body->>'labelId','version',old_version),
            jsonb_build_object('labelId',selected,'version',old_version+1),'场景V2：按工作类型分配低饱和标签，保留完整版本和事件');
    END LOOP;
    -- V1简介使用了辅助bio键；只补齐当前前端读取的introduction，不覆盖已有介绍。
    UPDATE review_requests r SET expected_version=u.version+1
      FROM users u WHERE r.target_id=u.id AND r.company_id=u.company_id
        AND r.kind='MEMBERSHIP' AND r.status='PENDING' AND r.expected_version=u.version
        AND u.company_id='scenario-cm' AND u.profile ? 'bio' AND NOT u.profile ? 'introduction';
    UPDATE users SET profile=jsonb_set(profile,'{introduction}',profile->'bio'),version=version+1
      WHERE company_id='scenario-cm' AND profile ? 'bio' AND NOT profile ? 'introduction';
END
$palette$;
