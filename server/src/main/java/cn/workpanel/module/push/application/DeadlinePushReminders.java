package cn.workpanel.module.push.application;
import cn.workpanel.*;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.time.*;
import java.sql.Timestamp;
import java.util.*;
/** One-minute windows skip missed stages; dedup contains deadline and actual recipient. */
@Service public class DeadlinePushReminders {
 final Db db;final boolean jobs;
 public DeadlinePushReminders(Db db,@Value("${app.jobs-enabled}") boolean jobs) {this.db=db;this.jobs=jobs;}
 @Scheduled(fixedDelay=60000) @Transactional public void tick() {if(jobs) run(Instant.now());}
 @Transactional public void run(Instant now) {
  for(String stage:List.of("DAY","HOUR","OVERDUE")) {
   Instant end=now.plusSeconds(stage.equals("DAY")?86400:stage.equals("HOUR")?3600:0),start=end.minusSeconds(60);
   for(var t:db.rows("SELECT t.* FROM tasks t WHERE t.phase IN ('DISPATCHED','RECEIVED') AND t.deadline>? AND t.deadline<=? ORDER BY t.deadline LIMIT 1000",Timestamp.from(start),Timestamp.from(end))) {
    Instant deadline=PushService.instant(t.get("deadline"));Instant expires=stage.equals("DAY")?deadline.minusSeconds(3600):stage.equals("HOUR")?deadline:deadline.plusSeconds(86400);
    for(var p:db.rows("SELECT p.user_id FROM task_participants p JOIN users u ON u.id=p.user_id AND u.company_id=p.company_id WHERE p.task_id=? AND u.status='ACTIVE'",t.get("id"))) {
     String key="deadline:"+t.get("id")+":"+deadline+":"+stage+":"+p.get("user_id");
     db.update("INSERT INTO outbox_events(id,company_id,recipient_id,type,object_id,body,dedup_key) VALUES (?,?,?,'DEADLINE',?,?::jsonb,?) ON CONFLICT(dedup_key) DO NOTHING",Db.id(),t.get("company_id"),p.get("user_id"),t.get("id"),db.write(Map.of("stage",stage,"deadline",deadline.toString(),"expiresAt",expires.toString(),"taskVersion",t.get("version"))),key);
    }
   }
  }
 }
}
