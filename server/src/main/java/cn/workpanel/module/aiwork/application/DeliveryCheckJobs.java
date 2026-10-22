package cn.workpanel.module.aiwork.application;

import cn.workpanel.*;
import cn.workpanel.module.attachment.application.AttachmentApplicationService;
import cn.workpanel.module.task.TaskAccess;
import cn.workpanel.shared.application.*;
import jakarta.annotation.PreDestroy;
import org.springframework.stereotype.Service;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import java.util.*;
import java.util.concurrent.*;

/** Durable bounded checks: HTTP accepts immediately, parsing runs outside the business transaction. */
@Service
public class DeliveryCheckJobs {
    private final Db db;private final CurrentActors actors;private final CommandKeys keys;private final AttachmentApplicationService attachments;private final DeliveryService delivery;private final TransactionTemplate tx;
    private final ExecutorService pool=Executors.newSingleThreadExecutor();private final Semaphore slots=new Semaphore(1);
    public DeliveryCheckJobs(Db db,CurrentActors actors,CommandKeys keys,AttachmentApplicationService attachments,DeliveryService delivery,PlatformTransactionManager manager){this.db=db;this.actors=actors;this.keys=keys;this.attachments=attachments;this.delivery=delivery;this.tx=new TransactionTemplate(manager);}
    public Map<String,Object> create(Actor actor,String taskId,Map<String,Object> body,String key){return tx.execute(s->{Actor a=actors.locked(actor);Db.fields(body,"taskVersion","attachmentIds");var task=TaskAccess.readable(db,a,taskId,false);if(!(body.get("taskVersion") instanceof Number version)||version.intValue()!=((Number)task.get("version")).intValue())throw ApiError.conflict();attachments.intake(a,Business.strings(body,"attachmentIds"));var receipt=keys.execute(a,"delivery.enqueue:"+taskId,key,body,()->{String id=Db.id();db.update("INSERT INTO task_delivery_check_jobs(id,company_id,task_id,owner_id,request) VALUES (?,?,?,?,?::jsonb)",id,a.company(),taskId,a.id(),db.write(body));return Map.of("id",id);});return get(a,taskId,Db.str(receipt,"id"));});}
    public Map<String,Object> get(Actor actor,String taskId,String id){Actor a=actors.fresh(actor);TaskAccess.readable(db,a,taskId,false);var rows=db.rows("SELECT * FROM task_delivery_check_jobs WHERE company_id=? AND task_id=? AND owner_id=? AND id=?",a.company(),taskId,a.id(),id);if(rows.isEmpty())return delivery.get(a,taskId,id);var job=rows.getFirst();if("SUCCEEDED".equals(job.get("state")))return delivery.get(a,taskId,Db.str(job,"report_id"));return Map.of("id",id,"state",job.get("state"),"summary",job.get("state").equals("FAILED")?"材料暂时没能核对，请重试":"正在核对材料…","errorCode",Db.str(job,"error_code"));}
    public Map<String,Object> latest(Actor actor,String taskId){Actor a=actors.fresh(actor);TaskAccess.readable(db,a,taskId,false);var rows=db.rows("SELECT id FROM task_delivery_check_jobs WHERE company_id=? AND task_id=? AND owner_id=? ORDER BY created_at DESC LIMIT 1",a.company(),taskId,a.id());return rows.isEmpty()?Map.of():get(a,taskId,Db.str(rows.getFirst(),"id"));}
    @Scheduled(fixedDelay=500)public void tick(){if(!slots.tryAcquire())return;Map<String,Object> job;
        try{job=tx.execute(s->{db.update("UPDATE task_delivery_check_jobs SET state='FAILED',error_code='FILE_TIMEOUT',fence=fence+1,lease_until=NULL,updated_at=now() WHERE state='RUNNING' AND attempts>=3 AND lease_until<now()");var rows=db.rows("SELECT * FROM task_delivery_check_jobs WHERE attempts<3 AND next_run_at<=now() AND (state='QUEUED' OR state='RUNNING' AND lease_until<now()) ORDER BY next_run_at,id FOR UPDATE SKIP LOCKED LIMIT 1");if(rows.isEmpty())return null;String id=Db.str(rows.getFirst(),"id");db.update("UPDATE task_delivery_check_jobs SET state='RUNNING',attempts=attempts+1,fence=fence+1,lease_until=now()+interval '180 seconds',updated_at=now() WHERE id=?",id);return db.one("SELECT * FROM task_delivery_check_jobs WHERE id=?",id);});}catch(Exception e){slots.release();return;}
        if(job==null){slots.release();return;}pool.submit(()->{try{run(job);}finally{slots.release();}});
    }
    private void run(Map<String,Object> job){try{
        Actor a=actors.fresh(new Actor(Db.str(job,"owner_id"),Db.str(job,"company_id"),"","","",false,false,false,"ACTIVE"));
        var report=delivery.check(a,Db.str(job,"task_id"),db.read(job.get("request")),"delivery-job:"+job.get("id"));
        tx.executeWithoutResult(s->{Actor current=actors.locked(a);TaskAccess.readable(db,current,Db.str(job,"task_id"),false);int changed=db.update("UPDATE task_delivery_check_jobs SET state='SUCCEEDED',report_id=?,lease_until=NULL,updated_at=now() WHERE id=? AND fence=? AND state='RUNNING'",report.get("id"),job.get("id"),job.get("fence"));if(changed>0)db.notify(current,current.id(),"DELIVERY_CHECKED",Db.str(job,"task_id"),"delivery-check:"+job.get("id"));});
    }catch(Exception e){String code=e instanceof ApiError api?api.code:"FILE_UNREADABLE";boolean retry="OCR_UNAVAILABLE".equals(code)&&((Number)job.get("attempts")).intValue()<3;db.update("UPDATE task_delivery_check_jobs SET state=?,error_code=?,lease_until=NULL,next_run_at=now()+interval '10 seconds',updated_at=now() WHERE id=? AND fence=? AND state='RUNNING'",retry?"QUEUED":"FAILED",code,job.get("id"),job.get("fence"));}}
    @PreDestroy public void stop(){pool.shutdownNow();}
}
