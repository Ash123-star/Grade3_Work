package cn.workpanel.module.message.application;

import cn.workpanel.*;
import cn.workpanel.module.review.infrastructure.ReviewRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.util.*;

/** Notification queries are bounded; all referenced titles use current object visibility. */
@Service
public class NotificationQueryService {
    private final Db db;
    public NotificationQueryService(Db db) { this.db=db; }

    private static final Map<String,List<String>> CATEGORIES=Map.of(
        "任务",List.of("TASK_DISPATCHED","TASK_ASSIGNED","TASK_EVENT","TASK_REVISED","TASK_REASSIGNED","TASK_RESCHEDULED","DELIVERY_CHECKED"),
        "审批",List.of("REVIEW_PENDING","REVIEW_UNASSIGNED"),
        "评论",List.of("TASK_COMMENT","LOG_COMMENT"),
        "待阅提醒",List.of("LOG_SUBMITTED","LOG_UPDATED"),
        "截止提醒",List.of("DEADLINE"),
        "审核结果",List.of("REVIEW_APPROVED","REVIEW_REJECTED"));
    private static String placeholders(int count) { return String.join(",",Collections.nCopies(count,"?")); }

    /** GET v1; recipient scope, optional category/search/unreadOnly plus legacy type.
     * cursor>=0, limit1..100, search<=200; invalid400, auth401/403, rate429.
     * Returns items/total/nextCursor/unread; summary is permission-filtered, no write/idempotency/version needed.
     */
    @Transactional(readOnly=true, isolation=org.springframework.transaction.annotation.Isolation.REPEATABLE_READ)
    public Map<String,Object> list(Actor actor,int cursor,int limit,String type,String category,String search,boolean unreadOnly) {
        Business.page(cursor,limit);
        String keyword=search==null?"":search.trim();
        if(keyword.length()>200) throw ApiError.bad("INVALID_SEARCH","搜索内容不能超过200字");
        if(category!=null&&!category.isBlank()&&!CATEGORIES.containsKey(category)) throw ApiError.bad("INVALID_CATEGORY","消息分类无效");
        var task=Business.taskScope(actor);
        var log=Business.accessibleLogOwnerClause(actor,"l");
        var review=ReviewRepository.readableScope(actor);
        var args=new ArrayList<Object>(task.args());
        args.add(actor.id()); args.addAll(log.args()); args.addAll(review.args());
        args.add(actor.company()); args.add(actor.id());
        String taskTypes="('TASK_DISPATCHED','TASK_ASSIGNED','TASK_EVENT','TASK_REVISED','TASK_REASSIGNED','TASK_RESCHEDULED','TASK_COMMENT','DEADLINE','DELIVERY_CHECKED')";
        String from=" FROM notifications n"
            +" LEFT JOIN tasks t ON n.type IN "+taskTypes+" AND t.id=n.object_id AND t.company_id=n.company_id AND ("+task.sql()+")"
            +" LEFT JOIN daily_logs l ON n.type IN ('LOG_SUBMITTED','LOG_UPDATED','LOG_COMMENT') AND l.id=n.object_id AND l.company_id=n.company_id AND (l.owner_id=? OR (l.submitted AND ("+log.sql()+")))"
            +" LEFT JOIN users author ON author.id=l.owner_id AND author.company_id=l.company_id"
            +" LEFT JOIN review_requests r ON n.type IN ('REVIEW_PENDING','REVIEW_APPROVED','REVIEW_REJECTED','REVIEW_UNASSIGNED') AND r.id=n.object_id AND r.company_id=n.company_id AND ("+review.sql()+")"
            +" WHERE n.company_id=? AND n.recipient_id=?";
        if(type!=null&&!type.isBlank()) { from+=" AND n.type=?"; args.add(type); }
        if(category!=null&&!category.isBlank()) {
            var types=CATEGORIES.get(category);from+=" AND n.type IN ("+placeholders(types.size())+")";args.addAll(types);
        }
        if(unreadOnly) from+=" AND NOT n.is_read";
        String title="CASE n.type"
            +" WHEN 'TASK_DISPATCHED' THEN '收到新任务' WHEN 'TASK_ASSIGNED' THEN '收到新任务'"
            +" WHEN 'TASK_EVENT' THEN '任务进度更新' WHEN 'TASK_REVISED' THEN '任务内容已更新'"
            +" WHEN 'TASK_REASSIGNED' THEN '任务参与安排已调整' WHEN 'TASK_RESCHEDULED' THEN '任务截止时间已调整'"
            +" WHEN 'TASK_COMMENT' THEN '任务新评论' WHEN 'DEADLINE' THEN '任务截止提醒'"
            +" WHEN 'LOG_SUBMITTED' THEN '收到工作日志' WHEN 'LOG_UPDATED' THEN '工作日志已更新' WHEN 'LOG_COMMENT' THEN '日志新评论'"
            +" WHEN 'REVIEW_PENDING' THEN '有申请待审核' WHEN 'REVIEW_APPROVED' THEN '申请已通过' WHEN 'REVIEW_REJECTED' THEN '申请已驳回' WHEN 'REVIEW_UNASSIGNED' THEN '有申请缺少审核人'"
            +" WHEN 'AI_READY' THEN 'AI 分析已完成' WHEN 'AI_WORK_UPDATED' THEN 'AI 工作状态更新' WHEN 'DELIVERY_CHECKED' THEN '任务交付检查已完成' ELSE '工作通知' END";
        String summary="CASE WHEN n.type IN "+taskTypes+" THEN t.title"
            +" WHEN n.type IN ('LOG_SUBMITTED','LOG_UPDATED','LOG_COMMENT') THEN to_char(l.business_date,'YYYY年MM月DD日')||' 工作日志 · '||author.name"
            +" WHEN n.type IN ('REVIEW_PENDING','REVIEW_APPROVED','REVIEW_REJECTED','REVIEW_UNASSIGNED') THEN CASE WHEN r.id IS NULL THEN NULL ELSE COALESCE(NULLIF(r.candidate->>'title',''),'审核申请') END"
            +" WHEN n.type='AI_READY' THEN '查看本次 AI 分析结果' WHEN n.type='AI_WORK_UPDATED' THEN '查看本次 AI 工作进展' ELSE '打开查看具体内容' END";
        String cte="WITH visible_messages AS (SELECT n.*,"+title+" AS message_title,COALESCE("+summary+",'关联内容已不可用或无权查看') AS summary"+from+") ";
        String where="";
        if(!keyword.isBlank()) { where=" WHERE strpos(lower(message_title||' '||summary),lower(?))>0";args.add(keyword); }
        long total=db.count(cte+"SELECT count(*) FROM visible_messages"+where,args.toArray());
        args.add(limit);args.add(cursor);
        var items=db.rows(cte+"SELECT * FROM visible_messages"+where+" ORDER BY sequence DESC LIMIT ? OFFSET ?",args.toArray());
        long next=(long)cursor+items.size();
        var result=new LinkedHashMap<String,Object>();
        result.put("items",items);result.put("total",total);result.put("nextCursor",next<total?String.valueOf(next):null);
        result.put("unread",db.count("SELECT count(*) FROM notifications WHERE company_id=? AND recipient_id=? AND NOT is_read",actor.company(),actor.id()));
        return result;
    }

    public Map<String,Object> readAll(Actor actor) {
        db.update("UPDATE notifications SET is_read=true WHERE company_id=? AND recipient_id=? AND NOT is_read",actor.company(),actor.id());
        return Map.of("ok",true);
    }
    public Map<String,Object> read(Actor actor,String id) {
        Db.conflict(db.update("UPDATE notifications SET is_read=true WHERE id=? AND company_id=? AND recipient_id=?",id,actor.company(),actor.id()));
        return Map.of("ok",true);
    }
}
