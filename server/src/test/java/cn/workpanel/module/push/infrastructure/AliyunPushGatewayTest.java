package cn.workpanel.module.push.infrastructure;
import cn.workpanel.module.push.application.PushGateway;
import com.aliyuncs.push.model.v20160801.PushRequest;
import com.aliyuncs.http.ProtocolType;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.sun.net.httpserver.HttpServer;
import org.junit.jupiter.api.Test;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.concurrent.atomic.AtomicReference;
import static org.junit.jupiter.api.Assertions.*;
class AliyunPushGatewayTest {
 @Test void realOfficialSdkSignsHttpAndOnlySendsGenericContent() throws Exception {
  var captured=new AtomicReference<String>();var server=HttpServer.create(new InetSocketAddress("127.0.0.1",0),0);
  server.createContext("/",e->{ captured.set(e.getRequestURI().toString()+new String(e.getRequestBody().readAllBytes(),StandardCharsets.UTF_8));byte[] body="{\"RequestId\":\"r\",\"MessageId\":\"accepted-1\"}".getBytes(StandardCharsets.UTF_8);e.getResponseHeaders().set("Content-Type","application/json");e.sendResponseHeaders(200,body.length);e.getResponseBody().write(body);e.close();});server.start();
  var gateway=new AliyunPushGateway(new ObjectMapper(),123L,"test-access","test-secret","","NORMAL","WORK","mi-channel","WORK","vivo-channel","honor-channel") {
   @Override public PushRequest request(String d,String n,String b,String c,String t,Instant x) throws Exception {
    var r=super.request(d,n,b,c,t,x);r.setSysProductDomain(new com.aliyuncs.regions.ProductDomain("Push","127.0.0.1:"+server.getAddress().getPort()));r.setSysProtocol(ProtocolType.HTTP);return r;
   }
  };
  try {
   assertEquals("accepted-1",gateway.send("device-abcdefgh","notice-1","lease-1","tasks","你有一项新任务",Instant.now().plusSeconds(3600)));
   String wire=URLDecoder.decode(captured.get(),StandardCharsets.UTF_8);
   assertTrue(wire.contains("Signature="));assertTrue(wire.contains("Target=DEVICE"));assertTrue(wire.contains("pandora_tasks"));assertTrue(wire.contains("notificationId"));
   assertTrue(wire.contains("AndroidMessageOppoCategory=WORK"));assertTrue(wire.contains("AndroidNotificationHonorChannel=honor-channel"));
   assertTrue(wire.contains("AndroidMessageHuaweiCategory=WORK"));assertTrue(wire.contains("AndroidNotificationHuaweiChannel=NORMAL"));
   assertTrue(wire.contains("AndroidRemind=true"));assertTrue(wire.contains("AndroidPopupActivity=cn.pandora.pandora_mobile.PushPopupActivity"));
   assertFalse(wire.contains("test-secret"));assertFalse(wire.contains("AccessKeySecret"));assertFalse(wire.contains("objectId"));
  } finally {gateway.close();server.stop(0);}
 }
 @Test void missingCredentialsNeverReportsAccepted() throws Exception {
  var gateway=new AliyunPushGateway(new ObjectMapper(),0L,"","","","NORMAL","WORK","","","","");assertFalse(gateway.configured());
  var error=assertThrows(PushGateway.Failure.class,()->gateway.send("device","n","b","tasks","提示",Instant.now()));assertEquals("NOT_CONFIGURED",error.code);assertFalse(error.retryable);
 }
 @Test void huaweiCategoryAndImportanceAreIndependentAndOptional() throws Exception {
  var categoryOnly=new AliyunPushGateway(new ObjectMapper(),0L,"","","","","WORK","","","","");
  var r=categoryOnly.request("device","n","b","reviews","你有一项申请待审批",Instant.now().plusSeconds(60));
  assertEquals("WORK",r.getAndroidMessageHuaweiCategory());assertNull(r.getAndroidNotificationHuaweiChannel());
  var importanceOnly=new AliyunPushGateway(new ObjectMapper(),0L,"","","","NORMAL","","","","","");
  r=importanceOnly.request("device","n","b","deadlines","你有一项任务即将截止",Instant.now().plusSeconds(60));
  assertNull(r.getAndroidMessageHuaweiCategory());assertEquals("NORMAL",r.getAndroidNotificationHuaweiChannel());
 }
}
