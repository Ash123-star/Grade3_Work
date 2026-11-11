package cn.workpanel.module.attachment.application;

import cn.workpanel.*;
import cn.workpanel.module.attachment.infrastructure.ObjectStorage;
import org.springframework.transaction.support.TransactionTemplate;
import java.util.*;

/** 管理工具专用：先记录意图，读回校验后以存储版本CAS切换；保留原bytea副本供独立核对/清除。 */
public final class AttachmentMigration {
    private final Db db;private final ObjectStorage storage;private final TransactionTemplate tx;
    public AttachmentMigration(Db db,ObjectStorage storage,TransactionTemplate tx){this.db=db;this.storage=storage;this.tx=tx;}
    public Map<String,Object> run(String mode,boolean apply){
        return run(mode,apply,null);
    }
    public Map<String,Object> run(String mode,boolean apply,String company){
        if(!Set.of("migrate","restore","purge").contains(mode))throw new IllegalArgumentException("Invalid migration mode");
        String where=mode.equals("migrate")?"storage_provider='DATABASE' AND storage_state='READY' AND octet_length(data)>0":"storage_provider='OSS' AND storage_state='READY'";
        var results=new ArrayList<Map<String,Object>>();String cursor="";
        // 批量只取ID，每次仅加载一份正文，避免50份10MB历史文件同时驻留堆内存。
        while(true){var args=new ArrayList<Object>();args.add(cursor);if(company!=null)args.add(company);var rows=db.rows("SELECT id FROM attachments WHERE "+where+" AND id>?"+(company==null?"":" AND company_id=?")+" AND (expires_at IS NULL OR expires_at>now()) ORDER BY id LIMIT 50",args.toArray());if(rows.isEmpty())break;
            for(var candidate:rows){String id=Db.str(candidate,"id");cursor=id;
                try{if(apply){var file=db.one("SELECT * FROM attachments WHERE id=? AND "+where+" AND (expires_at IS NULL OR expires_at>now())",id);if(mode.equals("migrate"))migrate(file);else reverse(file,mode.equals("purge"));}results.add(Map.of("id",id,"result",apply?"SUCCESS":"PLANNED"));}
                catch(ApiError e){results.add(Map.of("id",id,"result",e.code));}
            }
        }
        return Map.of("mode",mode,"apply",apply,"count",results.size(),"failed",results.stream().filter(r->!Set.of("SUCCESS","PLANNED").contains(r.get("result"))).count(),"items",results);
    }
    private void migrate(Map<String,Object> f){
        String id=Db.str(f,"id"),hash=AttachmentApplicationService.hash((byte[])f.get("data")),key=storage.key("business/"+f.get("company_id")+"/"+id);byte[] bytes=(byte[])f.get("data");long version=((Number)f.get("storage_version")).longValue();
        tx.executeWithoutResult(s->{db.one("SELECT id FROM attachments WHERE id=? AND storage_provider='DATABASE' AND storage_state='READY' AND storage_version=? FOR UPDATE",id,version);
            db.update("INSERT INTO attachment_migrations(attachment_id,object_key,file_hash,size_bytes,expected_version,state) VALUES (?,?,?,?,?,'PENDING') ON CONFLICT(attachment_id) DO UPDATE SET file_hash=EXCLUDED.file_hash,size_bytes=EXCLUDED.size_bytes,expected_version=EXCLUDED.expected_version,state='PENDING',updated_at=now()",id,key,hash,bytes.length,version);});
        storage.put(key,bytes,Db.str(f,"content_type"));BinaryFiles.verify(storage.get(key,BinaryFiles.MAX_BYTES),bytes.length,hash);
        tx.executeWithoutResult(s->{var current=db.one("SELECT * FROM attachments WHERE id=? FOR UPDATE",id);
            if(!"READY".equals(current.get("storage_state"))||!"DATABASE".equals(current.get("storage_provider"))||((Number)current.get("storage_version")).longValue()!=version||!hash.equals(AttachmentApplicationService.hash((byte[])current.get("data"))))throw ApiError.conflict();
            Db.conflict(db.update("UPDATE attachments SET storage_provider='OSS',object_key=?,file_hash=?,size_bytes=?,storage_version=storage_version+1,storage_updated_at=now() WHERE id=? AND storage_version=?",key,hash,bytes.length,id,version));
            db.update("UPDATE attachment_migrations SET state='READY',updated_at=now() WHERE attachment_id=?",id);});
    }
    private void reverse(Map<String,Object> f,boolean purge){
        String id=Db.str(f,"id"),hash=Db.str(f,"file_hash");byte[] bytes=storage.get(Db.str(f,"object_key"),BinaryFiles.MAX_BYTES);BinaryFiles.verify(bytes,((Number)f.get("size_bytes")).longValue(),hash);
        tx.executeWithoutResult(s->{var current=db.one("SELECT * FROM attachments WHERE id=? AND storage_state='READY' FOR UPDATE",id);
            if(!Objects.equals(current.get("storage_version"),f.get("storage_version")))throw ApiError.conflict();
            if(purge&&current.get("data") instanceof byte[] backup&&backup.length>0)BinaryFiles.verify(backup,bytes.length,hash);
            db.update("UPDATE attachments SET data=?,storage_provider=?,storage_version=storage_version+1,storage_updated_at=now() WHERE id=?",purge?null:bytes,purge?"OSS":"DATABASE",id);
        });
    }
}
