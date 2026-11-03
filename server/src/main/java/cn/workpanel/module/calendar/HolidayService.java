package cn.workpanel.module.calendar;

import cn.workpanel.ApiError;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.net.URI;
import java.net.http.*;
import java.time.*;
import java.util.*;
import org.springframework.stereotype.Service;

/** Validated public calendar data; no company or user information is sent upstream. */
@Service
public class HolidayService {
    public record Day(String date,String name,boolean isOffDay) {}
    public record Snapshot(int year,List<Day> days,List<String> papers,String status,String fetchedAt) {}
    interface Source { String fetch(int year) throws Exception; }
    private record Entry(Snapshot data,Instant retryAt) {}
    private final Map<Integer,Entry> cache=new HashMap<>();
    private final Clock clock; private final Source source; private final ObjectMapper json;
    @org.springframework.beans.factory.annotation.Autowired
    public HolidayService(ObjectMapper json) {
        this(json,Clock.systemUTC(),HolidayService::fetchPublicYear);
    }
    static String fetchPublicYear(int year) throws Exception {
        var request=HttpRequest.newBuilder(URI.create("https://api.github.com/repos/NateScarlet/holiday-cn/contents/"+year+".json"))
                .header("Accept","application/vnd.github.raw+json").header("User-Agent","Pandora-Holiday-Calendar")
                .timeout(Duration.ofSeconds(6)).GET().build();
        try(var client=HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(2)).build()) {
            var response=client.send(request, info -> new LimitedBody());
            if(response.statusCode()!=200) throw new IllegalStateException("source unavailable");
            return new String(response.body(),java.nio.charset.StandardCharsets.UTF_8);
        }
    }
    /** Cancel before buffering more than 256 KiB; the request deadline covers the full body. */
    static final class LimitedBody implements HttpResponse.BodySubscriber<byte[]> {
        private final HttpResponse.BodySubscriber<byte[]> delegate=HttpResponse.BodySubscribers.ofByteArray();
        private java.util.concurrent.Flow.Subscription subscription;
        private int size;
        private boolean done;
        public java.util.concurrent.CompletionStage<byte[]> getBody(){return delegate.getBody();}
        public void onSubscribe(java.util.concurrent.Flow.Subscription s){subscription=s;delegate.onSubscribe(s);}
        public void onNext(List<java.nio.ByteBuffer> buffers){
            if(done)return;
            long incoming=buffers.stream().mapToLong(java.nio.ByteBuffer::remaining).sum();
            if(incoming>262144-size){done=true;subscription.cancel();delegate.onError(new IllegalStateException("source too large"));return;}
            size+=(int)incoming;delegate.onNext(buffers);
        }
        public void onError(Throwable error){if(!done){done=true;delegate.onError(error);}}
        public void onComplete(){if(!done){done=true;delegate.onComplete();}}
    }

    HolidayService(ObjectMapper json,Clock clock,Source source) { this.json=json; this.clock=clock; this.source=source; }
    /** Bounded annual cache; repeated failures are throttled, last valid data retained. */
    public synchronized Snapshot year(int year) {
        if(year<2007||year>2100) throw ApiError.bad("INVALID_YEAR","年份须在2007至2100之间");
        Instant now=clock.instant(); var old=cache.get(year);
        if(old!=null&&now.isBefore(old.retryAt())) return old.data();
        Snapshot result; Duration delay;
        try { result=parse(year,source.fetch(year),now); delay=Duration.ofHours(24); }
        catch(Exception e) {
            if(e instanceof InterruptedException) Thread.currentThread().interrupt();
            var saved=old==null?null:old.data();
            result=new Snapshot(year,saved==null?List.of():saved.days(),saved==null?List.of():saved.papers(),saved==null||saved.fetchedAt().isEmpty()?"UNAVAILABLE":"STALE",saved==null?"":saved.fetchedAt());
            delay=Duration.ofMinutes(5);
        }
        cache.put(year,new Entry(result,now.plus(delay))); return result;
    }
    Snapshot parse(int year,String body,Instant now) throws Exception {
        var root=json.readTree(body);
        if(!root.path("year").isIntegralNumber()||root.path("year").asInt()!=year||!root.path("days").isArray()||!root.path("papers").isArray()||root.path("papers").isEmpty()) throw new IllegalArgumentException("invalid source");
        var papers=new ArrayList<String>();
        for(var item:root.path("papers")) {
            if(!item.isTextual()) throw new IllegalArgumentException("invalid paper");
            var uri=URI.create(item.asText()); String host=uri.getHost();
            if(!Set.of("https","http").contains(uri.getScheme())||host==null||!(host.equals("gov.cn")||host.endsWith(".gov.cn"))) throw new IllegalArgumentException("invalid paper");
            papers.add(item.asText());
        }
        var days=new ArrayList<Day>(); var seen=new HashSet<String>();
        if(root.path("days").size()>400) throw new IllegalArgumentException("too many days");
        for(var item:root.path("days")) {
            String date=item.path("date").asText(),name=item.path("name").asText();
            LocalDate parsed=LocalDate.parse(date);
            if(parsed.getYear()!=year&&!(parsed.getYear()==year-1&&parsed.getMonthValue()==12)) throw new IllegalArgumentException("date outside source year");
            if(name.isBlank()||name.length()>100||!item.path("isOffDay").isBoolean()||!seen.add(date)) throw new IllegalArgumentException("invalid day");
            days.add(new Day(date,name,item.path("isOffDay").asBoolean()));
        }
        return new Snapshot(year,List.copyOf(days),List.copyOf(papers),"FRESH",now.toString());
    }
}
