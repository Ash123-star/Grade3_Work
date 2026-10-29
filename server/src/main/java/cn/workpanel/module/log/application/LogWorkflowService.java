package cn.workpanel.module.log.application;

import cn.workpanel.*;
import cn.workpanel.module.log.LogTaskLinks;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.time.LocalDate;
import java.time.Instant;
import java.util.*;

/** 日报工作流应用层：草稿、提交、24小时正文更新、历史和评论均不依赖 HTTP。 */
@Service
public class LogWorkflowService {
    final Db db; final Business business;
    public LogWorkflowService(Db db,Business business) { this.db=db; this.business=business; }

    /** 草稿仅可由本人保存；同一业务日期复用主日报并以 version 防止覆盖。 */
    @Transactional
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
            LogEditWindow.requireOpen(log,Instant.now());
            if((boolean)log.get("submitted")) throw new ApiError(409,"DIRECT_CONTENT_REQUIRED","已提交日报正文请使用 PUT /logs/{id}/content");
            Db.conflict(db.update("UPDATE daily_logs SET body=?::jsonb,version=version+1 WHERE id=? AND version=?",db.write(content),id,Db.version(command)));
        }
        LogTaskLinks.validateAndSync(db,actor,id,content);
        return detail(actor,id);
    }

    /** 详情读取复用统一范围规则，非本人永远不能读取草稿。 */
    public Map<String,Object> detail(Actor actor,String id) {
        var log=business.log(actor,id,false);
        var result=LogEditWindow.view(db,actor,log,Instant.now());
        var author=new LogQueryRepository(db).author(actor,Db.str(log,"owner_id"));
        result.put("author",Map.of("id",Db.str(log,"owner_id"),"name",Db.str(author,"name")));
        result.put("department",Map.of("id",Db.str(author,"department_id"),"name",Db.str(author,"department_name")));
        return result;
    }

    /** 本人提交当前草稿，并在同一事务内产生首个历史版本。 */
    @Transactional
    public Map<String,Object> submit(Actor actor,String id,Map<String,Object> command) {
        Db.fields(command,"version"); var log=business.log(actor,id,true);
        if(!actor.id().equals(log.get("owner_id"))) throw ApiError.forbidden();
        if((boolean)log.get("submitted")) throw ApiError.conflict();
        LogEditWindow.requireOpen(log,Instant.now());
        if(LogEditWindow.submittedAt(log)==null) {
            LocalDate businessDate=log.get("business_date") instanceof java.sql.Date date?date.toLocalDate():LocalDate.parse(Db.str(log,"business_date"));
            LocalDate today=LocalDate.now(java.time.ZoneId.of("Asia/Shanghai"));
            if(businessDate.isBefore(today.minusDays(2))||businessDate.isAfter(today)) throw new ApiError(400,"FIRST_SUBMISSION_WINDOW","首次提交只能选择上海今天、昨天或前天");
        }
        var body=db.read(log.get("body")); Business.validateLog(db,actor,body); int version=Db.version(command);
        Db.conflict(db.update("UPDATE daily_logs SET submitted=true,submitted_at=COALESCE(submitted_at,now()),version=version+1 WHERE id=? AND version=?",id,version));
        db.update("INSERT INTO log_versions(company_id,log_id,version,body) VALUES (?,?,?,?::jsonb)",actor.company(),id,version+1,db.write(body));
        db.audit(actor,"LOG_SUBMITTED",id,Map.of(),body,"提交日报");
        notifyManagers(actor,id); return detail(actor,id);
    }

    /** 本人已提交日报的24小时正文更新，不创建审核候选且保留首次提交时间。 */
    @Transactional
    public Map<String,Object> updateContent(Actor actor,String id,Map<String,Object> command) {
        if(!actor.status().equals("ACTIVE")||actor.mustChange()) throw ApiError.forbidden();
        Db.fields(command,"work","version");
        var staleRequests=db.rows("SELECT id FROM review_requests WHERE company_id=? AND kind='LOG' AND target_id=? AND status='PENDING' ORDER BY id FOR UPDATE",actor.company(),id);
        var log=business.log(actor,id,true);
        if(!actor.id().equals(log.get("owner_id"))) throw ApiError.forbidden();
        if(!Boolean.TRUE.equals(log.get("submitted"))) throw new ApiError(409,"LOG_NOT_SUBMITTED","仅已提交日报可直接修改正文");
        LogEditWindow.requireOpen(log,Instant.now());
        String work=Db.required(command,"work");
        if(work.length()>20000) throw ApiError.bad("INVALID_FIELD","work 不得超过20000字");
        int version=Db.version(command); var body=db.read(log.get("body")); body.put("work",work);
        Db.conflict(db.update("UPDATE daily_logs SET body=?::jsonb,version=version+1 WHERE id=? AND owner_id=? AND submitted=true AND version=?",db.write(body),id,actor.id(),version));
        int next=version+1;
        db.update("INSERT INTO log_versions(company_id,log_id,version,body) VALUES (?,?,?,?::jsonb)",actor.company(),id,next,db.write(body));
        for(var stale:staleRequests) {
            String reviewId=Db.str(stale,"id");
            db.update("UPDATE review_steps SET state='SUPERSEDED',reason='正文已由24小时窗口直接更新',decided_at=now() WHERE request_id=? AND state='PENDING'",reviewId);
            db.update("UPDATE review_requests SET status='SUPERSEDED' WHERE id=? AND status='PENDING'",reviewId);
            db.audit(actor,"LOG_REVIEW_SUPERSEDED",reviewId,Map.of("status","PENDING"),Map.of("status","SUPERSEDED","logId",id,"version",next),"正文已由24小时窗口直接更新");
        }
        db.audit(actor,"LOG_CONTENT_UPDATED",id,Map.of("version",version),Map.of("version",next,"work",work),"24小时内正文直接修改");
        notifyManagers(actor,id,"LOG_UPDATED",next);
        return detail(actor,id);
    }


    /** 历史版本仅对统一可见范围内的已提交日报开放。 */
    public List<Map<String,Object>> versions(Actor actor,String id) {
        var log=business.log(actor,id,false); if(!(boolean)log.get("submitted")) throw ApiError.forbidden();
        return db.rows("SELECT * FROM log_versions WHERE log_id=? ORDER BY version",id);
    }


    /** 返回已提交日报的评语；草稿对本人以外的用户在读取阶段即隐藏。 */
    public List<Map<String,Object>> comments(Actor actor,String id) {
        var log=business.log(actor,id,false); if(!(boolean)log.get("submitted")) throw ApiError.forbidden();
        return db.rows("SELECT c.id,c.actor_id,u.name AS author_name,c.text,c.parent_id,c.created_at FROM log_comments c JOIN users u ON u.id=c.actor_id AND u.company_id=c.company_id WHERE c.log_id=? ORDER BY c.created_at,c.id",id);
    }

    /** 所有有读取权限的人可追加不可变评论；不受正文编辑窗口影响。 */
    public Map<String,Object> comment(Actor actor,String id,Map<String,Object> command) {
        Db.fields(command,"text","parentId"); var log=business.log(actor,id,true);
        if(!(boolean)log.get("submitted")) throw ApiError.forbidden();
        String text=Db.required(command,"text");
        if(text.length()>2000) throw ApiError.bad("INVALID_COMMENT","评论不得超过2000字");
        String parent=command.containsKey("parentId")?Db.required(command,"parentId"):null;
        var recipients=new LinkedHashSet<String>(); recipients.add(Db.str(log,"owner_id"));
        if(parent!=null) {
            var matches=db.rows("SELECT actor_id FROM log_comments WHERE company_id=? AND log_id=? AND id=?",actor.company(),id,parent);
            if(matches.isEmpty()) throw ApiError.bad("INVALID_COMMENT_PARENT","回复目标不属于当前日志");
            var user=db.one("SELECT * FROM users WHERE id=?",matches.getFirst().get("actor_id"));
            if("ACTIVE".equals(user.get("status"))&&Actor.from(user).canSeeUser(db.one("SELECT * FROM users WHERE id=?",log.get("owner_id")))) recipients.add(Db.str(user,"id"));
        }
        String commentId=Db.id(); db.update("INSERT INTO log_comments(id,company_id,log_id,actor_id,text,parent_id) VALUES (?,?,?,?,?,?)",commentId,actor.company(),id,actor.id(),text,parent);
        for(String recipient:recipients) db.notify(actor,recipient,"LOG_COMMENT",id,"comment:"+commentId+":"+recipient);
        return db.one("SELECT c.id,c.actor_id,u.name AS author_name,c.text,c.parent_id,c.created_at FROM log_comments c JOIN users u ON u.id=c.actor_id WHERE c.id=?",commentId);
    }

    private void notifyManagers(Actor actor,String logId) {
        notifyManagers(actor,logId,"LOG_SUBMITTED",0);
    }
    private void notifyManagers(Actor actor,String logId,String type,int version) {
        for(var user:db.rows("SELECT * FROM users WHERE company_id=? AND status='ACTIVE' AND role<>'EMPLOYEE'",actor.company())) {
            Actor manager=Actor.from(user);
            if(!manager.id().equals(actor.id())&&Business.canReadUserLogs(db,manager,db.one("SELECT * FROM users WHERE id=?",actor.id()))) db.notify(actor,manager.id(),type,logId,"log:"+logId+":"+manager.id()+":"+type+":"+version);
        }
    }
}
