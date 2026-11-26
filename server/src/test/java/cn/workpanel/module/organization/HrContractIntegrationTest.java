package cn.workpanel.module.organization;
import cn.workpanel.*;import cn.workpanel.module.organization.application.ContractReminders;import org.springframework.beans.factory.annotation.Autowired;import org.springframework.boot.test.context.SpringBootTest;import org.junit.jupiter.api.Test;import java.time.*;import java.util.*;import static org.junit.jupiter.api.Assertions.*;
@SpringBootTest(webEnvironment=SpringBootTest.WebEnvironment.RANDOM_PORT,properties={"app.admin-account=integration-admin","app.admin-password=Initial-test-password-2026","app.admin-phone=13900000001"})
class HrContractIntegrationTest extends MemberBHttpSupport {
 @Autowired ContractReminders reminders;
 @Autowired cn.workpanel.module.message.application.MessageApplicationService messages;
 @org.junit.jupiter.api.AfterEach void closeEvents(){db.update("UPDATE outbox_events SET delivered_at=now() WHERE company_id=?",company);}

 String attachment(String owner){String id=Db.id();db.update("INSERT INTO attachments(id,company_id,owner_id,filename,content_type,data,file_hash) VALUES (?,?,?,'contract.pdf','application/pdf',?,'test')",id,company,owner,new byte[]{1,2,3});return id;}
 Map<String,Object> command(String file){return new LinkedHashMap<>(Map.of("employeeId",employee,"title","劳动合同","startsOn",LocalDate.now().minusDays(1).toString(),"endsOn",LocalDate.now(ZoneId.of("Asia/Shanghai")).plusDays(30).toString(),"attachmentId",file,"recipients",List.of(admin),"version",0));}
 @Test void archivePermissionsAndVersion() throws Exception {call(403,"GET","/hr/contracts",employee,null);call(403,"GET","/hr/contracts",founder,null);String file=attachment(admin);var b=command(file);var c=call(200,"POST","/hr/contracts",admin,b);String id=c.get("id").asText();call(403,"GET","/hr/contracts/"+id,foreign,null);call(200,"PUT","/hr/grants/"+employee,admin,Map.of("access","READ","version",0));call(200,"GET","/hr/contracts/"+id,employee,null);call(403,"POST","/hr/contracts",employee,b);b.put("version",1);call(200,"PUT","/hr/contracts/"+id,admin,b);call(409,"PUT","/hr/contracts/"+id,admin,b);call(200,"PUT","/hr/grants/"+employee,admin,Map.of("access","NONE","version",1));call(403,"GET","/hr/contracts/"+id,employee,null);call(403,"GET","/attachments/"+file,employee,null);}
 @Test void remindersAreScopedAndDeduplicated() throws Exception {var b=command(attachment(admin));String id=call(200,"POST","/hr/contracts",admin,b).get("id").asText();LocalDate today=LocalDate.now(ZoneId.of("Asia/Shanghai"));assertEquals(1,reminders.scan(today,company));assertEquals(0,reminders.scan(today,company));assertEquals(1,db.count("SELECT count(*) FROM outbox_events WHERE object_id=? AND type='CONTRACT_EXPIRY'",id));assertEquals(0,reminders.scan(today,"missing"));}
 @Test void invalidDataRollsBack() throws Exception {var b=command(attachment(admin));b.put("endsOn","2020-01-01");call(400,"POST","/hr/contracts",admin,b);b.put("endsOn",LocalDate.now().plusDays(30).toString());b.put("recipients",List.of(employee));call(400,"POST","/hr/contracts",admin,b);assertEquals(0,db.count("SELECT count(*) FROM employee_contracts WHERE company_id=?",company));call(403,"PUT","/hr/grants/"+employee,founder,Map.of("access","MANAGE","version",0));}

