package cn.workpanel.storage;

import cn.workpanel.*;
import cn.workpanel.module.attachment.application.*;
import cn.workpanel.module.attachment.infrastructure.ObjectStorage;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import java.net.*;
import java.net.http.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.time.Duration;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;

/** 显式启用的真实供应商验收；独立数据库、随机前缀，最终删除全部测试对象。 */
@EnabledIfEnvironmentVariable(named="OSS_REAL_ACCEPTANCE", matches="true")
@SpringBootTest(webEnvironment=SpringBootTest.WebEnvironment.RANDOM_PORT,properties={
    "app.admin-account=integration-admin","app.admin-password=Initial-test-password-2026",
    "app.admin-phone=13900000001","app.jobs-enabled=false","app.memory-extract-enabled=false"})
class RealOssStorageIntegrationTest {
    static final String prefix="workpanel/verification/"+Db.id();
    @DynamicPropertySource static void storageScope(DynamicPropertyRegistry r){r.add("app.oss.prefix",()->prefix);}
    @Autowired Db db;@Autowired ObjectStorage storage;@Autowired GeneratedFiles generated;
    @Autowired StorageCleanup cleanup;@Autowired PlatformTransactionManager manager;
    @LocalServerPort int port;
    final ObjectMapper json=new ObjectMapper();
    final HttpClient http=HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).build();
    final Set<String> objects=new LinkedHashSet<>();
    @AfterEach void deleteObjects(){for(String key:objects)storage.delete(key);}
    HttpResponse<byte[]> request(String method,String path,String token,byte[] bytes,String type)throws Exception{
        var b=HttpRequest.newBuilder(URI.create("http://127.0.0.1:"+port+"/api"+path)).timeout(Duration.ofSeconds(30));
        if(token!=null)b.header("Authorization","Bearer "+token);if(type!=null)b.header("Content-Type",type);
        return http.send(b.method(method,bytes==null?HttpRequest.BodyPublishers.noBody():HttpRequest.BodyPublishers.ofByteArray(bytes)).build(),HttpResponse.BodyHandlers.ofByteArray());
    }
    @Test void businessUploadGeneratedMigrationAndDeletionUseRealObjects()throws Exception{
        String company=Db.id(),id=Db.id();db.update("INSERT INTO companies(id,name) VALUES (?,?)",company,"OSS isolated acceptance");
        db.update("INSERT INTO users(id,company_id,account,password_hash,phone,name,role,status) VALUES (?,?,?,'x',?,?,'EMPLOYEE','ACTIVE')",id,company,id,id,"OSS acceptance");
        db.update("INSERT INTO sessions(token_hash,user_id,expires_at) VALUES (?,?,now()+interval '1 hour')",Db.hash(id),id);
        Actor owner=new Actor(id,company,"EMPLOYEE","","",false,false,false,"ACTIVE");
        try{
            byte[] body=("--proof\r\nContent-Disposition: form-data; name=\"file\"; filename=\"proof.txt\"\r\nContent-Type: text/plain\r\n\r\nOSS acceptance\r\n--proof--\r\n").getBytes(StandardCharsets.UTF_8);
            var upload=request("POST","/attachments",id,body,"multipart/form-data; boundary=proof");assertEquals(200,upload.statusCode());
            String file=json.readTree(upload.body()).path("id").asText();var row=db.one("SELECT * FROM attachments WHERE id=?",file);
            objects.add(Db.str(row,"object_key"));assertNull(row.get("data"));assertEquals("OSS",row.get("storage_provider"));
            assertArrayEquals("OSS acceptance".getBytes(StandardCharsets.UTF_8),request("GET","/attachments/"+file,id,null,null).body());
            assertEquals(401,request("GET","/attachments/"+file,null,null,null).statusCode());
            var result=generated.create(owner,"EXPORT","proof.csv","a,b".getBytes(StandardCharsets.UTF_8),List.of());
            objects.add(Db.str(db.one("SELECT object_key FROM attachments WHERE id=?",result.id()),"object_key"));
            assertArrayEquals(result.bytes(),request("GET","/generated-files/"+result.id(),id,null,null).body());
            String legacy=Db.id();byte[] original="historical-proof".getBytes(StandardCharsets.UTF_8);
            db.update("INSERT INTO attachments(id,company_id,owner_id,filename,content_type,data) VALUES (?,?,?,'legacy.txt','text/plain',?)",legacy,company,id,original);
            objects.add(storage.key("business/"+company+"/"+legacy));var migration=new AttachmentMigration(db,storage,new TransactionTemplate(manager));
            assertEquals(0L,migration.run("migrate",true,company).get("failed"));assertEquals(0,migration.run("migrate",true,company).get("count"));
            assertArrayEquals(original,request("GET","/attachments/"+legacy,id,null,null).body());
            migration.run("purge",true,company);assertNull(db.one("SELECT data FROM attachments WHERE id=?",legacy).get("data"));
            migration.run("restore",true,company);assertArrayEquals(original,(byte[])db.one("SELECT data FROM attachments WHERE id=?",legacy).get("data"));
            cleanup.queue("f.company_id='"+company+"' AND f.storage_provider='OSS' AND f.storage_state='READY'");cleanup.drain();
            assertEquals(0,db.count("SELECT count(*) FROM attachments WHERE company_id=? AND storage_provider='OSS' AND storage_state<>'DELETED'",company));
            for(var deleted:db.rows("SELECT object_key FROM attachments WHERE company_id=? AND storage_state='DELETED'",company))assertEquals(404,assertThrows(ApiError.class,()->storage.get(Db.str(deleted,"object_key"),1024)).status);
        }finally{for(var row:db.rows("SELECT object_key FROM attachments WHERE company_id=? AND object_key IS NOT NULL",company))objects.add(Db.str(row,"object_key"));}
    }
    @Test void fullRepositoryPublicationAndPublicGatewayReadRealOss()throws Exception{
        Path root=Path.of("..").toRealPath();String release="acceptance-"+Db.id();
        var manifest=AssetPublisher.inventory(root,release);var items=AssetCatalog.items(manifest);
        for(String required:List.of("fonts/FontManifest.json","fonts/MaterialIcons-Regular.otf","fonts/DEPENDENCY-NOTICES.txt","packages/cute_ui/assets/openmoji/1F31F.svg"))assertTrue(items.stream().anyMatch(i->required.equals(i.get("path"))),required);
        for(var item:items)objects.add(storage.key("static/"+release+"/"+item.get("hash")+"/"+item.get("path")));
        long started=System.nanoTime();new AssetPublisher(db,storage,new TransactionTemplate(manager)).publish(root,manifest);
        var current=request("GET","/assets/manifest",null,null,null);assertEquals(200,current.statusCode());assertEquals(items.size(),json.readTree(current.body()).path("items").size());
        for(String mime:List.of("image/png","image/svg+xml","font/ttf","text/plain;charset=UTF-8")){
            var item=items.stream().filter(i->mime.equals(i.get("mime"))).findFirst().orElseThrow();
            var response=request("GET","/assets/"+release+"/"+item.get("path"),null,null,null);assertEquals(200,response.statusCode());
            BinaryFiles.verify(response.body(),((Number)item.get("size")).longValue(),Db.str(item,"hash"));
            assertTrue(response.headers().firstValue("cache-control").orElse("").contains("immutable"));
        }
        assertEquals(404,request("GET","/assets/"+release+"/business/private",null,null,null).statusCode());
        Path report=root.resolve("output/oss/real-publication.json");Files.createDirectories(report.getParent());
        Files.writeString(report,json.writerWithDefaultPrettyPrinter().writeValueAsString(Map.of("count",items.size(),"bytes",manifest.get("bytes"),"elapsedMs",(System.nanoTime()-started)/1_000_000,"manifest",manifest,"scope","isolated acceptance; test objects removed after test; not production activation")));
    }
}
