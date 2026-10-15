package cn.workpanel.module.log.application;

import cn.workpanel.*;
import cn.workpanel.module.log.LogTaskLinks;
import cn.workpanel.module.review.application.ReviewApplicationService;
import org.springframework.stereotype.Service;
import java.time.LocalDate;
import java.util.*;

/** 日报工作流应用层：草稿、提交、候选修订、历史、已读和评语均不依赖 HTTP。 */
@Service
public class LogWorkflowService {
    final Db db; final Business business; final ReviewApplicationService reviews;
    public LogWorkflowService(Db db,Business business,ReviewApplicationService reviews) { this.db=db; this.business=business; this.reviews=reviews; }

    /** 草稿仅可由本人保存；同一业务日期复用主日报并以 version 防止覆盖。 */
    public Map<String,Object> saveDraft(Actor actor,Map<String,Object> command) {
        Db.fields(command,"businessDate","body","version"); String date=Db.required(command,"businessDate");
        try { LocalDate.parse(date); } catch(Exception e) { throw ApiError.bad("INVALID_DATE","businessDate 无效"); }
        if(!(command.get("body") instanceof Map<?,?>)) throw ApiError.bad("INVALID_LOG","body 必须为对象");
        var content=db.read(db.write(command.get("body"))); Db.fields(content,"work","blockers","tomorrow","hours","taskIds");
        db.one("SELECT pg_advisory_xact_lock(hashtextextended(?,0))",actor.id()+":"+date);
        var old=db.rows("SELECT * FROM daily_logs WHERE owner_id=? AND business_date=?::date FOR UPDATE",actor.id(),date); String id;
        if(old.isEmpty()) {
            if(Db.version(command)!=0) throw ApiError.conflict(); id=Db.id();
            db.update("INSERT INTO daily_logs(id,company_id,owner_id,business_date,body) VALUES (?,?,?,?::date,?::jsonb)",id,actor.company(),actor.id(),date,db.write(content));
        } else {
            var log=old.getFirst(); id=Db.str(log,"id");
            if((boolean)log.get("submitted")) throw new ApiError(409,"REVIEW_REQUIRED","已提交日志需候选修订");
            Db.conflict(db.update("UPDATE daily_logs SET body=?::jsonb,version=version+1 WHERE id=? AND version=?",db.write(content),id,Db.version(command)));
        }
        LogTaskLinks.validateAndSync(db,actor,id,content);
        return Business.logDto(db,business.log(actor,id,false));
    }

    /** 详情读取复用统一范围规则，非本人永远不能读取草稿。 */
    public Map<String,Object> detail(Actor actor,String id) { return Business.logDto(db,business.log(actor,id,false)); }

    /** 本人提交当前草稿，并在同一事务内产生首个历史版本。 */
    public Map<String,Object> submit(Actor actor,String id,Map<String,Object> command) {
        Db.fields(command,"version"); var log=business.log(actor,id,true);
        if(!actor.id().equals(log.get("owner_id"))) throw ApiError.forbidden();
        if((boolean)log.get("submitted")) throw ApiError.conflict();
        var body=db.read(log.get("body")); Business.validateLog(db,actor,body); int version=Db.version(command);
        Db.conflict(db.update("UPDATE daily_logs SET submitted=true,submitted_at=now(),version=version+1 WHERE id=? AND version=?",id,version));
        db.update("INSERT INTO log_versions(company_id,log_id,version,body) VALUES (?,?,?,?::jsonb)",actor.company(),id,version+1,db.write(body));
        db.audit(actor,"LOG_SUBMITTED",id,Map.of(),body,"提交日报");
        notifyManagers(actor,id); return Business.logDto(db,business.log(actor,id,false));
    }

    /** 已提交日报只能创建既有 LOG 候选修订，审核链由 review 模块执行。 */
    public Map<String,Object> revise(Actor actor,String id,Map<String,Object> command) {
        Db.fields(command,"version","body","reason"); var log=business.log(actor,id,true);
        if(!actor.id().equals(log.get("owner_id"))&&!actor.admin()) throw ApiError.forbidden();
        if(!(boolean)log.get("submitted")) throw ApiError.bad("DRAFT_LOG","草稿请直接保存");
        if(!(command.get("body") instanceof Map<?,?>)) throw ApiError.bad("INVALID_LOG","body 必须为对象");
        var candidate=db.read(db.write(command.get("body"))); Business.validateLog(db,actor,candidate);
        LogTaskLinks.validate(db,actor,candidate);
        return reviews.create(actor,"LOG",id,Db.version(command),db.read(log.get("body")),candidate,Db.required(command,"reason"));
    }

    /** 历史版本仅对统一可见范围内的已提交日报开放。 */
    public List<Map<String,Object>> versions(Actor actor,String id) {
        var log=business.log(actor,id,false); if(!(boolean)log.get("submitted")) throw ApiError.forbidden();
        return db.rows("SELECT * FROM log_versions WHERE log_id=? ORDER BY version",id);
    }

    /** 可见的已提交日报可标记已读，草稿不得产生已读记录。 */
    public Map<String,Object> markRead(Actor actor,String id) {
        var log=business.log(actor,id,false); if(!(boolean)log.get("submitted")) throw ApiError.forbidden();
        db.update("INSERT INTO log_reads(log_id,reader_id) VALUES (?,?) ON CONFLICT(log_id,reader_id) DO UPDATE SET read_at=now()",id,actor.id());
        return Map.of("ok",true);
    }

    /** 返回已提交日报的评语；草稿对本人以外的用户在读取阶段即隐藏。 */
    public List<Map<String,Object>> comments(Actor actor,String id) {
        var log=business.log(actor,id,false); if(!(boolean)log.get("submitted")) throw ApiError.forbidden();
        return db.rows("SELECT id,actor_id,text,created_at FROM log_comments WHERE log_id=? ORDER BY created_at",id);
    }

    /** 本人或管理者可对可见的已提交日报写入评语。 */
    public Map<String,Object> comment(Actor actor,String id,Map<String,Object> command) {
        Db.fields(command,"text"); var log=business.log(actor,id,false);
        if(!(boolean)log.get("submitted")||!actor.manager()&&!actor.id().equals(log.get("owner_id"))) throw ApiError.forbidden();
        String commentId=Db.id(); db.update("INSERT INTO log_comments VALUES (?,?,?,?,?,now())",commentId,actor.company(),id,actor.id(),Db.required(command,"text"));
        db.notify(actor,Db.str(log,"owner_id"),"LOG_COMMENT",id,"comment:"+commentId); return Map.of("id",commentId);
    }

    private void notifyManagers(Actor actor,String logId) {
        for(var user:db.rows("SELECT * FROM users WHERE company_id=? AND status='ACTIVE' AND role<>'EMPLOYEE'",actor.company())) {
            Actor manager=Actor.from(user);
            if(!manager.id().equals(actor.id())&&manager.canSeeUser(db.one("SELECT * FROM users WHERE id=?",actor.id()))) db.notify(actor,manager.id(),"LOG_SUBMITTED",logId,"log:"+logId+":"+manager.id());
        }
    }
}
