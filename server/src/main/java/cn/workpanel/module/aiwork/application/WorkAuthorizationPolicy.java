package cn.workpanel.module.aiwork.application;

import cn.workpanel.*;
import cn.workpanel.module.aiwork.domain.AuthorizationPolicy;
import org.springframework.stereotype.Component;
import java.util.*;

@Component
public class WorkAuthorizationPolicy {
    private final Db db;
    public WorkAuthorizationPolicy(Db db){this.db=db;}
    /** 动作提交持有公司行共享锁；POLICY生效的UPDATE取得排他锁，从而与授权撤回/提交串行。 */
    public Map<String,Object> row(Actor actor,boolean lock){return db.one("SELECT version,ai_authorization_revision,review_policy FROM companies WHERE id=?"+(lock?" FOR SHARE":""),actor.company());}
    public AuthorizationPolicy rules(Map<String,Object> row){return AuthorizationPolicy.from(db.read(row.get("review_policy")));}
    public Map<String,Object> view(Actor actor){var row=row(actor,false);var p=rules(row);return Map.of("version",row.get("version"),"revision",row.get("ai_authorization_revision"),"canCreate",p.create()&&actor.dispatch()&&actor.manager(),"canSubmit",p.submit(),"maxDays",p.days(),"maxObjects",p.objects(),"maxActions",p.actions(),"values",p.values());}
}
