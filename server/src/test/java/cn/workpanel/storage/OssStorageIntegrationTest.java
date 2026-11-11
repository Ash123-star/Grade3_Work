package cn.workpanel.storage;

import cn.workpanel.*;
import cn.workpanel.module.attachment.application.*;
import cn.workpanel.shared.application.CurrentActors;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.context.annotation.Import;
import org.springframework.test.annotation.DirtiesContext;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.net.*;
import java.net.http.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;

/** 真实HTTP、PostgreSQL和鉴权；只有对象供应商被显式替换，真实OSS另由probe验收。 */
@SpringBootTest(webEnvironment=SpringBootTest.WebEnvironment.RANDOM_PORT,properties={"app.admin-account=integration-admin","app.admin-password=Initial-test-password-2026","app.admin-phone=13900000001","app.jobs-enabled=false","app.memory-extract-enabled=false"})
@Import(StorageTestConfiguration.class)
@DirtiesContext(classMode=DirtiesContext.ClassMode.AFTER_CLASS)
class OssStorageIntegrationTest {
    @LocalServerPort int port;
    @Autowired Db db;@Autowired BinaryFiles files;@Autowired GeneratedFiles generated;@Autowired StorageCleanup cleanup;
    @Autowired CurrentActors actors;@Autowired PlatformTransactionManager manager;
    @Autowired StorageTestConfiguration.MemoryStorage storage;
    final HttpClient http=HttpClient.newHttpClient();final ObjectMapper json=new ObjectMapper();
    String company;Actor owner,other,pending,foreign;
    @BeforeEach void setup(){company=Db.id();db.update("INSERT INTO companies(id,name) VALUES (?,?)",company,"OSS integration");owner=user(company,"ACTIVE");other=user(company,"ACTIVE");pending=user(company,"PENDING");String c=Db.id();db.update("INSERT INTO companies(id,name) VALUES (?,?)",c,"foreign");foreign=user(c,"ACTIVE");storage.failPut.set(false);storage.failDelete.set(false);}
    Actor user(String company,String status){String id=Db.id();String phone=String.valueOf(13000000000L+Math.abs((long)id.hashCode())%900000000L);db.update("INSERT INTO users(id,company_id,account,password_hash,phone,name,role,status) VALUES (?,?,?,'test',?,?,'EMPLOYEE',?)",id,company,id,phone,"OSS test",status);db.update("INSERT INTO sessions(token_hash,user_id,expires_at) VALUES (?,?,now()+interval '1 hour')",Db.hash(id),id);return new Actor(id,company,"EMPLOYEE","","",false,false,false,status);}
    HttpResponse<byte[]> request(String method,String path,Actor actor,byte[] body,String type)throws Exception{
        var builder=HttpRequest.newBuilder(URI.create("http://127.0.0.1:"+port+"/api"+path));if(actor!=null)builder.header("Authorization","Bearer "+actor.id());if(type!=null)builder.header("Content-Type",type);
        return http.send(builder.method(method,body==null?HttpRequest.BodyPublishers.noBody():HttpRequest.BodyPublishers.ofByteArray(body)).build(),HttpResponse.BodyHandlers.ofByteArray());
    }
    String upload()throws Exception{String content="--oss-test\r\nContent-Disposition: form-data; name=\"file\"; filename=\"proof.txt\"\r\nContent-Type: text/plain\r\n\r\nprivate proof\r\n--oss-test--\r\n";var response=request("POST","/attachments",owner,content.getBytes(StandardCharsets.UTF_8),"multipart/form-data; boundary=oss-test");assertEquals(200,response.statusCode(),new String(response.body(),StandardCharsets.UTF_8));return json.readTree(response.body()).get("id").asText();}
    @Test void uploadUsesObjectsAndRejectsUnauthorizedBeforeStorageRead()throws Exception{
        String id=upload();var row=db.one("SELECT * FROM attachments WHERE id=?",id);assertEquals("OSS",row.get("storage_provider"));assertNull(row.get("data"));assertEquals("READY",row.get("storage_state"));
        assertArrayEquals("private proof".getBytes(StandardCharsets.UTF_8),request("GET","/attachments/"+id,owner,null,null).body());
        int before=storage.reads.get();assertEquals(403,request("GET","/attachments/"+id,other,null,null).statusCode());assertEquals(404,request("GET","/attachments/"+id,foreign,null,null).statusCode());assertEquals(403,request("GET","/attachments/"+id,pending,null,null).statusCode());assertEquals(before,storage.reads.get());
        storage.objects.put(Db.str(row,"object_key"),"tampered".getBytes(StandardCharsets.UTF_8));assertEquals(502,request("GET","/attachments/"+id,owner,null,null).statusCode());
    }
    @Test void failedUploadHasDurableIntentAndDeletionRetries()throws Exception{
        storage.failPut.set(true);assertEquals("STORAGE_UNAVAILABLE",assertThrows(ApiError.class,()->files.save(owner,"a.txt",new byte[]{1})).code);storage.failPut.set(false);
        var row=db.one("SELECT * FROM attachments WHERE company_id=? AND storage_state='PENDING'",company);assertEquals(0,db.count("SELECT count(*) FROM attachment_bindings WHERE attachment_id=?",row.get("id")));
        cleanup.queue("f.company_id='"+company+"' AND f.storage_state='PENDING'");storage.failDelete.set(true);cleanup.drain();assertEquals(1,db.count("SELECT count(*) FROM storage_delete_jobs WHERE attachment_id=?",row.get("id")));
        storage.failDelete.set(false);db.update("UPDATE storage_delete_jobs SET available_at=now() WHERE attachment_id=?",row.get("id"));cleanup.drain();assertEquals("DELETED",db.one("SELECT storage_state FROM attachments WHERE id=?",row.get("id")).get("storage_state"));
    }
    @Test void generatedFileRevalidatesSourcesThroughBothDownloadRoutes()throws Exception{
        String log=Db.id();db.update("INSERT INTO daily_logs(id,company_id,owner_id,business_date,body,submitted,submitted_at) VALUES (?,?,?,current_date,'{}',true,now())",log,company,owner.id());
        var result=generated.create(owner,"EXPORT","export.csv","safe,csv".getBytes(StandardCharsets.UTF_8),List.of(Map.of("type","LOG","id",log,"version",1)));
        assertEquals(200,request("GET","/generated-files/"+result.id(),owner,null,null).statusCode());assertEquals(404,request("GET","/generated-files/"+result.id(),other,null,null).statusCode());
        assertThrows(ApiError.class,()->cn.workpanel.module.task.TaskAttachments.verify(db,owner,null,List.of(result.id())));
        db.update("UPDATE daily_logs SET version=version+1 WHERE id=?",log);assertEquals(409,request("GET","/generated-files/"+result.id(),owner,null,null).statusCode());assertEquals(409,request("GET","/attachments/"+result.id(),owner,null,null).statusCode());
    }
    @Test void interruptedMigrationResumesAndKeepsIdsAndBackup()throws Exception{
        String id=Db.id();byte[] bytes="legacy attachment".getBytes(StandardCharsets.UTF_8);db.update("INSERT INTO attachments(id,company_id,owner_id,filename,content_type,data) VALUES (?,?,?,'legacy.txt','text/plain',?)",id,company,owner.id(),bytes);
        var migration=new AttachmentMigration(db,storage,new TransactionTemplate(manager));storage.failPut.set(true);assertEquals(1L,migration.run("migrate",true,company).get("failed"));assertEquals("DATABASE",db.one("SELECT storage_provider FROM attachments WHERE id=?",id).get("storage_provider"));
        storage.failPut.set(false);assertEquals(0L,migration.run("migrate",true,company).get("failed"));assertEquals(0,migration.run("migrate",true,company).get("count"));assertArrayEquals(bytes,request("GET","/attachments/"+id,owner,null,null).body());
        migration.run("purge",true,company);assertNull(db.one("SELECT data FROM attachments WHERE id=?",id).get("data"));migration.run("restore",true,company);assertArrayEquals(bytes,(byte[])db.one("SELECT data FROM attachments WHERE id=?",id).get("data"));
    }
    @Test void runtimeContractIncludesPublicAssetsAndProtectedGeneratedFiles()throws Exception{
        var response=request("GET","/openapi",null,null,null);assertEquals(200,response.statusCode());var document=json.readTree(response.body());
        assertTrue(document.path("paths").has("/api/generated-files/{id}"));assertTrue(document.path("paths").has("/api/assets/manifest"));assertTrue(document.at("/paths/~1api~1assets~1manifest/get/security").isArray());
        Path output=Path.of("target/openapi-oss.json");Files.createDirectories(output.getParent());Files.write(output,response.body());
    }
    @Test void publicAssetsAreWhitelistedAndPublicationIsAtomic()throws Exception{
        Path root=Files.createTempDirectory("oss-assets-");try{Files.createDirectories(root.resolve("mobile/assets/licenses"));Files.writeString(root.resolve("mobile/assets/licenses/NOTICE.txt"),"attribution");String release="test-"+Db.id();var manifest=AssetPublisher.inventory(root,release);var publisher=new AssetPublisher(db,storage,new TransactionTemplate(manager));
            var previous=db.one("SELECT * FROM asset_current WHERE id=1");storage.failPut.set(true);assertThrows(ApiError.class,()->publisher.publish(root,manifest));assertEquals(previous,db.one("SELECT * FROM asset_current WHERE id=1"));storage.failPut.set(false);publisher.publish(root,manifest);
            var response=request("GET","/assets/"+release+"/assets/licenses/NOTICE.txt",null,null,null);assertEquals(200,response.statusCode());assertEquals("attribution",new String(response.body(),StandardCharsets.UTF_8));assertEquals(404,request("GET","/assets/"+release+"/business/private",null,null,null).statusCode());assertEquals(404,request("GET","/assets/unknown/assets/licenses/NOTICE.txt",null,null,null).statusCode());assertEquals(200,request("GET","/assets/manifest",null,null,null).statusCode());
        }finally{try(var walk=Files.walk(root)){for(Path path:walk.sorted(Comparator.reverseOrder()).toList())Files.delete(path);}}
    }
}