 @Test void uploaderLosesAccessAndCannotReuseContract() throws Exception {
  call(200,"PUT","/hr/grants/"+employee,admin,Map.of("access","MANAGE","version",0));String file=attachment(employee);var b=command(file);b.put("recipients",List.of(employee));String id=call(200,"POST","/hr/contracts",employee,b).get("id").asText();
  call(404,"PUT","/profiles/me",employee,Map.of("version",1,"avatarAttachmentId",file));
  call(200,"PUT","/hr/grants/"+employee,admin,Map.of("access","NONE","version",1));
  call(403,"GET","/attachments/"+file,employee,null);assertEquals(0,reminders.scan(LocalDate.now(ZoneId.of("Asia/Shanghai")),company));assertEquals(0,db.count("SELECT count(*) FROM outbox_events WHERE object_id=?",id));
 }
 @Test void grantAndDutiesRejectStaleVersion() throws Exception {
  call(200,"PUT","/hr/employees/"+employee+"/duties",admin,Map.of("duties","负责客户服务","version",0));call(409,"PUT","/hr/employees/"+employee+"/duties",admin,Map.of("duties","旧版本覆盖","version",0));
  call(200,"PUT","/hr/grants/"+employee,admin,Map.of("access","READ","version",0));call(409,"PUT","/hr/grants/"+employee,admin,Map.of("access","MANAGE","version",0));
  call(403,"PUT","/hr/employees/"+employee+"/duties",employee,Map.of("duties","越权","version",1));
  var people=call(200,"GET","/hr/employees",employee,null);assertFalse(people.toString().contains("password_hash"));assertFalse(people.toString().contains("id_card_number"));
 }

 @Test void concurrentReminderScansWriteOnce() throws Exception {
  String id=call(200,"POST","/hr/contracts",admin,command(attachment(admin))).get("id").asText();
  try(var pool=java.util.concurrent.Executors.newFixedThreadPool(2)){
   var jobs=pool.invokeAll(List.of(()->reminders.scan(LocalDate.now(ZoneId.of("Asia/Shanghai")),company),()->reminders.scan(LocalDate.now(ZoneId.of("Asia/Shanghai")),company)));
   for(var job:jobs)job.get();
  }
  assertEquals(1,db.count("SELECT count(*) FROM outbox_events WHERE object_id=? AND type='CONTRACT_EXPIRY'",id));
 }
 @Test void pendingAndDisabledRecipientCannotReceive() throws Exception {
  call(200,"PUT","/hr/grants/"+employee,admin,Map.of("access","READ","version",0));var b=command(attachment(admin));b.put("recipients",List.of(employee));call(200,"POST","/hr/contracts",admin,b);
  db.update("UPDATE users SET status='DISABLED' WHERE id=?",employee);assertEquals(0,reminders.scan(LocalDate.now(ZoneId.of("Asia/Shanghai")),company));call(401,"GET","/hr/me",employee,null);
 }

