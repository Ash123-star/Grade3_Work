package cn.workpanel.module.push.application;

import cn.workpanel.*;
import cn.workpanel.module.push.domain.PushRules;
import cn.workpanel.module.push.infrastructure.PushRepository;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.time.*;
import java.sql.Timestamp;
import java.util.*;

@Service
public class PushService {
    final PushRepository repository; final PushGateway gateway; final boolean enabled,jobs;
    public PushService(PushRepository repository,PushGateway gateway,@Value("${app.push.enabled:false}") boolean enabled,@Value("${app.jobs-enabled}") boolean jobs) {
        this.repository=repository;this.gateway=gateway;this.enabled=enabled;this.jobs=jobs;
    }
    public boolean configured() { return enabled&&gateway.configured(); }
    static String hash(String authorization) { return Db.hash(authorization.substring(7)); }
    static String device(Map<String,Object> body) {
        Db.fields(body,"deviceId");String device=Db.required(body,"deviceId");
        if(!device.matches("[A-Za-z0-9_-]{8,200}")) throw ApiError.bad("INVALID_DEVICE","设备标识无效");return device;
    }
    @Transactional public Map<String,Object> bind(Actor a,String authorization,Map<String,Object> body) {
        String device=device(body); if(!configured()) throw new ApiError(409,"PUSH_UNAVAILABLE","移动推送尚未配置");
        var row=repository.bind(a,hash(authorization),device);return Map.of("binding",row.get("binding"));
    }
    @Transactional public Map<String,Object> unbind(Actor a,String authorization,Map<String,Object> body) {
        repository.unbind(a,hash(authorization),device(body));return Map.of("ok",true);
    }
    @Transactional public Map<String,Object> preferences(Actor a) { return view(repository.preferences(a,false)); }
    Map<String,Object> view(Map<String,Object> p) {
        return Map.of("configured",configured(),"enabled",p.get("enabled"),"tasks",p.get("tasks"),"deadlines",p.get("deadlines"),"reviews",p.get("reviews"),"quietEnabled",p.get("quiet_enabled"),"quietStart",p.get("quiet_start"),"quietEnd",p.get("quiet_end"),"version",p.get("version"));
    }
    @Transactional public Map<String,Object> preferences(Actor a,Map<String,Object> body) {
        Db.fields(body,"enabled","tasks","deadlines","reviews","quietEnabled","quietStart","quietEnd","version");
        for(String key:List.of("enabled","tasks","deadlines","reviews","quietEnabled")) if(!(body.get(key) instanceof Boolean)) throw ApiError.bad("INVALID_FIELD",key+" 必须为布尔值");
        int start=hour(body.get("quietStart")),end=hour(body.get("quietEnd"));if(start==end) throw ApiError.bad("INVALID_QUIET_HOURS","免打扰起止时间不能相同");
        if(Boolean.TRUE.equals(body.get("enabled"))&&!configured()) throw new ApiError(409,"PUSH_UNAVAILABLE","移动推送尚未配置");
        repository.preferences(a,true);repository.preferences(a,body,Db.version(body));return preferences(a);
    }
    static int hour(Object v) {
        if(!(v instanceof Number n)||n.doubleValue()!=n.intValue()||n.intValue()<0||n.intValue()>23) throw ApiError.bad("INVALID_QUIET_HOURS","免打扰时间须为0至23时");return n.intValue();
    }
    record Context(Actor actor,PushRules.Notice notice,Map<String,Object> task,Map<String,Object> review) {}
    Context context(Map<String,Object> event) {
        Actor a=Actor.from(repository.recipient(event));
        if(a.mustChange()) throw ApiError.forbidden();
        String type=Db.str(event,"type"),object=Db.str(event,"object_id");
        var body=repository.body(event.get("body"));Map<String,Object> review=Map.of(),task=Map.of();
        if(type.startsWith("REVIEW_")) review=repository.review(a,object);
        boolean membership="MEMBERSHIP".equals(review.get("kind"));
        var notice=PushRules.notice(type,body,membership);if(notice==null) return null;
        if(!a.status().equals("ACTIVE")&&!(membership&&a.id().equals(review.get("applicant_id"))&&Set.of("REVIEW_APPROVED","REVIEW_REJECTED").contains(type))) throw ApiError.forbidden();
        if(type.startsWith("REVIEW_")) {
            if(type.equals("REVIEW_PENDING")&&(!"PENDING".equals(review.get("status"))||!repository.pendingReviewer(object,a.id(),body.get("reviewStepId")))) throw ApiError.notFound();
            if(!type.equals("REVIEW_PENDING")&&(!a.id().equals(review.get("applicant_id"))||!type.substring(7).equals(review.get("status")))) throw ApiError.notFound();
        } else {
            task=repository.task(a,object);
            String phase=Db.str(task,"phase");boolean withdrawn="WITHDRAWN".equals(body.get("action"));
            if(Set.of("ACCEPTED","ARCHIVED","WITHDRAWN").contains(phase)&&!(withdrawn&&phase.equals("WITHDRAWN"))) throw ApiError.notFound();
            if(type.equals("TASK_ASSIGNED")&&!phase.equals("DISPATCHED")) throw ApiError.notFound();
            if(type.equals("DEADLINE")&&(!Set.of("DISPATCHED","RECEIVED").contains(phase)||!Objects.equals(Db.str(body,"deadline"),instant(task.get("deadline")).toString()))) throw ApiError.notFound();
            if((type.equals("TASK_EVENT")||type.equals("DEADLINE"))&&!repository.participant(object,a.id())) throw ApiError.notFound();
            if(body.get("taskVersion") instanceof Number version&&version.intValue()!=((Number)task.get("version")).intValue()) throw ApiError.notFound();
            if(a.id().equals(body.get("actorId"))) return null;
        }
        return new Context(a,notice,task,review);
    }
    /** Called inside outbox transaction after station notification insertion. */
    @Transactional public void enqueue(Map<String,Object> event) {
        if(!configured()) return;
        try {
            var c=context(event);if(c==null) return;
            var p=repository.preferences(c.actor(),false);
            if(!Boolean.TRUE.equals(p.get("enabled"))||!Boolean.TRUE.equals(p.get(c.notice().category()))) return;
            Instant created=instant(event.get("created_at"));if(created==null) created=Instant.now();
            Instant expires=created.plus(Duration.ofDays(2));
            var body=repository.body(event.get("body"));
            if(event.get("type").equals("DEADLINE")) expires=Instant.parse(Db.required(body,"expiresAt"));
            if(!expires.isAfter(Instant.now())) return;
            Integer version=c.task().isEmpty()?null:((Number)c.task().get("version")).intValue();
            for(var d:repository.activeDevices(c.actor())) repository.enqueue(event,d,c.notice().category(),version,expires);
        } catch(ApiError ignored) { /* no currently authorized recipient/object */ }
    }
    @Scheduled(fixedDelay=5000,scheduler="pushDeliveryScheduler") @Transactional public void dispatch() { if(jobs) dispatchNow(); }
    @Transactional public void dispatchNow() {
        if(!configured()) return;
        for(var d:repository.pending()) {
            Instant now=Instant.now();int attempts=((Number)d.get("attempts")).intValue();String id=Db.str(d,"id");
            try {
                if(!repository.sessionValid(d)||!instant(d.get("expires_at")).isAfter(now)) throw ApiError.notFound();
                var c=context(d);if(c==null) throw ApiError.notFound();
                if(d.get("task_version")!=null&&!Objects.equals(d.get("task_version"),c.task().get("version"))) throw ApiError.notFound();
                var p=repository.preferences(c.actor(),false);
                if(!Boolean.TRUE.equals(p.get("enabled"))||!Boolean.TRUE.equals(p.get(c.notice().category()))) throw ApiError.notFound();
                Instant next=PushRules.quietUntil(now,(boolean)p.get("quiet_enabled"),((Number)p.get("quiet_start")).intValue(),((Number)p.get("quiet_end")).intValue());
                if(next.isAfter(now)) {
                    repository.outcome(id,next.isBefore(instant(d.get("expires_at")))?"PENDING":"CANCELLED",attempts,null,null,next);continue;
                }
                String accepted=gateway.send(Db.str(d,"cloud_device"),Db.str(d,"notification_id"),Db.str(d,"binding"),c.notice().category(),c.notice().title(),instant(d.get("expires_at")));
                repository.outcome(id,"ACCEPTED",attempts+1,accepted,null,now);
            } catch(ApiError ignored) { repository.outcome(id,"CANCELLED",attempts,null,"STALE",now); }
            catch(PushGateway.Failure failure) {
                attempts++;Instant next=now.plus(PushRules.backoff(attempts));
                boolean retry=failure.retryable&&attempts<5&&next.isBefore(instant(d.get("expires_at")));
                repository.outcome(id,retry?"PENDING":"FAILED",attempts,null,failure.code,next);
            }
        }
    }
    @Scheduled(fixedDelay=86400000) @Transactional public void cleanup() { if(jobs) repository.cleanup(); }
    @Transactional(readOnly=true) public Map<String,Object> open(Actor a,String authorization,String id,String device,String binding) {
        var e=repository.opened(a,hash(authorization),id,device,binding);
        if(!instant(e.get("expires_at")).isAfter(Instant.now())) throw ApiError.notFound();
        var c=context(e);if(c==null||e.get("task_version")!=null&&!Objects.equals(e.get("task_version"),c.task().get("version"))) throw ApiError.notFound();
        return Map.of("resource",c.task().isEmpty()?("MEMBERSHIP".equals(c.review().get("kind"))?"membership":"reviews"):"tasks","objectId",e.get("object_id"));
    }
    public static Instant instant(Object value) {
        if(value==null) return null;
        if(value instanceof Timestamp t) return t.toInstant();
        if(value instanceof OffsetDateTime t) return t.toInstant();
        return Instant.parse(value.toString());
    }
}
