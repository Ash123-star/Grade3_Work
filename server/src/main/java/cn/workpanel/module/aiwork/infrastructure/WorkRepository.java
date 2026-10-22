package cn.workpanel.module.aiwork.infrastructure;

import cn.workpanel.*;
import org.springframework.stereotype.Repository;
import java.util.*;

/** 持久队列及私有事项存储，所有用户查询固定 owner 和 company。 */
@Repository
public class WorkRepository {
    public final Db db;
    public WorkRepository(Db db){this.db=db;}
    public Db database(){return db;}
    public Map<String,Object> owned(Actor a,String id,boolean lock){return db.one("SELECT * FROM ai_work_items WHERE company_id=? AND owner_id=? AND id=? AND deleted_at IS NULL"+(lock?" FOR UPDATE":""),a.company(),a.id(),id);}
    public List<Map<String,Object>> messages(Actor a,String id){return db.rows("SELECT id,sequence,body,created_at FROM ai_work_messages WHERE company_id=? AND work_id=? ORDER BY sequence",a.company(),id);}
    public void append(Actor a,String id,Map<String,Object> body){db.update("INSERT INTO ai_work_messages(id,company_id,work_id,sequence,body) SELECT ?,?,?,coalesce(max(sequence),0)+1,?::jsonb FROM ai_work_messages WHERE company_id=? AND work_id=?",Db.id(),a.company(),id,db.write(body),a.company(),id);}
    public void step(Actor a,String id,int plan,String key,String action,Map<String,Object> payload){db.update("INSERT INTO ai_work_steps(id,company_id,work_id,plan_version,step_key,action,payload) VALUES (?,?,?,?,?,?,?::jsonb)",Db.id(),a.company(),id,plan,key,action,db.write(payload));}
    public void dependencies(Actor a,String id,int plan,String key,List<String> dependencies){db.update("UPDATE ai_work_steps SET dependencies=?::jsonb WHERE company_id=? AND work_id=? AND plan_version=? AND step_key=?",db.write(dependencies),a.company(),id,plan,key);}
    public boolean completed(Actor a,String id,String action,Map<String,Object> payload){
        String hash=cn.workpanel.module.aiwork.domain.WorkActions.fingerprint(db,action,payload);
        long matchingReceipts=db.rows("SELECT s.action,s.payload FROM ai_action_receipts r JOIN ai_work_steps s ON s.company_id=r.company_id AND s.work_id=r.work_id AND s.plan_version=r.plan_version AND s.step_key=r.step_key WHERE r.company_id=? AND r.actor_id=? AND r.work_id=? AND s.action=? AND r.result->>'kind' IS DISTINCT FROM 'NEEDS_MATERIAL'",a.company(),a.id(),id,action).stream().filter(r->hash.equals(cn.workpanel.module.aiwork.domain.WorkActions.fingerprint(db,Db.str(r,"action"),db.read(r.get("payload"))))).count();
        if(matchingReceipts==0)return false;
        int planVersion=((Number)owned(a,id,false).get("plan_version")).intValue();
        long earlierPlanned=db.rows("SELECT action,payload FROM ai_work_steps WHERE company_id=? AND work_id=? AND plan_version=?",a.company(),id,planVersion).stream().filter(r->hash.equals(cn.workpanel.module.aiwork.domain.WorkActions.fingerprint(db,Db.str(r,"action"),db.read(r.get("payload"))))).count();
        return earlierPlanned<matchingReceipts;
    }
    public void state(Actor a,String id,String state,Map<String,Object> result){
        var before=owned(a,id,true);
        db.update("UPDATE ai_work_items SET state=?,result=?::jsonb,version=version+1,updated_at=now(),error_code=NULL WHERE company_id=? AND id=?",state,db.write(result),a.company(),id);
        event(a,id);
        if(!state.equals(before.get("state"))&&Set.of("WAITING_INPUT","WAITING_CONFIRMATION","FAILED","PARTIAL","SUCCEEDED").contains(state))
            db.notify(a,Db.str(before,"owner_id"),"AI_WORK_UPDATED",id,"ai-work-state:"+id+":"+(((Number)before.get("version")).longValue()+1));
    }
    public void event(Actor a,String id){db.update("INSERT INTO ai_work_events(company_id,work_id,version) SELECT company_id,id,version FROM ai_work_items WHERE company_id=? AND id=?",a.company(),id);}
    public void cancelPending(Actor a,String id){db.update("UPDATE ai_work_steps SET state='CANCELLED',fence=fence+1,lease_until=NULL WHERE company_id=? AND work_id=? AND state IN ('PENDING','RUNNING','WAITING','FAILED','UNKNOWN')",a.company(),id);}
    public Map<String,Object> plan(Actor a,String id,int version){return db.one("SELECT * FROM ai_work_plans WHERE company_id=? AND work_id=? AND version=?",a.company(),id,version);}
}