 @Test void historyAndCrossCompanyScope() throws Exception {
  var b=command(attachment(admin));String id=call(200,"POST","/hr/contracts",admin,b).get("id").asText();b.put("version",1);b.put("title","续期日期更正");call(200,"PUT","/hr/contracts/"+id,admin,b);
  var history=call(200,"GET","/hr/contracts/"+id+"/history",admin,null);assertEquals(2,history.size());assertEquals("劳动合同",history.get(1).get("snapshot").get("title").asText());
  var f=db.one("SELECT company_id,department_id FROM users WHERE id=?",foreign);String otherAdmin=user(Db.str(f,"company_id"),Db.str(f,"department_id"),"","ADMIN",true);
  call(404,"GET","/hr/contracts/"+id,otherAdmin,null);call(404,"GET","/hr/contracts/"+id+"/history",otherAdmin,null);call(404,"GET","/attachments/"+b.get("attachmentId"),otherAdmin,null);
  assertEquals(3,call(200,"GET","/hr/employees?cursor=0&limit=3",admin,null).size());call(400,"GET","/hr/employees?cursor=-1",admin,null);
 }
 @Test void deliveryAndRevocationAreAtomic() throws Exception {
  call(200,"PUT","/hr/grants/"+employee,admin,Map.of("access","READ","version",0));var b=command(attachment(admin));b.put("recipients",List.of(employee));String id=call(200,"POST","/hr/contracts",admin,b).get("id").asText();reminders.scan(LocalDate.now(ZoneId.of("Asia/Shanghai")),company);
  try(var pool=java.util.concurrent.Executors.newFixedThreadPool(2)) {
   var delivery=pool.submit(()->{messages.deliverNow();return true;});
   var revoke=pool.submit(()->call(200,"PUT","/hr/grants/"+employee,admin,Map.of("access","NONE","version",1)));
   delivery.get(30,java.util.concurrent.TimeUnit.SECONDS);revoke.get(30,java.util.concurrent.TimeUnit.SECONDS);
  }
  assertEquals(0,db.count("SELECT count(*) FROM notifications WHERE object_id=?",id));call(403,"GET","/hr/reminders",employee,null);
 }
 @Test void removedRecipientDoesNotReceiveQueuedNotification() throws Exception {
  var b=command(attachment(admin));b.put("recipients",List.of(admin));String id=call(200,"POST","/hr/contracts",admin,b).get("id").asText();reminders.scan(LocalDate.now(ZoneId.of("Asia/Shanghai")),company);b.put("version",1);b.put("recipients",List.of(reviewer));call(200,"PUT","/hr/contracts/"+id,admin,b);messages.deliverNow();assertEquals(0,db.count("SELECT count(*) FROM notifications WHERE object_id=? AND recipient_id=?",id,admin));
 }
 @Test void archiveAndAvatarCannotShareAttachmentConcurrently() throws Exception {
  call(200,"PUT","/hr/grants/"+employee,admin,Map.of("access","MANAGE","version",0));String file=attachment(employee);var b=command(file);
  try(var pool=java.util.concurrent.Executors.newFixedThreadPool(2)) {
   var archive=pool.submit(()->rawStatus("POST","/hr/contracts",employee,b));
   var avatar=pool.submit(()->rawStatus("PUT","/profiles/me",employee,Map.of("version",1,"avatarAttachmentId",file)));
   int ar=archive.get(30,java.util.concurrent.TimeUnit.SECONDS), av=avatar.get(30,java.util.concurrent.TimeUnit.SECONDS);
   assertTrue(ar==200&&av==404 || ar==400&&av==200,"archive="+ar+", avatar="+av);
  }
  assertFalse(db.count("SELECT count(*) FROM employee_contracts c JOIN users u ON u.profile->>'avatarAttachmentId'=c.attachment_id WHERE c.attachment_id=?",file)>0);
 }
 int rawStatus(String method,String path,String who,Object body) throws Exception {
  return http.send(java.net.http.HttpRequest.newBuilder(java.net.URI.create("http://127.0.0.1:"+port+"/api"+path)).header("Authorization","Bearer "+tokens.get(who)).header("Content-Type","application/json").method(method,java.net.http.HttpRequest.BodyPublishers.ofString(JSON.writeValueAsString(body))).build(),java.net.http.HttpResponse.BodyHandlers.ofString()).statusCode();
 }

 @Test void allReminderNodesAndNoOtherDays() throws Exception {
  for(int days:new int[]{30,7,0,1,31}) {
   var b=command(attachment(admin));b.put("endsOn",LocalDate.now(ZoneId.of("Asia/Shanghai")).plusDays(days).toString());String id=call(200,"POST","/hr/contracts",admin,b).get("id").asText();
   reminders.scan(LocalDate.now(ZoneId.of("Asia/Shanghai")),company);assertEquals(Set.of(30,7,0).contains(days)?1:0,db.count("SELECT count(*) FROM outbox_events WHERE object_id=?",id));
  }
  var b=command(attachment(admin));b.put("startsOn","0000-01-01");call(400,"POST","/hr/contracts",admin,b);
 }
}
