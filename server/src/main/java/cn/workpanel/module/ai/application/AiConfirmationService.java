package cn.workpanel.module.ai.application;

import cn.workpanel.*;
import cn.workpanel.module.task.*;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.util.*;

/** AI确认只编排版本、来源和回执，正式任务仍经原派发应用服务及审核流程。 */
@Service
public class AiConfirmationService {
    private final Db db;
    private final AiApplicationService ai;
    private final TaskDispatchService tasks;
    public AiConfirmationService(Db db,AiApplicationService ai,TaskDispatchService tasks) { this.db=db; this.ai=ai; this.tasks=tasks; }

    @Transactional
    public Map<String,Object> confirm(Actor supplied,String id,Map<String,Object> body,String key) {
        Db.fields(body,"version","actionIndex","task");
        if(key==null||key.isBlank()||key.length()>128) throw ApiError.bad("IDEMPOTENCY_REQUIRED","确认需要1–128位幂等键");
        var locked=db.one("SELECT * FROM ai_jobs WHERE id=? AND company_id=? AND owner_id=? FOR UPDATE",id,supplied.company(),supplied.id());
        Actor actor=ai.currentOwner(locked); actor.requireDispatch();
        int expected=Db.version(body);
        Object indexValue=body.get("actionIndex");
        if(!(indexValue instanceof Number index)||index.doubleValue()!=index.intValue()||index.intValue()<0||index.intValue()>2) throw ApiError.bad("INVALID_ACTION","行动索引无效");
        if(!(body.get("task") instanceof Map<?,?>)) throw ApiError.bad("INVALID_TASK","需要人工确认的完整任务");
        var task=db.read(db.write(body.get("task")));
        String hash=Db.hash(expected+":"+index.intValue()+":"+TaskDraftNormalizer.hash(db,TaskDraftNormalizer.normalize(task)));
        // 来源失权后不允许利用重放读取旧回执；同键重试可跨后续草稿版本重放。
        var current=ai.job(actor,id);
        if(current.get("output") instanceof Map<?,?> output) ai.validateSources(actor,db.read(db.write(output)));
        var prior=db.rows("SELECT request_hash,response,source_refs FROM ai_task_confirmations WHERE company_id=? AND owner_id=? AND job_id=? AND client_key=?",actor.company(),actor.id(),id,key);
        if(!prior.isEmpty()) {
            if(!hash.equals(Db.str(prior.getFirst(),"request_hash"))) throw new ApiError(409,"IDEMPOTENCY_CONFLICT","同一确认键内容不同");
            ai.validateSources(actor,db.read(prior.getFirst().get("source_refs")));
            return db.read(prior.getFirst().get("response"));
        }
        if(!"SUCCEEDED".equals(locked.get("state"))||((Number)locked.get("version")).intValue()!=expected) throw ApiError.conflict();
        var actions=AiApplicationService.maps(db.read(locked.get("output")),"actions",3);
        if(index.intValue()>=actions.size()) throw ApiError.bad("INVALID_ACTION","行动索引无效");
        String commandKey="ai-confirm:"+Db.hash(actor.id()+":"+id+":"+key);
        var response=tasks.dispatch(actor,task,commandKey);
        var refs=Map.of("sourceIds",Business.strings(actions.get(index.intValue()),"sourceIds"),"nodes",List.of(),"actions",List.of());
        db.update("INSERT INTO ai_task_confirmations(id,company_id,owner_id,job_id,client_key,job_version,action_index,request_hash,source_refs,response) VALUES (?,?,?,?,?,?,?,?,?::jsonb,?::jsonb)",Db.id(),actor.company(),actor.id(),id,key,expected,index.intValue(),hash,db.write(refs),db.write(response));
        db.audit(actor,"AI_TASK_CONFIRMED",id,Map.of("version",expected),Map.of("actionIndex",index.intValue(),"resultId",response.get("id")),"人工确认任务草稿");
        return response;
    }
}
