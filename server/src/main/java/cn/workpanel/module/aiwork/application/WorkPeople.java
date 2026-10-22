package cn.workpanel.module.aiwork.application;

import cn.workpanel.*;
import org.springframework.stereotype.Component;
import java.util.*;

/** 规划和确认共用实时人员范围快照，调岗或更名不能复用旧的人员候选。 */
@Component
public class WorkPeople {
    private final Db db;
    public WorkPeople(Db db){this.db=db;}
    public List<Map<String,Object>> snapshot(Actor a){
        var args=new ArrayList<Object>();args.add(a.company());args.addAll(Arrays.asList(a.scopeArgs()));
        return db.rows("SELECT u.id,u.name,u.department_id,u.team_id,d.name AS department_name,t.name AS team_name FROM users u LEFT JOIN departments d ON d.company_id=u.company_id AND d.id=u.department_id LEFT JOIN teams t ON t.company_id=u.company_id AND t.id=u.team_id WHERE u.company_id=? AND u.status='ACTIVE' AND ("+a.userScope("u")+") ORDER BY u.name,u.id",args.toArray());
    }
    public void validate(Actor a,Map<String,Object> plan){
        var used=new HashSet<String>();for(var action:DeliveryService.maps(plan,"actions")){String owner=Db.str(db.read(action.get("payload")),"ownerId");if(!owner.isBlank())used.add(owner);}
        var before=DeliveryService.maps(plan,"people");var current=snapshot(a);
        for(String id:used){var expected=before.stream().filter(p->id.equals(p.get("id"))).toList();var live=current.stream().filter(p->id.equals(p.get("id"))).toList();
            if(expected.size()!=1||!expected.equals(live))throw new ApiError(409,"PLAN_STALE","人员信息已更新，请重新核对");
        }
    }
}
