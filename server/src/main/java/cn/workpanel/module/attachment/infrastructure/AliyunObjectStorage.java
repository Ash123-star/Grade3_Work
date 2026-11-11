package cn.workpanel.module.attachment.infrastructure;

import cn.workpanel.ApiError;
import com.aliyun.oss.*;
import com.aliyun.oss.common.auth.*;
import com.aliyun.oss.model.ObjectMetadata;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.stereotype.Component;
import jakarta.annotation.PreDestroy;
import java.io.*;

/** 官方SDK、服务端凭据、有限重试；SDK异常文本不进入API或普通日志。 */
@Component
@EnableConfigurationProperties(OssSettings.class)
public class AliyunObjectStorage implements ObjectStorage, AutoCloseable {
    private final OssSettings settings;
    private volatile OSS client;
    public AliyunObjectStorage(OssSettings settings){this.settings=settings;}
    private synchronized OSS client(){
        if(client!=null)return client;
        try {
            CredentialsProvider credentials;
            if(settings.roleName()!=null&&!settings.roleName().isBlank())
                credentials=CredentialsProviderFactory.newInstanceProfileCredentialsProvider(settings.roleName());
            else {
                if(settings.accessKeyId()==null||settings.accessKeyId().isBlank()||settings.accessKeySecret()==null||settings.accessKeySecret().isBlank())throw unavailable();
                credentials=new DefaultCredentialProvider(settings.accessKeyId(),settings.accessKeySecret(),settings.securityToken());
            }
            var config=new ClientBuilderConfiguration();config.setConnectionTimeout(5000);config.setSocketTimeout(15000);
            config.setMaxErrorRetry(2);config.setMaxConnections(16);
            client=new OSSClientBuilder().build(settings.endpoint(),credentials,config);
            return client;
        }catch(ApiError e){throw e;}catch(Exception e){throw unavailable();}
    }
    @Override public String key(String relative){
        if(relative==null||relative.isBlank()||relative.startsWith("/")||relative.contains("\\")||relative.contains("%")||java.util.Arrays.stream(relative.split("/",-1)).anyMatch(p->p.isBlank()||p.equals(".")||p.equals("..")))throw new IllegalArgumentException("Invalid object path");
        return settings.prefix()+"/"+relative;
    }
    private void check(String key){if(key==null||!key.startsWith(settings.prefix()+"/")||!key.equals(key(key.substring(settings.prefix().length()+1))))throw new IllegalArgumentException("Object outside configured prefix");}
    @Override public void put(String key,byte[] bytes,String type){
        check(key);var metadata=new ObjectMetadata();metadata.setContentLength(bytes.length);metadata.setContentType(type);
        metadata.setHeader("x-oss-object-acl","private");
        try{client().putObject(settings.bucket(),key,new ByteArrayInputStream(bytes),metadata);}catch(ApiError e){throw e;}catch(Exception e){throw unavailable();}
    }
    @Override public byte[] get(String key,long maximumBytes){
        check(key);if(maximumBytes<1||maximumBytes>100L*1024*1024)throw new IllegalArgumentException("Invalid read limit");
        try(var object=client().getObject(settings.bucket(),key);var input=object.getObjectContent()){
            if(object.getObjectMetadata().getContentLength()>maximumBytes)throw integrity();
            byte[] bytes=input.readNBytes(Math.toIntExact(maximumBytes+1));if(bytes.length>maximumBytes)throw integrity();return bytes;
        }catch(OSSException e){if("NoSuchKey".equals(e.getErrorCode()))throw new ApiError(404,"FILE_NOT_FOUND","文件不存在或已清理");throw unavailable();}
        catch(ApiError e){throw e;}catch(Exception e){throw unavailable();}
    }
    @Override public void delete(String key){check(key);try{client().deleteObject(settings.bucket(),key);}catch(Exception e){throw unavailable();}}
    public static ApiError unavailable(){return new ApiError(503,"STORAGE_UNAVAILABLE","文件存储暂不可用，请稍后重试");}
    public static ApiError integrity(){return new ApiError(502,"FILE_INTEGRITY_ERROR","文件校验失败，请重新上传或联系管理员");}
    @Override @PreDestroy public void close(){if(client!=null)client.shutdown();}
}
