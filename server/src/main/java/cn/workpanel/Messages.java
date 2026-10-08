package cn.workpanel;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;
import java.util.*;
import java.util.concurrent.*;

@Service
public class Messages {
    final Db db; final boolean enabled; final ScheduledExecutorService streams=Executors.newScheduledThreadPool(2);
    Messages(Db db,@Value("${app.jobs-enabled}") boolean enabled) { this.db=db; this.enabled=enabled; }
    @Scheduled(fixedDelay=2000) @Transactional
    public void deliver() {
        if(!enabled) return;
        for(var e:db.rows("SELECT * FROM outbox_events WHERE delivered_at IS NULL ORDER BY created_at LIMIT 100 FOR UPDATE SKIP LOCKED")) {
            db.update("INSERT INTO notifications(id,company_id,recipient_id,type,object_id,body) VALUES (?,?,?,?,?,?::jsonb) ON CONFLICT(id) DO NOTHING",e.get("id"),e.get("company_id"),e.get("recipient_id"),e.get("type"),e.get("object_id"),db.write(e.get("body")));
            db.update("UPDATE outbox_events SET delivered_at=now() WHERE id=?",e.get("id"));
        }
    }
    @Scheduled(fixedDelay=60000) @Transactional
    public void reminders() {
        if(!enabled) return;
        for(var t:db.rows("SELECT t.* FROM tasks t WHERE deadline>now() AND deadline<now()+interval '24 hours' AND phase NOT IN ('ACCEPTED','ARCHIVED','WITHDRAWN') LIMIT 1000")) {
            Actor issuer=Actor.from(db.one("SELECT * FROM users WHERE id=?",t.get("issuer_id"))); db.notify(issuer,Db.str(t,"owner_id"),"DEADLINE",Db.str(t,"id"),"deadline:"+t.get("id")+":"+t.get("deadline"));
        }
        db.update("DELETE FROM sessions WHERE expires_at<now()");
    }
    SseEmitter stream(String token,long after) {
        SseEmitter emitter=new SseEmitter(55000L); long[] sequence={after}; ScheduledFuture<?>[] future=new ScheduledFuture<?>[1];
        future[0]=streams.scheduleAtFixedRate(()->{
            try {
                Actor a=Security.authenticate(db,token); if(!a.status().equals("ACTIVE")||a.mustChange()) throw ApiError.forbidden();
                var rows=db.rows("SELECT sequence,id,type,object_id,created_at FROM notifications WHERE company_id=? AND recipient_id=? AND sequence>? ORDER BY sequence LIMIT 100",a.company(),a.id(),sequence[0]);
                for(var row:rows) { emitter.send(SseEmitter.event().id(row.get("sequence").toString()).name("notification").data(row)); sequence[0]=((Number)row.get("sequence")).longValue(); }
                if(rows.isEmpty()) emitter.send(SseEmitter.event().comment("keepalive"));
            } catch(Exception e) { emitter.complete(); }
        },0,2,TimeUnit.SECONDS);
        Runnable stop=()->future[0].cancel(false); emitter.onCompletion(stop); emitter.onTimeout(stop); emitter.onError(e->stop.run()); return emitter;
    }
    @jakarta.annotation.PreDestroy void stop() { streams.shutdownNow(); }
}

@RestController
@RequestMapping("/api/notifications")
class NotificationApi {
    final Db db; final Messages messages;
    NotificationApi(Db db,Messages messages) { this.db=db; this.messages=messages; }
    @GetMapping public Map<String,Object> list(HttpServletRequest r,@RequestParam(defaultValue="0") int cursor,@RequestParam(defaultValue="30") int limit,@RequestParam(required=false) String type) {
        Actor a=Actor.current(r); Business.page(cursor,limit); String where="company_id=? AND recipient_id=?"; var args=new ArrayList<Object>(List.of(a.company(),a.id())); if(type!=null) { where+=" AND type=?"; args.add(type); }
        long total=db.count("SELECT count(*) FROM notifications WHERE "+where,args.toArray()); args.add(limit); args.add(cursor);
        return Map.of("items",db.rows("SELECT * FROM notifications WHERE "+where+" ORDER BY sequence DESC LIMIT ? OFFSET ?",args.toArray()),"total",total,"nextCursor",String.valueOf(cursor+limit),"unread",db.count("SELECT count(*) FROM notifications WHERE company_id=? AND recipient_id=? AND NOT is_read",a.company(),a.id()));
    }
    @PostMapping("/read-all") public Map<String,Object> readAll(HttpServletRequest r) { Actor a=Actor.current(r); db.update("UPDATE notifications SET is_read=true WHERE company_id=? AND recipient_id=?",a.company(),a.id()); return Map.of("ok",true); }
    @PostMapping("/{id}/read") public Map<String,Object> read(HttpServletRequest r,@PathVariable String id) { Actor a=Actor.current(r); Db.conflict(db.update("UPDATE notifications SET is_read=true WHERE id=? AND company_id=? AND recipient_id=?",id,a.company(),a.id())); return Map.of("ok",true); }
    @GetMapping(value="/stream",produces="text/event-stream") public SseEmitter stream(HttpServletRequest r,@RequestHeader(value="Last-Event-ID",defaultValue="0") long sequence) { if(sequence<0) throw ApiError.bad("INVALID_SEQUENCE","序号不能为负"); return messages.stream(r.getHeader("Authorization"),sequence); }
}
