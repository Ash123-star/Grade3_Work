package cn.workpanel.module.attachment.application;

import cn.workpanel.*;
import cn.workpanel.module.attachment.infrastructure.ObjectStorage;
import org.springframework.stereotype.Service;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import java.util.*;

/** 先锁定并拒绝绑定，再提交删除意图；网络删除在事务外，失败保留退避重试。 */
@Service
public class StorageCleanup {
    private final Db db;private final ObjectStorage storage;private final TransactionTemplate tx;private final boolean enabled;
    private static final String UNREFERENCED=" f.task_id IS NULL AND NOT EXISTS(SELECT 1 FROM attachment_bindings b WHERE b.company_id=f.company_id AND b.attachment_id=f.id AND b.resource_type IN ('PROCEDURE','DELIVERY')) AND NOT EXISTS(SELECT 1 FROM users u WHERE u.company_id=f.company_id AND u.profile->>'avatarAttachmentId'=f.id) ";
    public StorageCleanup(Db db,ObjectStorage storage,PlatformTransactionManager manager,@Value("${app.jobs-enabled:true}")boolean enabled){this.db=db;this.storage=storage;this.tx=new TransactionTemplate(manager);this.enabled=enabled;}
    public void expirePrivateWork(){
        queue("f.storage_state='READY' AND "+UNREFERENCED+" AND EXISTS(SELECT 1 FROM attachment_bindings b JOIN ai_work_items w ON w.company_id=b.company_id AND w.id=b.resource_id WHERE b.attachment_id=f.id AND b.company_id=f.company_id AND b.resource_type='WORK' AND (w.deleted_at IS NOT NULL OR w.state IN ('SUCCEEDED','CANCELLED') AND w.updated_at<now()-interval '30 days')) AND NOT EXISTS(SELECT 1 FROM attachment_bindings b JOIN ai_work_items w ON w.company_id=b.company_id AND w.id=b.resource_id WHERE b.attachment_id=f.id AND b.company_id=f.company_id AND b.resource_type='WORK' AND w.deleted_at IS NULL AND (w.state NOT IN ('SUCCEEDED','CANCELLED') OR w.updated_at>=now()-interval '30 days'))");
    }
    public void queue(String predicate){
        tx.executeWithoutResult(s->{for(var f:db.rows("SELECT f.* FROM attachments f WHERE "+predicate+" ORDER BY f.id LIMIT 100 FOR UPDATE SKIP LOCKED")){
            String id=Db.str(f,"id");
            // 锁后重新验证引用，所有绑定写入同样锁附件行。
            if(db.count("SELECT count(*) FROM attachments f WHERE f.id=? AND "+predicate,id)==0)continue;
            if("OSS".equals(f.get("storage_provider"))){
                db.update("UPDATE attachments SET storage_state='DELETING',expires_at=now(),storage_version=storage_version+1 WHERE id=?",id);
                db.update("INSERT INTO storage_delete_jobs(object_key,attachment_id) VALUES (?,?) ON CONFLICT DO NOTHING",f.get("object_key"),id);
            }else db.update("UPDATE attachments SET storage_state='DELETED',data=''::bytea,expires_at=now(),storage_version=storage_version+1 WHERE id=?",id);
            db.update("DELETE FROM ai_file_extractions WHERE attachment_id=?",id);
        }});
    }
    @Scheduled(fixedDelay=60000,initialDelay=60000) public void tick(){if(!enabled)return;expirePrivateWork();
        queue("f.storage_state='PENDING' AND f.storage_updated_at<now()-interval '1 hour'");
        queue("f.storage_state='READY' AND "+UNREFERENCED+" AND (f.expires_at<=now() OR f.storage_provider='OSS' AND f.storage_updated_at<now()-interval '1 day' AND NOT EXISTS(SELECT 1 FROM attachment_bindings b WHERE b.attachment_id=f.id))");
        drain();
    }
    public void drain(){
        for(int i=0;i<100;i++){
            var jobs=tx.execute(s->db.rows("WITH pick AS (SELECT object_key FROM storage_delete_jobs WHERE available_at<=now() ORDER BY created_at FOR UPDATE SKIP LOCKED LIMIT 1) UPDATE storage_delete_jobs j SET available_at=now()+interval '2 minutes',attempts=attempts+1 FROM pick WHERE j.object_key=pick.object_key RETURNING j.*"));
            if(jobs==null||jobs.isEmpty())break;var job=jobs.getFirst();String key=Db.str(job,"object_key");
            try{storage.delete(key);tx.executeWithoutResult(s->{db.update("UPDATE attachments SET storage_state='DELETED',data=''::bytea,storage_version=storage_version+1 WHERE id=? AND storage_state='DELETING'",job.get("attachment_id"));db.update("DELETE FROM storage_delete_jobs WHERE object_key=?",key);});}
            catch(ApiError e){/* 持久化重试；不输出SDK请求、私有Key或凭据。 */}
        }
    }
}
