package cn.workpanel.module.aiwork.application;

import cn.workpanel.*;
import cn.workpanel.shared.application.CommandKeys;
import org.springframework.stereotype.Component;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;
import java.util.concurrent.ConcurrentHashMap;
import java.util.*;

/** 只发送持久序号/版本，正文由同一快照的 GET 恢复；每批重新鉴权，失权立即停流。 */
@Component
public class WorkEvents {
    private final Db db;private final WorkService service;
    private final Map<String,Subscription> subscriptions=new ConcurrentHashMap<>();
    private static final class Subscription {
        final Actor actor;final String id,token;final SseEmitter emitter;
        long cursor;String fingerprint;
        Subscription(Actor actor,String id,String token,SseEmitter emitter,long cursor,String fingerprint){this.actor=actor;this.id=id;this.token=token;this.emitter=emitter;this.cursor=cursor;this.fingerprint=fingerprint;}
    }
    public WorkEvents(Db db,WorkService service){this.db=db;this.service=service;}
    public synchronized SseEmitter open(Actor actor,String id,String cursor,String token){
        var snapshot=service.get(actor,id);long sequence;
        try{if(!cursor.matches("[0-9]{1,19}"))throw new NumberFormatException();sequence=Long.parseLong(cursor);if(sequence>((Number)snapshot.get("eventsCursor")).longValue())throw new NumberFormatException();}
        catch(NumberFormatException e){throw ApiError.bad("INVALID_CURSOR","无效的事件序号，请刷新后重试");}
        if(subscriptions.values().stream().filter(s->s.actor.company().equals(actor.company())&&s.actor.id().equals(actor.id())).count()>=3)throw new ApiError(429,"STREAM_LIMIT","打开的页面过多，请关闭后重试");
        String key=Db.id();var emitter=new SseEmitter(55000L);var sub=new Subscription(actor,id,token,emitter,sequence,fingerprint(snapshot));
        subscriptions.put(key,sub);Runnable remove=()->subscriptions.remove(key,sub);
        emitter.onCompletion(remove);emitter.onTimeout(remove);emitter.onError(e->remove.run());
        try{emitter.send(SseEmitter.event().comment("connected"));}catch(Exception e){remove.run();complete(emitter);}
        return emitter;
    }
    @Scheduled(fixedDelay=1500)public void dispatch(){subscriptions.forEach((key,sub)->{try{
        Actor authenticated=Security.authenticate(db,sub.token);var snapshot=service.get(authenticated,sub.id);
        var events=db.rows("SELECT sequence,version FROM ai_work_events WHERE company_id=? AND work_id=? AND sequence>? AND sequence<=? ORDER BY sequence LIMIT 100",authenticated.company(),sub.id,sub.cursor,snapshot.get("eventsCursor"));
        for(var event:events){
            sub.emitter.send(SseEmitter.event().id(event.get("sequence").toString()).name("change").data(Map.of("version",event.get("version"))));sub.cursor=((Number)event.get("sequence")).longValue();
        }
        String next=fingerprint(snapshot);
        // 来源/目标范围变化不一定修改事项版本，仍须使两端旧正文失效。
        if(!next.equals(sub.fingerprint))sub.emitter.send(SseEmitter.event().name("refresh").data(Map.of("version",snapshot.get("version"))));
        sub.fingerprint=next;sub.emitter.send(SseEmitter.event().comment("keepalive"));
    }catch(ApiError e){
        subscriptions.remove(key,sub);
        try{if(Set.of(401,403,404).contains(e.status))sub.emitter.send(SseEmitter.event().name("access-lost").data(Map.of("status",e.status)));}catch(Exception ignored){}
        complete(sub.emitter);
    }catch(Exception e){subscriptions.remove(key,sub);complete(sub.emitter);}});}
    private static void complete(SseEmitter emitter){try{emitter.complete();}catch(IllegalStateException ignored){/* 容器可能已在断线回调中释放异步请求；订阅已移除，不再次分派。 */}}
    private String fingerprint(Map<String,Object> snapshot){return Db.hash(db.write(CommandKeys.canonical(snapshot)));}
}
