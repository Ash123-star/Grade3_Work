package cn.workpanel;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import java.time.*;
import java.util.*;

@RestController
@RequestMapping("/api/logs")
public class Logs {
    final Db db; final Business business; final Reviews reviews;
    Logs(Db db,Business business,Reviews reviews) { this.db=db; this.business=business; this.reviews=reviews; }
    @GetMapping public Map<String,Object> list(HttpServletRequest r,@RequestParam(defaultValue="0") int cursor,@RequestParam(defaultValue="30") int limit,@RequestParam(required=false) String ownerId,@RequestParam(required=false) String date,@RequestParam(defaultValue="day") String period) {
        return list(Actor.current(r),cursor,limit,ownerId,date,period,false);
    }
    @GetMapping("/subordinates") public Map<String,Object> subordinates(HttpServletRequest r,@RequestParam(defaultValue="0") int cursor,@RequestParam(defaultValue="30") int limit,@RequestParam(required=false) String ownerId,@RequestParam(required=false) String date,@RequestParam(defaultValue="day") String period) { Actor a=Actor.current(r); if(!a.manager()) throw ApiError.forbidden(); return list(a,cursor,limit,ownerId,date,period,true); }
    Map<String,Object> list(Actor a,int cursor,int limit,String ownerId,String date,String period,boolean subordinate) {
        Business.page(cursor,limit); var c=Business.ownerScope(a,"l"); var args=new ArrayList<>(c.args()); String where=c.sql()+" AND (l.submitted OR l.owner_id=?)"; args.add(a.id());
        if(subordinate) { where+=" AND l.owner_id<>? AND l.submitted"; args.add(a.id()); }
        if(ownerId!=null) { if(!a.canSeeUser(db.one("SELECT * FROM users WHERE id=? AND company_id=?",ownerId,a.company()))) throw ApiError.forbidden(); where+=" AND l.owner_id=?"; args.add(ownerId); }
        if(date!=null) { var range=Business.range(date,period); where+=" AND business_date>=?::date AND business_date<?::date"; args.add(range.first().toString()); args.add(range.end().toString()); }
        long total=db.count("SELECT count(*) FROM daily_logs l WHERE "+where,args.toArray()); args.add(limit); args.add(cursor);
        return Map.of("items",db.rows("SELECT l.* FROM daily_logs l WHERE "+where+" ORDER BY business_date DESC,l.id LIMIT ? OFFSET ?",args.toArray()).stream().map(l->Business.logDto(db,l)).toList(),"total",total,"nextCursor",String.valueOf(cursor+limit));
    }
    @GetMapping("/{id}") public Map<String,Object> detail(HttpServletRequest r,@PathVariable String id) { return Business.logDto(db,business.log(Actor.current(r),id,false)); }
    @PutMapping("/draft") @Transactional
    public Map<String,Object> draft(HttpServletRequest r,@RequestBody Map<String,Object> b) {
        Db.fields(b,"businessDate","body","version"); Actor a=Actor.current(r); String date=Db.required(b,"businessDate"); try { LocalDate.parse(date); } catch(Exception e) { throw ApiError.bad("INVALID_DATE","businessDate 无效"); }
        if(!(b.get("body") instanceof Map<?,?>)) throw ApiError.bad("INVALID_LOG","body 必须为对象"); var content=db.read(db.write(b.get("body"))); Db.fields(content,"work","blockers","tomorrow","hours","taskIds");
        db.one("SELECT pg_advisory_xact_lock(hashtextextended(?,0))",a.id()+":"+date);
        var old=db.rows("SELECT * FROM daily_logs WHERE owner_id=? AND business_date=?::date FOR UPDATE",a.id(),date); String id;
        if(old.isEmpty()) { if(Db.version(b)!=0) throw ApiError.conflict(); id=Db.id(); db.update("INSERT INTO daily_logs(id,company_id,owner_id,business_date,body) VALUES (?,?,?,?::date,?::jsonb)",id,a.company(),a.id(),date,db.write(content)); }
        else { var l=old.getFirst(); id=Db.str(l,"id"); if((boolean)l.get("submitted")) throw new ApiError(409,"REVIEW_REQUIRED","已提交日志需候选修订"); Db.conflict(db.update("UPDATE daily_logs SET body=?::jsonb,version=version+1 WHERE id=? AND version=?",db.write(content),id,Db.version(b))); }
        return Business.logDto(db,business.log(a,id,false));
    }
    @PostMapping("/{id}/submit") @Transactional
    public Map<String,Object> submit(HttpServletRequest r,@PathVariable String id,@RequestBody Map<String,Object> b) {
        Db.fields(b,"version"); Actor a=Actor.current(r); var l=business.log(a,id,true); if(!a.id().equals(l.get("owner_id"))) throw ApiError.forbidden(); if((boolean)l.get("submitted")) throw ApiError.conflict(); var body=db.read(l.get("body")); Business.validateLog(db,a,body);
        int v=Db.version(b); Db.conflict(db.update("UPDATE daily_logs SET submitted=true,submitted_at=now(),version=version+1 WHERE id=? AND version=?",id,v));
        db.update("INSERT INTO log_versions(company_id,log_id,version,body) VALUES (?,?,?,?::jsonb)",a.company(),id,v+1,db.write(body)); db.audit(a,"LOG_SUBMITTED",id,Map.of(),body,"提交日报");
        for(var user:db.rows("SELECT * FROM users WHERE company_id=? AND status='ACTIVE' AND role<>'EMPLOYEE'",a.company())) { Actor manager=Actor.from(user); if(!manager.id().equals(a.id())&&manager.canSeeUser(db.one("SELECT * FROM users WHERE id=?",a.id()))) db.notify(a,manager.id(),"LOG_SUBMITTED",id,"log:"+id+":"+manager.id()); }
        return Business.logDto(db,business.log(a,id,false));
    }
    @PostMapping("/{id}/revisions") @Transactional
    public Map<String,Object> revise(HttpServletRequest r,@PathVariable String id,@RequestBody Map<String,Object> b) {
        Db.fields(b,"version","body","reason"); Actor a=Actor.current(r); var l=business.log(a,id,true); if(!a.id().equals(l.get("owner_id"))&&!a.admin()) throw ApiError.forbidden(); if(!(boolean)l.get("submitted")) throw ApiError.bad("DRAFT_LOG","草稿请直接保存");
        if(!(b.get("body") instanceof Map<?,?>)) throw ApiError.bad("INVALID_LOG","body 必须为对象"); var c=db.read(db.write(b.get("body"))); Business.validateLog(db,a,c); return reviews.create(a,"LOG",id,Db.version(b),db.read(l.get("body")),c,Db.required(b,"reason"));
    }
    @GetMapping("/{id}/versions") public List<Map<String,Object>> versions(HttpServletRequest r,@PathVariable String id) { business.log(Actor.current(r),id,false); return db.rows("SELECT * FROM log_versions WHERE log_id=? ORDER BY version",id); }
    @PostMapping("/{id}/read") public Map<String,Object> read(HttpServletRequest r,@PathVariable String id) { Actor a=Actor.current(r); var l=business.log(a,id,false); if(!(boolean)l.get("submitted")) throw ApiError.forbidden(); db.update("INSERT INTO log_reads(log_id,reader_id) VALUES (?,?) ON CONFLICT(log_id,reader_id) DO UPDATE SET read_at=now()",id,a.id()); return Map.of("ok",true); }
    @GetMapping("/{id}/comments") public List<Map<String,Object>> comments(HttpServletRequest r,@PathVariable String id) { business.log(Actor.current(r),id,false); return db.rows("SELECT id,actor_id,text,created_at FROM log_comments WHERE log_id=? ORDER BY created_at",id); }
    @PostMapping("/{id}/comments") @Transactional public Map<String,Object> comment(HttpServletRequest r,@PathVariable String id,@RequestBody Map<String,Object> b) { Db.fields(b,"text"); Actor a=Actor.current(r); var l=business.log(a,id,false); if(!(boolean)l.get("submitted")||!a.manager()&&!a.id().equals(l.get("owner_id"))) throw ApiError.forbidden(); String cid=Db.id(); db.update("INSERT INTO log_comments VALUES (?,?,?,?,?,now())",cid,a.company(),id,a.id(),Db.required(b,"text")); db.notify(a,Db.str(l,"owner_id"),"LOG_COMMENT",id,"comment:"+cid); return Map.of("id",cid); }
}
