package cn.workpanel.module.comment;

import cn.workpanel.*;
import cn.workpanel.module.task.TaskAccess;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.util.*;

/** 任务公开评论：只追加，评论、审计和 outbox 在同一事务写入。 */
@Service
public class TaskCommentService {
    private final Db db;
    public TaskCommentService(Db db) { this.db=db; }

    public List<Map<String,Object>> list(Actor actor,String taskId) {
        TaskAccess.readable(db,actor,taskId,false);
        return db.rows("SELECT c.id,c.parent_id,c.body,c.created_at,c.author_id,u.name AS nickname,u.profile->>'avatarAttachmentId' AS avatar_id FROM task_comments c JOIN users u ON u.id=c.author_id WHERE c.task_id=? ORDER BY c.created_at,c.id",taskId);
    }

    @Transactional public Map<String,Object> create(Actor actor,String taskId,Map<String,Object> raw,String clientKey) {
        var task=TaskAccess.readable(db,actor,taskId,true); authorizeWriter(actor,task);
        Db.fields(raw,"text","parentId");
        Object textValue=raw.get("text");
        if(!(textValue instanceof String text)||text.trim().isEmpty()||text.length()>2000) throw ApiError.bad("INVALID_COMMENT","评论长度必须为 1–2000 字");
        if(clientKey==null||clientKey.isBlank()||clientKey.length()>128) throw ApiError.bad("IDEMPOTENCY_REQUIRED","评论需要 1–128 位幂等键");
        String parent=raw.containsKey("parentId")?Db.required(raw,"parentId"):null;
        if(parent!=null&&db.count("SELECT count(*) FROM task_comments WHERE id=? AND task_id=?",parent,taskId)!=1) throw ApiError.bad("INVALID_PARENT_COMMENT","父评论不属于当前任务");
        if(db.count("SELECT count(*) FROM task_comments WHERE task_id=? AND author_id=? AND client_key=?",taskId,actor.id(),clientKey)>0) throw new ApiError(409,"DUPLICATE_COMMENT","请勿重复提交评论");
        String id=Db.id();
        try { db.update("INSERT INTO task_comments(id,company_id,task_id,author_id,parent_id,body,client_key) VALUES (?,?,?,?,?,?,?)",id,actor.company(),taskId,actor.id(),parent,text,clientKey); }
        catch(DuplicateKeyException exception) { throw new ApiError(409,"DUPLICATE_COMMENT","请勿重复提交评论"); }
        db.audit(actor,"TASK_COMMENT_CREATED",id,Map.of(),Map.of("taskId",taskId,"parentId",parent==null?"":parent,"text",text),"新增任务评论");
        var recipients=new LinkedHashSet<String>(); recipients.add(Db.str(task,"issuer_id"));
        for(var row:db.rows("SELECT user_id FROM task_participants WHERE task_id=?",taskId)) recipients.add(Db.str(row,"user_id"));
        if(parent!=null) recipients.add(Db.str(db.one("SELECT author_id FROM task_comments WHERE id=?",parent),"author_id"));
        recipients.remove(actor.id());
        for(String recipient:recipients) db.notify(actor,recipient,"TASK_COMMENT",taskId,"task-comment:"+id+":"+recipient);
        return db.one("SELECT c.id,c.parent_id,c.body,c.created_at,c.author_id,u.name AS nickname,u.profile->>'avatarAttachmentId' AS avatar_id FROM task_comments c JOIN users u ON u.id=c.author_id WHERE c.id=?",id);
    }

    private void authorizeWriter(Actor actor,Map<String,Object> task) {
        if(actor.admin()||actor.id().equals(Db.str(task,"issuer_id"))) return;
        if(db.count("SELECT count(*) FROM task_participants WHERE task_id=? AND user_id=?",Db.str(task,"id"),actor.id())==0) throw ApiError.forbidden();
    }
}
