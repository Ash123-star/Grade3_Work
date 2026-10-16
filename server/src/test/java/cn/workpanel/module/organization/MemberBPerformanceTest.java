package cn.workpanel.module.organization;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;
import static org.junit.jupiter.api.Assertions.*;

/** 参考规模下 B 的组织树与审核列表 HTTP 诊断，不替代首页或全产品性能验收。 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = {
    "app.admin-account=integration-admin", "app.admin-password=Initial-test-password-2026", "app.admin-phone=13900000001"
})
class MemberBPerformanceTest extends MemberBHttpSupport {
    record Sample(String endpoint, double milliseconds) { }
    @Test void twentyConcurrentReadersWithReferenceDataVolume() throws Exception {
        db.update("INSERT INTO users(id,company_id,account,password_hash,phone,name,department_id,team_id,role,status) SELECT 'perf-user-'||?||'-'||g,?,'perf-account-'||?||'-'||g,'not-used-for-login','133'||lpad(g::text,8,'0'),'性能人员'||g,?,?,'EMPLOYEE','ACTIVE' FROM generate_series(1,1000) g", company, company, company, department, team);
        db.update("INSERT INTO daily_logs(id,company_id,owner_id,business_date,body) SELECT 'perf-log-'||?||'-'||g,?,'perf-user-'||?||'-'||(g%1000+1),CURRENT_DATE-(g/1000+1),'{}' FROM generate_series(0,99999) g", company, company, company);
        db.update("INSERT INTO tasks(id,company_id,owner_id,issuer_id,title,deadline,body) SELECT 'perf-task-'||?||'-'||g,?,'perf-user-'||?||'-'||(g%1000+1),?,'性能任务'||g,now()+interval '1 day',jsonb_build_object('title','性能任务'||g,'ownerId','perf-user-'||?||'-'||(g%1000+1),'deadline',now()+interval '1 day','urgency','NORMAL','content','性能背景数据','collaborators','[]'::jsonb) FROM generate_series(0,9999) g", company, company, company, leader, company);
        db.update("INSERT INTO task_assignees(task_id,user_id,kind,company_id) SELECT id,owner_id,'PRIMARY',company_id FROM tasks WHERE company_id=?", company);
        assertEquals(100000, db.count("SELECT count(*) FROM daily_logs WHERE company_id=?", company));
        assertEquals(10000, db.count("SELECT count(*) FROM tasks WHERE company_id=?", company));
        revision(employee, Map.of("name", "性能候选"));
        for (int i = 0; i < 5; i++) { call(200, "GET", "/organization", admin, null); call(200, "GET", "/reviews", admin, null); }
        List<Sample> samples = Collections.synchronizedList(new ArrayList<>());
        var barrier = new CyclicBarrier(20);
        try (var pool = Executors.newFixedThreadPool(20)) {
            var futures = new ArrayList<Future<?>>();
            for (int worker = 0; worker < 20; worker++) {
                int number = worker;
                futures.add(pool.submit(() -> {
                    barrier.await(20, TimeUnit.SECONDS);
                    for (int i = 0; i < 5; i++) {
                        String endpoint = (number + i) % 2 == 0 ? "/organization" : "/reviews";
                        long start = System.nanoTime(); call(200, "GET", endpoint, admin, null);
                        samples.add(new Sample(endpoint, (System.nanoTime() - start) / 1_000_000.0));
                    }
                    return null;
                }));
            }
            for (var future : futures) future.get(90, TimeUnit.SECONDS);
        }
        var report = new LinkedHashMap<String, Object>();
        report.put("scope", "B组织树与审核列表；合成背景数据，非首页/全产品性能验收");
        report.put("concurrency", 20); report.put("warmupRequests", 10); report.put("samples", samples.size());
        report.put("logRows", 100000); report.put("taskRows", 10000); report.put("organizationPeople", 1008);
        report.put("java", System.getProperty("java.version")); report.put("os", System.getProperty("os.name"));
        report.put("jvmProcessors", Runtime.getRuntime().availableProcessors()); report.put("jvmMaxMemoryBytes", Runtime.getRuntime().maxMemory());
        var p95s = new LinkedHashMap<String, Double>();
        for (String endpoint : List.of("/organization", "/reviews")) {
            var values = samples.stream().filter(sample -> sample.endpoint().equals(endpoint)).mapToDouble(Sample::milliseconds).sorted().toArray();
            p95s.put(endpoint, values[(int) Math.ceil(values.length * .95) - 1]);
        }
        report.put("p95Milliseconds", p95s); report.put("observations", samples);
        Path reportPath = Path.of("../output/member-b-performance.json");
        Files.createDirectories(reportPath.getParent()); Files.writeString(reportPath, JSON.writerWithDefaultPrettyPrinter().writeValueAsString(report));
        for (var entry : p95s.entrySet()) assertTrue(entry.getValue() <= 2000, entry.getKey() + " P95=" + entry.getValue() + "ms，超出参考目标");
    }
}
