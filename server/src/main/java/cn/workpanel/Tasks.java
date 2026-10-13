package cn.workpanel;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import java.util.*;

@RestController
@RequestMapping("/api/tasks")
public class Tasks {
    final Db db; final Business business; final Reviews reviews;
    Tasks(Db db,Business business,Reviews reviews) { this.db=db; this.business=business; this.reviews=reviews; }
    @GetMapping public Map<String,Object> list(HttpServletRequest r,@RequestParam(defaultValue="0") int cursor,@RequestParam(defaultValue="30") int limit,@RequestParam(defaultValue="") String search,@RequestParam(required=false) String ownerId,@RequestParam(required=false) String date,@RequestParam(defaultValue="day") String period) {
        Actor a=Actor.current(r); Business.page(cursor,limit); var c=Business.taskScope(a); var args=new ArrayList<>(c.args()); String where=c.sql()+" AND t.title ILIKE ?"; args.add("%"+search+"%");
        if(ownerId!=null) { var user=db.one("SELECT * FROM users WHERE id=? AND company_id=?",ownerId,a.company()); if(!a.canSeeUser(user)) throw ApiError.forbidden(); where+=" AND t.owner_id=?"; args.add(ownerId); }
        if(date!=null) { var range=Business.range(date,period); where+=" AND t.deadline>=?::timestamptz AND t.deadline<?::timestamptz"; args.add(range.from().toString()); args.add(range.to().toString()); }
        long total=db.count("SELECT count(*) FROM tasks t WHERE "+where,args.toArray()); args.add(limit); args.add(cursor);
        return Map.of("items",db.rows("SELECT t.* FROM tasks t WHERE "+where+" ORDER BY t.deadline,t.id LIMIT ? OFFSET ?",args.toArray()).stream().map(t->Business.taskDto(db,t,false)).toList(),"total",total,"nextCursor",String.valueOf(cursor+limit));
    }
    @PostMapping("/{id}/events") @Transactional
    public Map<String,Object> event(HttpServletRequest r,@PathVariable String id,@RequestBody Map<String,Object> b) {
        Db.fields(b,"type","text","version"); Actor a=Actor.current(r); var t=business.task(a,id,true); String type=Db.required(b,"type"),phase=Db.str(t,"phase"); int version=Db.version(b); boolean issuer=a.id().equals(t.get("issuer_id"))||a.admin(),owner=a.id().equals(t.get("owner_id"));
        String next=switch(type) {
            case "RECEIVED" -> { if(!owner||!phase.equals("DISPATCHED")) throw ApiError.forbidden(); yield "RECEIVED"; }
            case "FEEDBACK" -> { if(db.count("SELECT count(*) FROM task_assignees WHERE task_id=? AND user_id=?",id,a.id())==0||!Set.of("RECEIVED","FEEDBACK").contains(phase)) throw ApiError.forbidden(); Db.required(b,"text"); yield "FEEDBACK"; }
            case "ACCEPTED" -> { if(!issuer||!phase.equals("FEEDBACK")) throw ApiError.forbidden(); yield "ACCEPTED"; }
            case "ARCHIVED" -> { if(!issuer||!phase.equals("ACCEPTED")) throw ApiError.forbidden(); yield "ARCHIVED"; }
            case "WITHDRAWN" -> { if(!issuer||Set.of("ACCEPTED","ARCHIVED","WITHDRAWN").contains(phase)) throw ApiError.forbidden(); Db.required(b,"text"); yield "WITHDRAWN"; }
            default -> throw ApiError.bad("INVALID_EVENT","不支持的任务事件");
        };
        Db.conflict(db.update("UPDATE tasks SET phase=?,version=version+1 WHERE id=? AND version=?",next,id,version));
        db.update("INSERT INTO task_events(company_id,task_id,actor_id,type,body) VALUES (?,?,?,?,?::jsonb)",a.company(),id,a.id(),type,db.write(Map.of("text",Db.str(b,"text"))));
        db.audit(a,"TASK_EVENT",id,Map.of("phase",phase),Map.of("phase",next,"text",Db.str(b,"text")),type);
        var recipients=new HashSet<String>(); recipients.add(Db.str(t,"issuer_id")); db.rows("SELECT user_id FROM task_assignees WHERE task_id=?",id).forEach(p->recipients.add(Db.str(p,"user_id")));
        for(String recipient:recipients) db.notify(a,recipient,"TASK_EVENT",id,"task-event:"+id+":"+version+":"+recipient);
        return Business.taskDto(db,business.task(a,id,false),true);
    }
    @PostMapping("/{id}/revisions") @Transactional
    public Map<String,Object> revision(HttpServletRequest r,@PathVariable String id,@RequestBody Map<String,Object> b) {
        Db.fields(b,"version","reason","candidate"); Actor a=Actor.current(r); a.requireDispatch(); var t=business.task(a,id,true); if(!a.id().equals(t.get("issuer_id"))&&!a.admin()) throw ApiError.forbidden(); if(Set.of("ARCHIVED","WITHDRAWN").contains(t.get("phase"))) throw ApiError.conflict();
        if(!(b.get("candidate") instanceof Map<?,?>)) throw ApiError.bad("INVALID_CANDIDATE","candidate 必须为对象"); var c=cn.workpanel.module.task.TaskRevisionSupport.validate(db,a,id,db.read(db.write(b.get("candidate"))));
        return reviews.create(a,"TASK",id,Db.version(b),db.read(t.get("body")),c,Db.required(b,"reason"));
    }
}
