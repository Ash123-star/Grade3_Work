package cn.workpanel.module.attachment.application;

import cn.workpanel.*;
import cn.workpanel.module.attachment.infrastructure.*;
import org.springframework.stereotype.Service;
import org.springframework.transaction.*;
import org.springframework.transaction.support.TransactionTemplate;
import java.util.*;

/** 存储编排；PENDING意图独立提交，外部对象操作不包在数据库长事务内。 */
@Service
public class BinaryFiles {
    public static final long MAX_BYTES=10L*1024*1024;
    private final Db db; private final ObjectStorage storage; private final TransactionTemplate tx;
    public BinaryFiles(Db db,ObjectStorage storage,PlatformTransactionManager manager){
        this.db=db;this.storage=storage;tx=new TransactionTemplate(manager);tx.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
    }
    /** 先独立保存上传意图，再写OSS并读回校验；只有READY提交成功才返回附件ID。 */
    public Map<String,Object> save(Actor a,String name,byte[] bytes){
        if(bytes.length<1||bytes.length>MAX_BYTES)throw ApiError.bad("INVALID_FILE","文件大小应在1字节至10MB之间");
        String id=Db.id(),key=storage.key("business/"+a.company()+"/"+id),hash=AttachmentApplicationService.hash(bytes);
        tx.executeWithoutResult(s->db.update("INSERT INTO attachments(id,company_id,owner_id,filename,content_type,file_hash,storage_provider,object_key,size_bytes,storage_state) VALUES (?,?,?,?,?,?,'OSS',?,?,'PENDING')",id,a.company(),a.id(),name,"application/octet-stream",hash,key,bytes.length));
        storage.put(key,bytes,"application/octet-stream");
        verify(storage.get(key,MAX_BYTES),bytes.length,hash);
        tx.executeWithoutResult(s->Db.conflict(db.update("UPDATE attachments SET storage_state='READY',storage_updated_at=now(),storage_version=storage_version+1 WHERE id=? AND storage_state='PENDING'",id)));
        return Map.of("id",id,"filename",name,"size",bytes.length,"hash",hash);
    }
    public byte[] bytes(Map<String,Object> file){
        byte[] result;
        if("OSS".equals(file.get("storage_provider"))){
            result=storage.get(Db.str(file,"object_key"),MAX_BYTES);
            verify(result,((Number)file.get("size_bytes")).longValue(),Db.str(file,"file_hash"));
        }else{result=(byte[])file.get("data");if(result==null||result.length==0)throw ApiError.notFound();}
        return result;
    }
    public static void verify(byte[] bytes,long expected,String hash){
        if(bytes.length!=expected||!AttachmentApplicationService.hash(bytes).equals(hash))throw AliyunObjectStorage.integrity();
    }
}
