package cn.workpanel.storage;

import cn.workpanel.ApiError;
import cn.workpanel.module.attachment.infrastructure.ObjectStorage;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;

/** 测试显式注入对象端口替身，生产没有本地文件或数据库回退。 */
@TestConfiguration
public class StorageTestConfiguration {
    @Bean @Primary public MemoryStorage testObjectStorage(){return new MemoryStorage();}
    public static class MemoryStorage implements ObjectStorage {
        public final ConcurrentHashMap<String,byte[]> objects=new ConcurrentHashMap<>();
        public final AtomicBoolean failPut=new AtomicBoolean(),failDelete=new AtomicBoolean();
        public final AtomicInteger reads=new AtomicInteger();
        public String key(String relative){return "workpanel/"+relative;}
        public void put(String key,byte[] bytes,String type){if(failPut.get())throw new ApiError(503,"STORAGE_UNAVAILABLE","test unavailable");objects.put(key,bytes.clone());}
        public byte[] get(String key,long max){reads.incrementAndGet();byte[] bytes=objects.get(key);if(bytes==null)throw new ApiError(404,"FILE_NOT_FOUND","test missing");if(bytes.length>max)throw new ApiError(502,"FILE_INTEGRITY_ERROR","test oversized");return bytes.clone();}
        public void delete(String key){if(failDelete.get())throw new ApiError(503,"STORAGE_UNAVAILABLE","test unavailable");objects.remove(key);}
    }
}
