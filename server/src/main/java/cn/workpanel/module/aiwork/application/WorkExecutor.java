package cn.workpanel.module.aiwork.application;

import cn.workpanel.*;
import cn.workpanel.module.aiwork.domain.WorkPolicy;
import cn.workpanel.module.aiwork.infrastructure.WorkRepository;
import cn.workpanel.module.task.api.TaskApi;
import cn.workpanel.module.review.api.*;
import cn.workpanel.shared.application.*;
import org.springframework.stereotype.Component;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import jakarta.annotation.PreDestroy;
import java.util.*;
import java.util.concurrent.*;

/** 两个有界工作槽；外部调用不持业务事务，提交检查租约 fence，业务写入与回执原子提交。 */
@Component
public class WorkExecutor {
    private final WorkRepository repo;private final Db db;private final CurrentActors actors;private final WorkPlanner planner;private final WorkService work;private final TaskApi tasks;private final DeliveryService deliveries;private final ReviewApi reviews;private final TransactionTemplate tx;
    private final ExecutorService pool=Executors.newFixedThreadPool(2);private final Semaphore slots=new Semaphore(2);
    public WorkExecutor(WorkRepository repo,CurrentActors actors,WorkPlanner planner,WorkService work,TaskApi tasks,DeliveryService deliveries,ReviewApi reviews,PlatformTransactionManager manager){this.repo=repo;this.db=repo.database();this.actors=actors;this.planner=planner;this.work=work;this.tasks=tasks;this.deliveries=deliveries;this.reviews=reviews;this.tx=new TransactionTemplate(manager);}
    @Scheduled(fixedDelayString="${app.ai-work-poll-ms:1000}") public void tick(){
        if(!work.isEnabled())return;
        reconcileOutcomes();
        for(var expired:db.rows("SELECT * FROM ai_work_steps WHERE state='RUNNING' AND attempts>=3 AND lease_until<now() LIMIT 20"))fail(expired,new ApiError(422,"WORK_TIMEOUT","处理超时，内容已保留，请重试"));
        propagateDependencyFailures();
        while(slots.tryAcquire()){
            Map<String,Object> step;
            try{step=tx.execute(s->{var rows=db.rows("SELECT s.* FROM ai_work_steps s JOIN ai_work_items w ON w.company_id=s.company_id AND w.id=s.work_id WHERE w.deleted_at IS NULL AND w.state NOT IN ('CANCELLED','CANCEL_REQUESTED','WAITING_INPUT','RECONCILING') AND (s.action IN ('PREPARE','CHECK_DELIVERY') OR ?) AND NOT EXISTS(SELECT 1 FROM ai_work_steps prior WHERE prior.company_id=s.company_id AND prior.work_id=s.work_id AND prior.plan_version=s.plan_version AND prior.id<>s.id AND (prior.state='RUNNING' AND prior.lease_until>now() OR prior.state='PENDING' AND prior.step_key<s.step_key)) AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements_text(s.dependencies) dep WHERE NOT EXISTS(SELECT 1 FROM ai_work_steps predecessor WHERE predecessor.company_id=s.company_id AND predecessor.work_id=s.work_id AND predecessor.plan_version=s.plan_version AND predecessor.step_key=dep AND predecessor.state='SUCCEEDED')) AND s.attempts<3 AND s.next_run_at<=now() AND (s.state='PENDING' OR s.state='RUNNING' AND s.lease_until<now()) ORDER BY s.next_run_at,s.id FOR UPDATE OF s SKIP LOCKED LIMIT 1",work.isExecutionEnabled());if(rows.isEmpty())return null;var r=rows.getFirst();db.update("UPDATE ai_work_steps SET state='RUNNING',attempts=attempts+1,fence=fence+1,lease_until=now()+interval '150 seconds' WHERE id=?",r.get("id"));return db.one("SELECT * FROM ai_work_steps WHERE id=?",r.get("id"));});}catch(Exception e){slots.release();org.slf4j.LoggerFactory.getLogger(getClass()).warn("AI queue claim failed: {}",e.getClass().getSimpleName());return;}
            if(step==null){slots.release();break;}
            pool.submit(()->{try{run(step);}finally{slots.release();}});
        }
    }
    /** 所有正式动作与回执同库同事务；取得事项/步骤锁后才核对，不在结果不明时再调业务接口。 */
    public void reconcileOutcomes(){
        for(var candidate:db.rows("SELECT s.*,w.owner_id FROM ai_work_steps s JOIN ai_work_items w ON w.company_id=s.company_id AND w.id=s.work_id WHERE w.deleted_at IS NULL AND w.state NOT IN ('CANCELLED','CANCEL_REQUESTED') AND (s.state='UNKNOWN' AND s.next_run_at<=now() OR s.state='RUNNING' AND s.lease_until<now() AND EXISTS(SELECT 1 FROM ai_action_receipts r WHERE r.company_id=s.company_id AND r.work_id=s.work_id AND r.plan_version=s.plan_version AND r.step_key=s.step_key)) ORDER BY s.next_run_at,s.id LIMIT 20"))try{
            tx.executeWithoutResult(status->{
                Actor actor=actors.locked(new Actor(Db.str(candidate,"owner_id"),Db.str(candidate,"company_id"),"","","",false,false,false,"ACTIVE"));
                String id=Db.str(candidate,"work_id");var item=repo.owned(actor,id,true);
                if(Set.of("CANCELLED","CANCEL_REQUESTED").contains(item.get("state")))return;
                var step=db.one("SELECT * FROM ai_work_steps WHERE id=? FOR UPDATE",candidate.get("id"));
                if(!"UNKNOWN".equals(step.get("state"))&&!("RUNNING".equals(step.get("state"))&&step.get("lease_until") instanceof java.sql.Timestamp lease&&lease.toInstant().isBefore(java.time.Instant.now())))return;
                var receipts=db.rows("SELECT request_hash,result FROM ai_action_receipts WHERE company_id=? AND actor_id=? AND work_id=? AND plan_version=? AND step_key=?",actor.company(),actor.id(),id,step.get("plan_version"),step.get("step_key"));
                if(!receipts.isEmpty()){
                    var receipt=receipts.getFirst();String hash=cn.workpanel.module.aiwork.domain.WorkActions.fingerprint(db,Db.str(step,"action"),db.read(step.get("payload")));
                    if(!hash.equals(receipt.get("request_hash"))){db.update("UPDATE ai_work_steps SET state='UNKNOWN',fence=fence+1,lease_until=NULL,next_run_at=now()+interval '1 hour',error_code='RECEIPT_MISMATCH' WHERE id=?",step.get("id"));repo.state(actor,id,"RECONCILING",Map.of("summary","办理记录需要人工核对，已停止后续操作","errorCode","RECEIPT_MISMATCH"));return;}
                    var result=db.read(receipt.get("result"));db.update("UPDATE ai_work_steps SET state='SUCCEEDED',result=?::jsonb,fence=fence+1,lease_until=NULL,error_code=NULL WHERE id=?",db.write(result),step.get("id"));
                    finish(actor,id,((Number)step.get("plan_version")).intValue(),result);
                }else if("UNKNOWN".equals(step.get("state"))){
                    boolean exhausted=((Number)step.get("attempts")).intValue()>=3;
                    db.update("UPDATE ai_work_steps SET state=?,fence=fence+1,lease_until=NULL,next_run_at=now(),error_code=? WHERE id=?",exhausted?"FAILED":"PENDING",exhausted?"WORK_TIMEOUT":null,step.get("id"));
                    boolean unresolved=db.count("SELECT count(*) FROM ai_work_steps WHERE company_id=? AND work_id=? AND state='UNKNOWN'",actor.company(),id)>0;
                    var result=Map.<String,Object>of("summary",unresolved?"正在核对办理结果，请稍候":exhausted?"核对后仍未完成，内容已保留，请重试":"已核对尚未提交，正在继续办理");
                    if(exhausted&&!unresolved)finish(actor,id,((Number)step.get("plan_version")).intValue(),result);else repo.state(actor,id,unresolved?"RECONCILING":"QUEUED",result);
                }
            });
        }catch(Exception ignored){/* 数据库或身份暂不可用时保留不明状态，下一轮重新核对，不输出私有内容。 */}
    }
    public void propagateDependencyFailures(){
        try{
            int changed=tx.execute(status->{int total=0,updated;do{updated=db.update("UPDATE ai_work_steps dependent SET state='FAILED',error_code='DEPENDENCY_FAILED',result='{}'::jsonb,lease_until=NULL WHERE dependent.state IN ('PENDING','WAITING') AND EXISTS (SELECT 1 FROM jsonb_array_elements_text(dependent.dependencies) dep(step_key) JOIN ai_work_steps predecessor ON predecessor.company_id=dependent.company_id AND predecessor.work_id=dependent.work_id AND predecessor.plan_version=dependent.plan_version AND predecessor.step_key=dep.step_key WHERE predecessor.state IN ('FAILED','CANCELLED','SKIPPED'))");total+=updated;}while(updated>0);return total;});
            if(changed==0)return;
            for(var row:db.rows("SELECT w.id,w.company_id,w.owner_id FROM ai_work_items w WHERE w.deleted_at IS NULL AND w.state NOT IN ('CANCELLED','CANCEL_REQUESTED','SUCCEEDED','FAILED','PARTIAL','RECONCILING') AND EXISTS(SELECT 1 FROM ai_work_steps s WHERE s.company_id=w.company_id AND s.work_id=w.id AND s.state='FAILED') AND NOT EXISTS(SELECT 1 FROM ai_work_steps s WHERE s.company_id=w.company_id AND s.work_id=w.id AND s.state IN ('PENDING','RUNNING','WAITING','UNKNOWN'))")){
                tx.executeWithoutResult(status->{Actor actor=new Actor(Db.str(row,"owner_id"),Db.str(row,"company_id"),"","","",false,false,false,"ACTIVE");var item=repo.owned(actor,Db.str(row,"id"),true);if(Set.of("CANCELLED","CANCEL_REQUESTED","SUCCEEDED","FAILED","PARTIAL").contains(item.get("state")))return;
                    long receipts=db.count("SELECT count(*) FROM ai_action_receipts WHERE company_id=? AND work_id=?",actor.company(),row.get("id"));repo.state(actor,Db.str(row,"id"),receipts>0?"PARTIAL":"FAILED",Map.of("summary","前置步骤未完成，已保留已办理内容","errorCode","DEPENDENCY_FAILED"));});
            }
        }catch(Exception e){org.slf4j.LoggerFactory.getLogger(getClass()).warn("AI dependency reconciliation failed: {}",e.getClass().getSimpleName());}
    }
    private void run(Map<String,Object> step){String id=Db.str(step,"work_id");Actor a;
        try{
            var row=db.one("SELECT w.*,u.role,u.department_id,u.team_id,u.dispatch_enabled,u.company_reviewer,u.must_change_password,u.status FROM ai_work_items w JOIN users u ON u.company_id=w.company_id AND u.id=w.owner_id WHERE w.company_id=? AND w.id=? AND w.deleted_at IS NULL",step.get("company_id"),id);
            a=actors.fresh(new Actor(Db.str(row,"owner_id"),Db.str(row,"company_id"),"","","",false,false,false,"ACTIVE"));
            String action=Db.str(step,"action");
            if(action.equals("PREPARE")){
                tx.executeWithoutResult(s->{Actor current=actors.locked(a);locked(current,step);repo.state(current,id,"PREPARING",Map.of("summary","正在整理要求…"));});
                var plan=planner.prepare(a,repo.messages(a,id));
                tx.executeWithoutResult(s->{Actor current=actors.locked(a);work.lockAuthorizationPolicy(current);var item=locked(current,step);if(!actors.fingerprint(current).equals(plan.get("permissionFingerprint")))throw ApiError.forbidden();int version=((Number)item.get("plan_version")).intValue()+1;String hash=Db.hash(db.write(CommandKeys.canonical(plan)));
                    db.update("INSERT INTO ai_work_plans(company_id,work_id,version,body,hash,permission_fingerprint,expires_at) VALUES (?,?,?,?::jsonb,?,?,now()+interval '10 minutes')",a.company(),id,version,db.write(plan),hash,actors.fingerprint(current));
                    db.update("UPDATE ai_work_items SET plan_version=?,title=? WHERE company_id=? AND id=?",version,Db.str(plan,"summary").isBlank()?item.get("title"):plan.get("summary"),a.company(),id);
                    var actions=DeliveryService.maps(plan,"actions");boolean questions=plan.get("questions") instanceof List<?> q&&!q.isEmpty();boolean waiting=false;int pos=0;
                    int resume=db.read(step.get("payload")).get("resumePlanVersion") instanceof Number n?n.intValue():0;
                    for(var candidate:actions){String type=Db.str(candidate,"type");var payload=db.read(candidate.get("payload"));boolean dispatchAllowed=!type.equals("CREATE_TASK")||WorkPolicy.canDispatch(current);
                        boolean reused=resume>0&&work.reusableAuthorization(current,id,resume,type,payload,plan);
                        boolean automatic=type.equals("CHECK_DELIVERY")||DeliveryService.maps(candidate,"similarTasks").isEmpty()&&dispatchAllowed&&(resume>0?reused:Boolean.TRUE.equals(candidate.get("explicit"))||work.preauthorized(current,type,payload,actions.size()));String key="action-"+(++pos);

                        if(repo.completed(current,id,type,payload)){repo.step(current,id,version,key,type,payload);db.update("UPDATE ai_work_steps SET state='SUCCEEDED',result='{\"summary\":\"此前已办理\"}'::jsonb WHERE company_id=? AND work_id=? AND plan_version=? AND step_key=?",a.company(),id,version,key);continue;}
                        payload.put("explicit",resume==0&&Boolean.TRUE.equals(candidate.get("explicit")));payload.put("preauthorized",work.preauthorized(current,type,payload,actions.size()));payload.put("confirmed",reused);repo.step(current,id,version,key,type,payload);repo.dependencies(current,id,version,key,Business.strings(candidate,"dependencies"));
                        if(questions){db.update("UPDATE ai_work_steps SET state='WAITING' WHERE company_id=? AND work_id=? AND plan_version=? AND step_key=?",a.company(),id,version,key);}
                        else if(!automatic){waiting=true;db.update("UPDATE ai_work_steps SET state='WAITING' WHERE company_id=? AND work_id=? AND plan_version=? AND step_key=?",a.company(),id,version,key);}
                    }
                    complete(step,Map.of("summary","要求已整理"));
                    long remaining=db.count("SELECT count(*) FROM ai_work_steps WHERE company_id=? AND work_id=? AND plan_version=? AND action<>'PREPARE' AND state IN ('PENDING','WAITING')",a.company(),id,version);
                    String state=questions?"WAITING_INPUT":remaining==0?"SUCCEEDED":waiting?"WAITING_CONFIRMATION":"EXECUTING";
                    if(waiting)db.update("INSERT INTO ai_work_confirmations(id,company_id,work_id,plan_version,plan_hash,expires_at) VALUES (?,?,?,?,?,now()+interval '10 minutes')",Db.id(),a.company(),id,version,hash);
                    repo.state(current,id,state,Map.of("summary",questions?"补充信息后就能继续":waiting?"请核对要办理的操作":actions.isEmpty()?Db.str(plan,"answer"):remaining==0?"已办理的操作已保留":"正在办理…"));
                });
            }else{
                var payload=db.read(step.get("payload"));Map<String,Object> check=null;
                if(action.equals("CHECK_DELIVERY")||action.equals("SUBMIT_DELIVERY"))check=deliveries.check(a,Db.str(payload,"taskId"),Map.of("taskVersion",payload.get("taskVersion"),"attachmentIds",payload.get("attachmentIds")),"work-check:"+step.get("id"));
                final var report=check;
                tx.executeWithoutResult(s->{Actor current=actors.locked(a);work.lockAuthorizationPolicy(current);locked(current,step);work.validateStep(current,repo.plan(current,id,((Number)step.get("plan_version")).intValue()),Db.str(step,"step_key"));
                    if(!WorkPolicy.readOnly(action)&&!work.isExecutionEnabled())throw new ApiError(503,"EXECUTION_DISABLED","自动办理暂时关闭，内容已保留");
                    boolean granted=action.equals("CHECK_DELIVERY")||Boolean.TRUE.equals(payload.get("explicit"))||Boolean.TRUE.equals(payload.get("confirmed"))||Boolean.TRUE.equals(payload.get("preauthorized"))&&work.preauthorized(current,action,payload,DeliveryService.maps(db.read(repo.plan(current,id,((Number)step.get("plan_version")).intValue()).get("body")),"actions").size());
                    if(!granted)throw ApiError.forbidden();
                    var receipt=db.rows("SELECT result FROM ai_action_receipts WHERE company_id=? AND actor_id=? AND work_id=? AND plan_version=? AND step_key=?",a.company(),a.id(),id,step.get("plan_version"),step.get("step_key"));Map<String,Object> result;
                    if(!receipt.isEmpty())result=db.read(receipt.getFirst().get("result"));else{
                        String key="ai-work:"+step.get("id");var context=ReviewActors.context(current);var b=new LinkedHashMap<>(payload);b.keySet().removeAll(Set.of("explicit","confirmed","preauthorized"));
                        switch(action){
                            case "CREATE_TASK"->{var t=tasks.create(context,b,key);result=Map.of("taskId",t.get("id"),"version",t.get("version"),"summary","任务已创建","kind","TASK_CREATED");}
                            case "CHECK_DELIVERY"->result=Map.of("taskId",payload.get("taskId"),"checkId",report.get("id"),"summary",report.get("summary"),"report",report,"kind","DELIVERY_CHECKED");
                            case "SUBMIT_DELIVERY"->{if(!"PASS".equals(report.get("state"))){result=Map.of("taskId",payload.get("taskId"),"checkId",report.get("id"),"summary",report.get("summary"),"report",report,"kind","NEEDS_MATERIAL");}else{
                                String text=Db.str(payload,"text");if(text.isBlank())text="交付材料已核对，请验收";result=deliveries.submit(current,Db.str(payload,"taskId"),Map.of("taskVersion",payload.get("taskVersion"),"checkId",report.get("id"),"checkVersion",report.get("version"),"attachmentIds",payload.get("attachmentIds"),"mode","CHECKED","text",text),key);}}
                            case "REQUEST_RESCHEDULE","REQUEST_REASSIGNMENT"->{var request=new LinkedHashMap<String,Object>();request.put("version",payload.get("taskVersion"));request.put("reason",payload.get("reason"));request.put(action.equals("REQUEST_RESCHEDULE")?"deadline":"ownerId",payload.get(action.equals("REQUEST_RESCHEDULE")?"deadline":"ownerId"));var review=action.equals("REQUEST_RESCHEDULE")?tasks.requestReschedule(context,Db.str(payload,"taskId"),request):tasks.requestReassignment(context,Db.str(payload,"taskId"),request);result=Map.of("taskId",payload.get("taskId"),"reviewId",review.get("id"),"summary","申请已提交，等待复核","kind","WAITING_REVIEW");}
                            default->throw ApiError.bad("INVALID_ACTION","暂不支持这项操作");
                        }
                        db.update("INSERT INTO ai_action_receipts(company_id,actor_id,work_id,plan_version,step_key,request_hash,result) VALUES (?,?,?,?,?,?,?::jsonb)",a.company(),a.id(),id,step.get("plan_version"),step.get("step_key"),cn.workpanel.module.aiwork.domain.WorkActions.fingerprint(db,action,b),db.write(result));
                        db.audit(current,"AI_WORK_ACTION",id,Map.of(),Map.of("action",action,"step",step.get("step_key")),"办理事项");
                    }
                    complete(step,result);finish(current,id,((Number)step.get("plan_version")).intValue(),result);
                });
            }
        }catch(Exception e){fail(step,e);}
    }
    private Map<String,Object> locked(Actor a,Map<String,Object> step){if(!work.isEnabled())throw new ApiError(503,"WORK_DISABLED","AI 办事暂时不可用，内容已保留");var item=repo.owned(a,Db.str(step,"work_id"),true);var live=db.one("SELECT * FROM ai_work_steps WHERE id=? FOR UPDATE",step.get("id"));if(!"RUNNING".equals(live.get("state"))||((Number)live.get("fence")).longValue()!=((Number)step.get("fence")).longValue()||((java.sql.Timestamp)live.get("lease_until")).toInstant().isBefore(java.time.Instant.now())||Set.of("CANCELLED","CANCEL_REQUESTED").contains(item.get("state")))throw ApiError.conflict();return item;}
    private void complete(Map<String,Object> step,Map<String,Object> result){Db.conflict(db.update("UPDATE ai_work_steps SET state='SUCCEEDED',result=?::jsonb,lease_until=NULL,error_code=NULL WHERE id=? AND fence=? AND state='RUNNING'",db.write(result),step.get("id"),step.get("fence")));}
    private void finish(Actor a,String id,int version,Map<String,Object> result){
        if(db.count("SELECT count(*) FROM ai_work_steps WHERE company_id=? AND work_id=? AND plan_version=? AND state='UNKNOWN'",a.company(),id,version)>0){repo.state(a,id,"RECONCILING",Map.of("summary","正在核对办理结果，请稍候"));return;}
        long pending=db.count("SELECT count(*) FROM ai_work_steps WHERE company_id=? AND work_id=? AND plan_version=? AND state IN ('PENDING','RUNNING')",a.company(),id,version);
        long waiting=db.count("SELECT count(*) FROM ai_work_steps WHERE company_id=? AND work_id=? AND plan_version=? AND state='WAITING'",a.company(),id,version);
        if(pending>0||waiting>0){repo.state(a,id,waiting>0?"WAITING_CONFIRMATION":"EXECUTING",result);return;}
        long failed=db.count("SELECT count(*) FROM ai_work_steps WHERE company_id=? AND work_id=? AND plan_version=? AND state='FAILED'",a.company(),id,version);
        var receipts=db.rows("SELECT result FROM ai_action_receipts WHERE company_id=? AND work_id=? AND plan_version=?",a.company(),id,version).stream().map(r->db.read(r.get("result"))).toList();
        String state=failed>0?(receipts.isEmpty()?"FAILED":"PARTIAL"):receipts.stream().anyMatch(r->"WAITING_REVIEW".equals(r.get("kind")))?"WAITING_REVIEW":receipts.stream().anyMatch(r->"NEEDS_MATERIAL".equals(r.get("kind")))?"WAITING_INPUT":"SUCCEEDED";
        repo.state(a,id,state,result);
    }
    private void fail(Map<String,Object> step,Exception error){try{tx.executeWithoutResult(s->{var w=db.rows("SELECT * FROM ai_work_items WHERE company_id=? AND id=? AND deleted_at IS NULL FOR UPDATE",step.get("company_id"),step.get("work_id"));if(w.isEmpty())return;var row=w.getFirst();if(Set.of("CANCELLED","CANCEL_REQUESTED").contains(row.get("state")))return;
        String code=error instanceof ApiError api?api.code:"WORK_FAILED";boolean retry=Set.of("AI_PROVIDER_FAILED","OCR_UNAVAILABLE").contains(code)&&((Number)step.get("attempts")).intValue()<3;
        boolean unknown=error instanceof org.springframework.transaction.TransactionException||error instanceof org.springframework.dao.DataAccessResourceFailureException||error instanceof org.springframework.dao.TransientDataAccessResourceException;
        int changed=db.update("UPDATE ai_work_steps SET state=?,error_code=?,next_run_at=now()+interval '10 seconds',lease_until=NULL WHERE id=? AND fence=? AND state='RUNNING'",unknown?"UNKNOWN":retry?"PENDING":"FAILED",code,step.get("id"),step.get("fence"));if(changed==0)return;
        Actor a=new Actor(Db.str(row,"owner_id"),Db.str(row,"company_id"),"","","",false,false,false,"ACTIVE");long succeeded=db.count("SELECT count(*) FROM ai_action_receipts WHERE company_id=? AND work_id=?",a.company(),row.get("id"));repo.state(a,Db.str(row,"id"),unknown?"RECONCILING":retry?"QUEUED":succeeded>0?"PARTIAL":"FAILED",Map.of("summary",unknown?"正在核对办理结果，请稍候":failureMessage(code),"errorCode",code));
    });}catch(Exception ignored){/* 数据库不可用时由租约恢复；不输出用户原文或供应商响应。 */}}
    private static String failureMessage(String code){return switch(code){
        case "INVALID_TRANSITION"->"任务当前还不能提交反馈，请先查看任务进展";
        case "FORBIDDEN"->"你目前没有办理这项操作的权限，材料已保留";
        case "CHECK_STALE","VERSION_CONFLICT","CONFLICT","PLAN_STALE"->"办理条件已更新，请重新核对后继续";
        case "FILE_LIMIT","FILE_TYPE_MISMATCH","UNSUPPORTED_FILE","FILE_UNSAFE","FILE_ENCRYPTED"->cn.workpanel.shared.application.AiFilePolicy.error(code).getMessage();
        default->"暂时没能处理，内容已保留";
    };}
    @Scheduled(fixedDelay=10000) public void reconcileReviews(){
        for(var row:db.rows("SELECT id,company_id,owner_id,plan_version FROM ai_work_items WHERE state='WAITING_REVIEW' AND deleted_at IS NULL LIMIT 50"))try{
            var a=actors.fresh(new Actor(Db.str(row,"owner_id"),Db.str(row,"company_id"),"","","",false,false,false,"ACTIVE"));
            var results=new ArrayList<Map<String,Object>>();
            for(var receipt:db.rows("SELECT result FROM ai_action_receipts WHERE company_id=? AND work_id=? AND plan_version=?",a.company(),row.get("id"),row.get("plan_version"))){var result=db.read(receipt.get("result"));if(result.containsKey("reviewId"))results.add(reviews.get(ReviewActors.context(a),Db.str(result,"reviewId")));}
            if(results.isEmpty()||results.stream().anyMatch(r->"PENDING".equals(r.get("status"))))continue;
            boolean approved=results.stream().allMatch(r->"APPROVED".equals(r.get("status")));
            tx.executeWithoutResult(s->{Actor current=actors.locked(a);var live=repo.owned(current,Db.str(row,"id"),true);if("WAITING_REVIEW".equals(live.get("state"))&&Objects.equals(live.get("plan_version"),row.get("plan_version"))){repo.state(current,Db.str(row,"id"),approved?"SUCCEEDED":"WAITING_INPUT",Map.of("summary",approved?"复核已通过，变更已生效":"申请被退回，请查看原因后调整","reviews",results.stream().map(r->Map.of("id",r.get("id"),"status",r.get("status"),"reason",Db.str(r,"reason"))).toList()));}});
        }catch(ApiError ignored){}
    }
    @PreDestroy public void stop(){pool.shutdownNow();}
}
