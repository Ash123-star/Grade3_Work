package cn.workpanel.module.push.infrastructure;

import cn.workpanel.*;
import cn.workpanel.module.review.infrastructure.ReviewRepository;
import cn.workpanel.module.task.TaskAccess;
import org.springframework.stereotype.Repository;
import java.util.*;

@Repository
public class PushRepository {
    private final Db db;
    public PushRepository(Db db) { this.db=db; }
    public Map<String,Object> body(Object value) { return db.read(value); }
    public Map<String,Object> preferences(Actor a,boolean lock) {
        db.update("INSERT INTO push_preferences(user_id,company_id) VALUES (?,?) ON CONFLICT DO NOTHING",a.id(),a.company());
        return db.one("SELECT * FROM push_preferences WHERE user_id=? AND company_id=?"+(lock?" FOR UPDATE":""),a.id(),a.company());
    }
    public Map<String,Object> task(Actor a,String id) { return TaskAccess.readable(db,a,id,false); }
    public Map<String,Object> review(Actor a,String id) {
        var scope=ReviewRepository.readableScope(a);var args=new ArrayList<>(scope.args());args.add(id);
        return db.one("SELECT r.* FROM review_requests r WHERE "+scope.sql()+" AND r.id=?",args.toArray());
    }
    public Map<String,Object> recipient(Map<String,Object> event) {
        return db.one("SELECT * FROM users WHERE company_id=? AND id=? AND status<>'DISABLED'",event.get("company_id"),event.get("recipient_id"));
    }
    public List<Map<String,Object>> activeDevices(Actor a) {
        return db.rows("SELECT d.* FROM push_devices d JOIN sessions s ON s.token_hash=d.session_hash WHERE d.company_id=? AND d.user_id=? AND s.user_id=d.user_id AND s.expires_at>now() AND d.updated_at>now()-interval '30 days'",a.company(),a.id());
    }

    public Map<String,Object> bind(Actor a,String hash,String device) {
        db.update("INSERT INTO push_devices(id,device_id,company_id,user_id,session_hash,binding) VALUES (?,?,?,?,?,?) ON CONFLICT(device_id) DO UPDATE SET company_id=excluded.company_id,user_id=excluded.user_id,session_hash=excluded.session_hash,binding=CASE WHEN push_devices.user_id=excluded.user_id AND push_devices.session_hash=excluded.session_hash THEN push_devices.binding ELSE excluded.binding END,updated_at=now()",Db.id(),device,a.company(),a.id(),hash,Db.id());
        return db.one("SELECT id,binding FROM push_devices WHERE device_id=?",device);
    }
    public void unbind(Actor a,String hash,String device) { db.update("DELETE FROM push_devices WHERE device_id=? AND user_id=? AND company_id=? AND session_hash=?",device,a.id(),a.company(),hash); }
    public void preferences(Actor a,Map<String,Object> b,int version) {
        Db.conflict(db.update("UPDATE push_preferences SET enabled=?,tasks=?,deadlines=?,reviews=?,quiet_enabled=?,quiet_start=?,quiet_end=?,version=version+1 WHERE company_id=? AND user_id=? AND version=?",b.get("enabled"),b.get("tasks"),b.get("deadlines"),b.get("reviews"),b.get("quietEnabled"),b.get("quietStart"),b.get("quietEnd"),a.company(),a.id(),version));
    }
    public void enqueue(Map<String,Object> event,Map<String,Object> device,String category,Integer version,java.time.Instant expires) {
        db.update("INSERT INTO push_deliveries(id,notification_id,device_id,binding,category,task_version,expires_at) VALUES (?,?,?,?,?,?,?) ON CONFLICT DO NOTHING",Db.id(),event.get("id"),device.get("id"),device.get("binding"),category,version,java.sql.Timestamp.from(expires));
    }
    public List<Map<String,Object>> pending() {
        return db.rows("SELECT p.*,n.company_id,n.recipient_id,n.type,n.object_id,n.body,n.created_at AS event_created,d.device_id AS cloud_device,d.binding AS current_binding,d.user_id AS device_user,d.session_hash FROM push_deliveries p JOIN notifications n ON n.id=p.notification_id JOIN push_devices d ON d.id=p.device_id WHERE p.state='PENDING' AND p.next_attempt_at<=now() ORDER BY p.next_attempt_at LIMIT 20 FOR UPDATE OF p,d SKIP LOCKED");
    }
    public boolean sessionValid(Map<String,Object> d) {
        return Objects.equals(d.get("binding"),d.get("current_binding"))&&Objects.equals(d.get("device_user"),d.get("recipient_id"))&&db.count("SELECT count(*) FROM sessions s JOIN push_devices d ON d.session_hash=s.token_hash WHERE d.id=? AND d.binding=? AND d.user_id=? AND d.company_id=? AND d.updated_at>now()-interval '30 days' AND s.user_id=d.user_id AND s.expires_at>now()",d.get("device_id"),d.get("binding"),d.get("recipient_id"),d.get("company_id"))==1;
    }
    public void outcome(String id,String state,int attempts,String provider,String error,java.time.Instant next) {
        db.update("UPDATE push_deliveries SET state=?,attempts=?,provider_id=?,error_code=?,next_attempt_at=?,updated_at=now() WHERE id=?",state,attempts,provider,error,java.sql.Timestamp.from(next),id);
    }
    public Map<String,Object> opened(Actor a,String hash,String id,String device,String binding) {
        return db.one("SELECT n.*,p.task_version,p.expires_at FROM notifications n JOIN push_deliveries p ON p.notification_id=n.id JOIN push_devices d ON d.id=p.device_id WHERE n.id=? AND n.company_id=? AND n.recipient_id=? AND d.device_id=? AND d.binding=? AND p.binding=d.binding AND d.session_hash=? AND d.user_id=? AND p.state='ACCEPTED'",id,a.company(),a.id(),device,binding,hash,a.id());
    }
    public boolean participant(String task,String user) { return db.count("SELECT count(*) FROM task_participants WHERE task_id=? AND user_id=?",task,user)>0; }
    public boolean pendingReviewer(String request,String user,Object step) { return step!=null&&db.count("SELECT count(*) FROM review_steps WHERE request_id=? AND reviewer_id=? AND id=? AND state='PENDING' AND position=(SELECT min(position) FROM review_steps WHERE request_id=? AND state='PENDING')",request,user,step,request)>0; }
    public void cleanup() {
        db.update("DELETE FROM push_deliveries WHERE created_at<now()-interval '30 days' AND state<>'PENDING'");
        db.update("DELETE FROM push_devices WHERE updated_at<now()-interval '30 days'");
    }
}
