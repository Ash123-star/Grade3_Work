package cn.workpanel.module.organization;

import cn.workpanel.*;
import cn.workpanel.module.push.application.*;
import cn.workpanel.module.message.application.MessageApplicationService;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.transaction.support.TransactionTemplate;
import cn.workpanel.module.review.infrastructure.ReviewRepository;
import java.net.*;
import java.net.http.*;
import java.time.*;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;

@SpringBootTest(webEnvironment=SpringBootTest.WebEnvironment.RANDOM_PORT,properties={"app.admin-account=integration-admin","app.admin-password=Initial-test-password-2026","app.admin-phone=13900000001","app.jobs-enabled=false","app.push.enabled=true"})
class EssentialPushIntegrationTest extends MemberBHttpSupport {
 @Autowired PushService pushes;@Autowired DeadlinePushReminders reminders;@Autowired MessageApplicationService messages;
 @Autowired ReviewRepository reviews;
 @MockBean PushGateway gateway;
 @BeforeEach void provider() throws Exception {when(gateway.configured()).thenReturn(true);when(gateway.send(anyString(),anyString(),anyString(),anyString(),anyString(),any())).thenReturn("accepted");db.update("UPDATE push_deliveries SET state='CANCELLED' WHERE state='PENDING'");}
 @AfterEach void cleanup() {db.update("UPDATE outbox_events SET delivered_at=now() WHERE company_id=?",company);db.update("DELETE FROM push_devices WHERE company_id=?",company);}
 Map<String,Object> settings(int version) {return new LinkedHashMap<>(Map.of("version",version,"enabled",true,"tasks",true,"deadlines",true,"reviews",true,"quietEnabled",false,"quietStart",22,"quietEnd",8));}
 String device(String who,String device) throws Exception {
  call(200,"PUT","/push/preferences",who,settings(1));return call(200,"PUT","/push/device",who,Map.of("deviceId",device)).get("binding").asText();
 }
 String task() throws Exception {
  db.update("UPDATE users SET dispatch_enabled=true WHERE id=?",founder);
  var request=HttpRequest.newBuilder(URI.create("http://127.0.0.1:"+port+"/api/tasks")).header("Authorization","Bearer "+tokens.get(founder)).header("Content-Type","application/json").header("Idempotency-Key",Db.id()).POST(HttpRequest.BodyPublishers.ofString(JSON.writeValueAsString(Map.of("title","秘密项目正文不应推送","participants",List.of(employee,colleague),"deadline",Instant.now().plusSeconds(90000).toString(),"content","私密任务说明")))).build();
  var response=http.send(request,HttpResponse.BodyHandlers.ofString());assertEquals(200,response.statusCode(),response.body());return JSON.readTree(response.body()).get("target_id").asText();
 }
 @Test void realTaskEntryQueuesOnceAndOpensOnlyForCurrentSession() throws Exception {
  String lease=device(employee,"device-alpha-12345"),task=task();messages.deliverNow();messages.deliverNow();
  assertEquals(1,db.count("SELECT count(*) FROM push_deliveries p JOIN notifications n ON n.id=p.notification_id WHERE n.company_id=?",company));
  pushes.dispatchNow();pushes.dispatchNow();verify(gateway,times(1)).send(eq("device-alpha-12345"),anyString(),eq(lease),eq("tasks"),eq("你有一项新任务"),any());
  String notice=Db.str(db.one("SELECT n.id FROM notifications n WHERE n.company_id=? AND n.recipient_id=? AND n.type='TASK_ASSIGNED'",company,employee),"id");
  var opened=call(200,"GET","/push/open/"+notice+"?deviceId=device-alpha-12345&binding="+lease,employee,null);assertEquals(task,opened.get("objectId").asText());
  call(404,"GET","/push/open/"+notice+"?deviceId=device-alpha-12345&binding="+lease,colleague,null);
  call(404,"GET","/push/open/"+notice+"?deviceId=device-alpha-12345&binding="+lease,foreign,null);
  call(200,"POST","/auth/logout",employee,Map.of());assertEquals(0,db.count("SELECT count(*) FROM push_devices WHERE user_id=?",employee));
 }
 @Test void sessionSwitchStaleTaskAndRevokedSessionsCancelQueue() throws Exception {
  String lease=device(employee,"device-switch-12345");task();messages.deliverNow();
  device(colleague,"device-switch-12345");pushes.dispatchNow();verify(gateway,never()).send(anyString(),anyString(),anyString(),anyString(),anyString(),any());
  assertEquals("CANCELLED",db.one("SELECT p.state FROM push_deliveries p JOIN notifications n ON n.id=p.notification_id WHERE n.recipient_id=?",employee).get("state"));
  assertNotEquals(lease,db.one("SELECT binding FROM push_devices WHERE device_id='device-switch-12345'").get("binding"));
 }
 @Test void temporaryFailureRetriesAndVersionChangeSuppressesOldReminder() throws Exception {
  device(employee,"device-retry-12345");String task=task();messages.deliverNow();
  when(gateway.send(anyString(),anyString(),anyString(),anyString(),anyString(),any())).thenThrow(new PushGateway.Failure("Throttling",true));
  pushes.dispatchNow();var d=db.one("SELECT p.* FROM push_deliveries p JOIN notifications n ON n.id=p.notification_id WHERE n.recipient_id=?",employee);
  assertEquals("PENDING",d.get("state"));assertEquals(1,d.get("attempts"));
  db.update("UPDATE tasks SET version=version+1 WHERE id=?",task);db.update("UPDATE push_deliveries SET next_attempt_at=now() WHERE id=?",d.get("id"));
  pushes.dispatchNow();assertEquals("CANCELLED",db.one("SELECT state FROM push_deliveries WHERE id=?",d.get("id")).get("state"));
 }
 @Test void preferencesRejectInvalidInputAndQuietHoursDefer() throws Exception {
  var initial=call(200,"GET","/push/preferences",employee,null);assertFalse(initial.get("enabled").asBoolean());
  var bad=settings(1);bad.put("quietStart",24);call(400,"PUT","/push/preferences",employee,bad);
  call(400,"PUT","/push/device",employee,Map.of("deviceId","bad","userId",colleague));
  device(employee,"device-quiet-12345");String task=task();messages.deliverNow();
  var quiet=settings(2);int hour=ZonedDateTime.now(ZoneId.of("Asia/Shanghai")).getHour();quiet.put("quietEnabled",true);quiet.put("quietStart",hour);quiet.put("quietEnd",(hour+1)%24);call(200,"PUT","/push/preferences",employee,quiet);
  call(409,"PUT","/push/preferences",employee,settings(1));
  pushes.dispatchNow();verify(gateway,never()).send(anyString(),anyString(),anyString(),anyString(),anyString(),any());
  assertEquals(1,db.count("SELECT count(*) FROM push_deliveries p JOIN notifications n ON n.id=p.notification_id WHERE n.recipient_id=? AND p.state='PENDING' AND p.next_attempt_at>now()",employee));
 }
 @Test void reminderStagesCoverAllParticipantsAndDoNotCatchUpOrDuplicate() throws Exception {
  String task=task();Instant now=Instant.now(),deadline=now.plusSeconds(3590);
  db.update("UPDATE tasks SET deadline=?::timestamptz WHERE id=?",deadline.toString(),task);reminders.run(now);reminders.run(now);
  assertEquals(2,db.count("SELECT count(*) FROM outbox_events WHERE object_id=? AND type='DEADLINE'",task));
  reminders.run(now.plusSeconds(120));assertEquals(2,db.count("SELECT count(*) FROM outbox_events WHERE object_id=? AND type='DEADLINE'",task));
  reminders.run(deadline.minusSeconds(86390));reminders.run(deadline.minusSeconds(86390));assertEquals(4,db.count("SELECT count(*) FROM outbox_events WHERE object_id=? AND type='DEADLINE'",task));
  reminders.run(deadline.plusSeconds(10));reminders.run(deadline.plusSeconds(10));assertEquals(6,db.count("SELECT count(*) FROM outbox_events WHERE object_id=? AND type='DEADLINE'",task));
  db.update("UPDATE tasks SET phase='ACCEPTED' WHERE id=?",task);reminders.run(deadline.plusSeconds(120));assertEquals(6,db.count("SELECT count(*) FROM outbox_events WHERE object_id=? AND type='DEADLINE'",task));
 }
 @Test void pendingMembershipMayBindAndReceiveOwnResultButNotBusinessData() throws Exception {
  db.update("UPDATE users SET status='PENDING' WHERE id=?",employee);String lease=device(employee,"device-pending-12345");
  call(403,"GET","/tasks",employee,null);
  String review=Db.id();db.update("INSERT INTO review_requests(id,company_id,applicant_id,kind,target_id,expected_version,before_value,candidate,reason,status) VALUES (?,?,?,'MEMBERSHIP',?,1,'{}','{}','申请','REJECTED')",review,company,employee,employee);
  db.notify(Actor.from(db.one("SELECT * FROM users WHERE id=?",admin)),employee,"REVIEW_REJECTED",review,"membership-result-"+review);messages.deliverNow();pushes.dispatchNow();
  var n=db.one("SELECT id FROM notifications WHERE object_id=? AND recipient_id=?",review,employee);
  var opened=call(200,"GET","/push/open/"+n.get("id")+"?deviceId=device-pending-12345&binding="+lease,employee,null);assertEquals("membership",opened.get("resource").asText());
  call(403,"GET","/tasks",employee,null);
 }
 @Test void rollbackKeepsOutboxStationAndPushAtomic() throws Exception {
  device(employee,"device-rollback-12345");String task=task();
  assertThrows(IllegalStateException.class,()->new TransactionTemplate(manager).execute(status->{messages.deliverNow();throw new IllegalStateException("rollback");}));
  assertEquals(0,db.count("SELECT count(*) FROM notifications WHERE object_id=?",task));
  assertEquals(0,db.count("SELECT count(*) FROM push_deliveries p JOIN notifications n ON n.id=p.notification_id WHERE n.company_id=?",company));
  assertEquals(2,db.count("SELECT count(*) FROM outbox_events WHERE object_id=? AND type='TASK_ASSIGNED' AND delivered_at IS NULL",task));
  messages.deliverNow();assertEquals(1,db.count("SELECT count(*) FROM push_deliveries p JOIN notifications n ON n.id=p.notification_id WHERE n.company_id=?",company));
 }
 @Test void withdrawalReplacesQueuedAssignmentWithOnlyGenericActionNotice() throws Exception {
  device(employee,"device-withdraw-12345");String task=task();messages.deliverNow();
  call(200,"POST","/tasks/"+task+"/events",founder,Map.of("type","WITHDRAWN","version",1,"text","敏感撤回原因"));
  messages.deliverNow();pushes.dispatchNow();verify(gateway,times(1)).send(anyString(),anyString(),anyString(),eq("tasks"),eq("你的任务已撤回"),any());
  assertEquals(1,db.count("SELECT count(*) FROM push_deliveries p JOIN notifications n ON n.id=p.notification_id WHERE n.object_id=? AND p.state='CANCELLED'",task));
 }
 @Test void expiredOrDisabledCategoryNeverCallsProvider() throws Exception {
  device(employee,"device-expiry-12345");task();messages.deliverNow();
  db.update("UPDATE push_deliveries p SET expires_at=now()-interval '1 second' FROM notifications n WHERE n.id=p.notification_id AND n.company_id=?",company);
  pushes.dispatchNow();verify(gateway,never()).send(anyString(),anyString(),anyString(),anyString(),anyString(),any());
  task();messages.deliverNow();var settings=settings(2);settings.put("tasks",false);call(200,"PUT","/push/preferences",employee,settings);
  pushes.dispatchNow();verify(gateway,never()).send(anyString(),anyString(),anyString(),anyString(),anyString(),any());
  assertEquals(2,db.count("SELECT count(*) FROM push_deliveries p JOIN notifications n ON n.id=p.notification_id WHERE n.company_id=? AND state='CANCELLED'",company));
 }
 @Test void retriesStopAtFiveAndPermanentErrorsStopImmediately() throws Exception {
  device(employee,"device-limit-12345");task();messages.deliverNow();
  when(gateway.send(anyString(),anyString(),anyString(),anyString(),anyString(),any())).thenThrow(new PushGateway.Failure("Throttling",true));
  for(int i=0;i<6;i++) {db.update("UPDATE push_deliveries SET next_attempt_at=now() WHERE state='PENDING'");pushes.dispatchNow();}
  verify(gateway,times(5)).send(anyString(),anyString(),anyString(),anyString(),anyString(),any());
  assertEquals(1,db.count("SELECT count(*) FROM push_deliveries p JOIN notifications n ON n.id=p.notification_id WHERE n.company_id=? AND state='FAILED' AND attempts=5",company));
  task();messages.deliverNow();doThrow(new PushGateway.Failure("InvalidAppKey",false)).when(gateway).send(anyString(),anyString(),anyString(),anyString(),anyString(),any());
  pushes.dispatchNow();assertEquals(1,db.count("SELECT count(*) FROM push_deliveries p JOIN notifications n ON n.id=p.notification_id WHERE n.company_id=? AND state='FAILED' AND attempts=1",company));
 }
 @Test void replacedReviewStepCannotReuseOldPendingNotice() throws Exception {
  String lease=device(reviewer,"device-review-12345");String review=revision(employee,Map.of("name","调整后的姓名")).get("id").asText();
  messages.deliverNow();
  String oldNotice=Db.str(db.one("SELECT id FROM notifications WHERE object_id=? AND recipient_id=? AND type='REVIEW_PENDING'",review,reviewer),"id");
  new TransactionTemplate(manager).execute(status->{
   db.update("UPDATE review_steps SET state='SUPERSEDED' WHERE request_id=? AND state='PENDING'",review);
   db.update("INSERT INTO review_steps(request_id,reviewer_id,applicant_id,position,company_id) VALUES (?,?,?,2,?)",review,reviewer,admin,company);
   reviews.notify(Actor.from(db.one("SELECT * FROM users WHERE id=?",admin)),reviewer,"REVIEW_PENDING",review,"review-new-step-"+review);return null;
  });
  messages.deliverNow();pushes.dispatchNow();verify(gateway,times(1)).send(anyString(),anyString(),anyString(),eq("reviews"),anyString(),any());
  assertEquals("CANCELLED",db.one("SELECT state FROM push_deliveries WHERE notification_id=?",oldNotice).get("state"));
  String notice=Db.str(db.one("SELECT notification_id FROM push_deliveries p JOIN notifications n ON n.id=p.notification_id WHERE n.object_id=? AND p.state='ACCEPTED'",review),"notification_id");
  assertEquals("reviews",call(200,"GET","/push/open/"+notice+"?deviceId=device-review-12345&binding="+lease,reviewer,null).get("resource").asText());
  db.update("UPDATE review_requests SET status='REJECTED' WHERE id=?",review);
  call(404,"GET","/push/open/"+notice+"?deviceId=device-review-12345&binding="+lease,reviewer,null);
 }
}
