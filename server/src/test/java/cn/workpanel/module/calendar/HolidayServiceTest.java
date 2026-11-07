package cn.workpanel.module.calendar;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.*;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;
class HolidayServiceTest {
 static class Time extends Clock {
  Instant now=Instant.parse("2026-10-31T00:00:00Z");
  public ZoneId getZone(){return ZoneOffset.UTC;} public Clock withZone(ZoneId zone){return this;} public Instant instant(){return now;}
 }
 static String valid="{\"year\":2026,\"papers\":[\"https://www.gov.cn/test\"],\"days\":[{\"date\":\"2026-10-01\",\"name\":\"国庆节\",\"isOffDay\":true},{\"date\":\"2026-10-10\",\"name\":\"国庆节\",\"isOffDay\":false}]}";
 @Test void refreshAndFailureRetainLastGoodSnapshot() {
  var time=new Time(); int[] calls={0};
  var service=new HolidayService(new ObjectMapper(),time,y->{ calls[0]++; if(calls[0]>1) throw new Exception(); return valid; });
  assertEquals("FRESH",service.year(2026).status()); assertFalse(service.year(2026).days().get(1).isOffDay()); assertEquals(1,calls[0]);
  time.now=time.now.plus(Duration.ofHours(24));
  assertEquals("STALE",service.year(2026).status()); assertEquals(2,service.year(2026).days().size()); assertEquals(2,calls[0]);
 }
 @Test void successfulRefreshReplacesData() {
  var time=new Time(); int[] calls={0};
  var service=new HolidayService(new ObjectMapper(),time,y->++calls[0]==1?valid:valid.replace("国庆节","更新名称"));
  assertEquals("国庆节",service.year(2026).days().getFirst().name());
  time.now=time.now.plus(Duration.ofHours(24));
  assertEquals("更新名称",service.year(2026).days().getFirst().name());
 }
 @Test void missingAndInvalidDataNeverInventHolidays() {
  var service=new HolidayService(new ObjectMapper(),new Time(),y->"{}");
  assertEquals("UNAVAILABLE",service.year(2026).status()); assertTrue(service.year(2026).days().isEmpty());
  assertThrows(cn.workpanel.ApiError.class,()->service.year(2101));
 }
 @Test void sourceYearAndReferencesAreValidated() throws Exception {
  var s=new HolidayService(new ObjectMapper(),new Time(),y->valid);
  assertThrows(Exception.class,()->s.parse(2025,valid,Instant.now()));
  assertThrows(Exception.class,()->s.parse(2026,valid.replace("www.gov.cn","example.com"),Instant.now()));
  assertThrows(Exception.class,()->s.parse(2026,valid.replace("2026-10-01","2026-02-30"),Instant.now()));
 }
 @Test void oversizedResponseCancelsBeforeBuffering() {
  var subscriber=new HolidayService.LimitedBody(); boolean[] cancelled={false};
  subscriber.onSubscribe(new java.util.concurrent.Flow.Subscription(){public void request(long n){} public void cancel(){cancelled[0]=true;}});
  subscriber.onNext(java.util.List.of(java.nio.ByteBuffer.allocate(262145)));
  assertTrue(cancelled[0]);
  assertThrows(java.util.concurrent.CompletionException.class,()->subscriber.getBody().toCompletableFuture().join());
 }
 @Test void announcementCanIncludePreviousDecemberButNotOtherYears() throws Exception {
  var service=new HolidayService(new ObjectMapper(),new Time(),y->valid);
  assertEquals("2025-12-31",service.parse(2026,valid.replace("2026-10-01","2025-12-31"),Instant.now()).days().getFirst().date());
  assertThrows(Exception.class,()->service.parse(2026,valid.replace("2026-10-01","2025-11-30"),Instant.now()));
 }
}
