package cn.workpanel.module.message.application;

import cn.workpanel.*;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;
import java.util.*;
import java.util.concurrent.*;
import java.security.MessageDigest;
import java.nio.charset.StandardCharsets;
import org.springframework.http.ResponseEntity;

@Service
public class MessageApplicationService {
    final cn.workpanel.module.push.application.PushService pushes; final Db db; final boolean enabled; final ScheduledExecutorService streams=Executors.newScheduledThreadPool(2);
    public MessageApplicationService(Db db,@Value("${app.jobs-enabled}") boolean enabled,cn.workpanel.module.push.application.PushService pushes) { this.db=db; this.enabled=enabled; this.pushes=pushes; }
    @Scheduled(fixedDelay=2000) @Transactional
    public void deliver() {
        if(enabled) deliverNow();
    }
    /** Explicit transactional delivery entry for operations and integration verification; no HTTP endpoint. */
    @Transactional public void deliverNow() {
        for(var e:db.rows("SELECT * FROM outbox_events WHERE delivered_at IS NULL AND type<>'MEMORY_SOURCE' ORDER BY created_at LIMIT 100 FOR UPDATE SKIP LOCKED")) {
            db.update("INSERT INTO notifications(id,company_id,recipient_id,type,object_id,body) VALUES (?,?,?,?,?,?::jsonb) ON CONFLICT(id) DO NOTHING",e.get("id"),e.get("company_id"),e.get("recipient_id"),e.get("type"),e.get("object_id"),db.write(e.get("body")));
            pushes.enqueue(e);
            db.update("UPDATE outbox_events SET delivered_at=now() WHERE id=?",e.get("id"));
        }
    }
    @Scheduled(fixedDelay=60000) @Transactional
    public void reminders() {
        if(!enabled) return;
        // Deadline stages are handled by DeadlinePushReminders for all real participants.
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
        Runnable stop=()->future[0].cancel(false); emitter.onCompletion(stop);
        emitter.onTimeout(()->{ stop.run(); emitter.complete(); });
        emitter.onError(e->stop.run()); return emitter;
    }
    @jakarta.annotation.PreDestroy void stop() { streams.shutdownNow(); }
}

@RestController
@RequestMapping("/api/notifications")
/** 通知查询、已读和 SSE 接口；写入由事务 outbox 负责，客户端只消费消息。 */
class NotificationController {
    final NotificationQueryService queries; final MessageApplicationService messages; final Db db;
    NotificationController(NotificationQueryService queries,MessageApplicationService messages,Db db) { this.queries=queries; this.messages=messages; this.db=db; }
    /** 本人通知分页；可选type/category/search/unreadOnly，摘要执行当前对象授权，未读数为全量；非法400、鉴权401/403、限流429；只读无需版本或幂等键。 */
    @GetMapping public ResponseEntity<?> list(HttpServletRequest r,@RequestParam(defaultValue="0") int cursor,@RequestParam(defaultValue="30") int limit,@RequestParam(required=false) String type,@RequestParam(required=false) String category,@RequestParam(required=false) String search,@RequestParam(defaultValue="false") boolean unreadOnly) {
        // Always authorize and render current summaries before checking a private validator.
        var actor=Actor.current(r);
        var result=queries.list(actor,cursor,limit,type,category,search,unreadOnly);
        String etag;
        try { etag="W/\""+HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest((actor.company()+":"+actor.id()+":"+db.write(result)).getBytes(StandardCharsets.UTF_8)))+"\""; }
        catch(java.security.NoSuchAlgorithmException e) { throw new IllegalStateException(e); }
        var response=ResponseEntity.status(org.springframework.http.HttpStatus.OK).eTag(etag).header("Cache-Control","private, no-cache").header("Vary","Authorization");
        String validator=r.getHeader("If-None-Match");
        if(validator!=null&&Arrays.stream(validator.split(",")).map(String::trim).anyMatch(v->v.equals("*")||v.replaceFirst("^W/", "").equals(etag.replaceFirst("^W/", "")))) {
            return ResponseEntity.status(304).eTag(etag).header("Cache-Control","private, no-cache").header("Vary","Authorization").build();
        }
        return response.body(result);
    }
    /** 将本人全部通知标记为已读；幂等，无版本字段；鉴权401/403、限流429。 */
    @PostMapping("/read-all") public Map<String,Object> readAll(HttpServletRequest r) { return queries.readAll(Actor.current(r)); }
    /** 标记本人单条通知；幂等，范围外或不存在409，无版本字段；鉴权401/403、限流429。 */
    @PostMapping("/{id}/read") public Map<String,Object> read(HttpServletRequest r,@PathVariable String id) { return queries.read(Actor.current(r),id); }
    /** 建立通知 SSE 流。Last-Event-ID 用于断线重放；会话撤销或序号非法时终止/返回 400。 */
    @GetMapping(value="/stream",produces="text/event-stream") public SseEmitter stream(HttpServletRequest r,@RequestHeader(value="Last-Event-ID",defaultValue="0") long sequence) { if(sequence<0) throw ApiError.bad("INVALID_SEQUENCE","序号不能为负"); return messages.stream(r.getHeader("Authorization"),sequence); }
}

