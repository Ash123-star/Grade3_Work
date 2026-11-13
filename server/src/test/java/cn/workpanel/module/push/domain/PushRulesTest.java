package cn.workpanel.module.push.domain;
import org.junit.jupiter.api.Test;
import java.time.*;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
class PushRulesTest {
 @Test void onlyNecessaryEventsAndMembershipApproval() {
  for(String ignored:List.of("LOG_SUBMITTED","LOG_COMMENT","TASK_COMMENT","AI_READY","REVIEW_APPROVED")) assertNull(PushRules.notice(ignored,Map.of(),false));
  for(String action:List.of("RECEIVED","FEEDBACK","ACCEPTED","ARCHIVED")) assertNull(PushRules.notice("TASK_EVENT",Map.of("action",action),false));
  assertNotNull(PushRules.notice("REVIEW_APPROVED",Map.of(),true));
  assertEquals("tasks",PushRules.notice("TASK_EVENT",Map.of("action","RETURNED"),false).category());
  assertEquals("deadlines",PushRules.notice("DEADLINE",Map.of("stage","OVERDUE"),false).category());
  assertEquals("reviews",PushRules.notice("REVIEW_PENDING",Map.of(),false).category());
 }
 @Test void shanghaiQuietHoursCrossMidnightAndBoundaries() {
  assertEquals(Instant.parse("2026-11-12T00:00:00Z"),PushRules.quietUntil(Instant.parse("2026-11-11T15:30:00Z"),true,22,8));
  assertEquals(Instant.parse("2026-11-12T00:00:00Z"),PushRules.quietUntil(Instant.parse("2026-11-11T23:59:00Z"),true,22,8));
  var boundary=Instant.parse("2026-11-12T00:00:00Z");assertEquals(boundary,PushRules.quietUntil(boundary,true,22,8));
  var daytime=Instant.parse("2026-11-12T04:00:00Z");assertEquals(Instant.parse("2026-11-12T05:00:00Z"),PushRules.quietUntil(daytime,true,12,13));
  assertEquals(daytime,PushRules.quietUntil(daytime,false,12,13));
 }
 @Test void boundedBackoff() { assertEquals(15,PushRules.backoff(1).toSeconds());assertEquals(240,PushRules.backoff(5).toSeconds()); }
}
