package cn.workpanel.module.task.infrastructure;

import cn.workpanel.*;
import org.springframework.stereotype.Repository;
import java.util.*;

/** 专用命令存储；不持有审核行锁，避免 review → task 锁序环路。 */
@Repository
public class TaskMovementRepository {
    private final Db db;
    public TaskMovementRepository(Db db){this.db=db;}
    public void lockKey(Actor a,String key){db.one("SELECT pg_advisory_xact_lock(hashtextextended(?,0))","task-move:"+a.company()+":"+a.id()+":"+key);}
    public List<Map<String,Object>> find(Actor a,String key){return db.rows("SELECT * FROM task_reschedule_commands WHERE company_id=? AND actor_id=? AND idempotency_key=?",a.company(),a.id(),key);}
    public boolean pending(Actor a,String task,int version){return db.count("SELECT count(*) FROM review_requests WHERE company_id=? AND target_id=? AND expected_version=? AND kind='TASK_RESCHEDULE' AND status='PENDING' AND candidate->>'scheduleMode'='MOVE'",a.company(),task,version)>0;}
    public void save(Actor a,String key,String task,String review,String hash){db.update("INSERT INTO task_reschedule_commands(company_id,actor_id,idempotency_key,task_id,review_id,request_hash,hash_version) VALUES (?,?,?,?,?,?,1)",a.company(),a.id(),key,task,review,hash);}
}
