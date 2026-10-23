package cn.workpanel.shared.application;

import cn.workpanel.*;
import cn.workpanel.contract.ActorContext;
import org.springframework.stereotype.Component;

/** 所有跨模块/异步动作重新读取服务端身份；不信任调用者携带的角色快照。 */
@Component
public class CurrentActors {
    private final Db db;
    public CurrentActors(Db db) { this.db=db; }
    public Actor fresh(ActorContext context) { return fresh(context.companyId(),context.userId(),false); }
    public Actor fresh(Actor actor) { return fresh(actor.company(),actor.id(),false); }
    public Actor locked(Actor actor) { return fresh(actor.company(),actor.id(),true); }
    private Actor fresh(String company,String id,boolean lock) {
        Actor actor=Actor.from(db.one("SELECT * FROM users WHERE company_id=? AND id=?"+(lock?" FOR UPDATE":""),company,id));
        if(!actor.status().equals("ACTIVE")||actor.mustChange()) throw ApiError.forbidden();
        return actor;
    }
    public String fingerprint(Actor a) { return Db.hash(a.company()+":"+a.id()+":"+a.role()+":"+a.department()+":"+a.team()+":"+a.dispatch()+":"+a.reviewer()); }
}
