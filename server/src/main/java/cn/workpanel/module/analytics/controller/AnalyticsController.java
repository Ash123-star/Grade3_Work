package cn.workpanel.module.analytics.controller;

import cn.workpanel.*;
import cn.workpanel.module.analytics.application.*;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;
import java.util.*;

/** 分析 HTTP 边界；日期、组织筛选与授权由同一应用服务处理。 */
@RestController
@RequestMapping("/api")
public class AnalyticsController {
    private final AnalyticsService service;
    public AnalyticsController(AnalyticsService service) { this.service=service; }
    /** 公开服务及数据库连通状态；无版本、分页或幂等键。 */
    @GetMapping("/health") public Map<String,Object> health() { return service.health(); }
    /** 当前有效账号的授权统计；date/period/groupBy/departmentId/teamId/ownerId 与明细和导出相同。无效400，越权403/404；只读、无幂等键/版本要求。 */
    @GetMapping("/analytics")
    public Map<String,Object> stats(HttpServletRequest r,@RequestParam String date,@RequestParam(defaultValue="week") String period,@RequestParam(defaultValue="department") String groupBy,@RequestParam(required=false) String departmentId,@RequestParam(required=false) String teamId,@RequestParam(required=false) String ownerId) {
        return service.statistics(Actor.current(r),new AnalyticsQuery(date,period,groupBy,departmentId,teamId,ownerId));
    }
    /** 指标明细；metric白名单，可选groupId和区间内bucket=YYYY-MM-DD；offset cursor>=0、limit 1–100。无效400、越权403/404；只读，无版本和幂等键。 */
    @GetMapping("/analytics/details")
    public Map<String,Object> details(HttpServletRequest r,@RequestParam String date,@RequestParam(defaultValue="week") String period,@RequestParam(defaultValue="department") String groupBy,@RequestParam(required=false) String departmentId,@RequestParam(required=false) String teamId,@RequestParam(required=false) String ownerId,@RequestParam String metric,@RequestParam(required=false) String groupId,@RequestParam(required=false) String bucket,@RequestParam(defaultValue="0") int cursor,@RequestParam(defaultValue="30") int limit) {
        return service.details(Actor.current(r),new AnalyticsQuery(date,period,groupBy,departmentId,teamId,ownerId),metric,groupId,bucket,cursor,limit);
    }
    /** 同范围CSV：resource=logs/tasks，最多10000条，超限400不截断，公式转义、UTF-8。授权及错误同汇总；无版本和幂等键。 */
    @GetMapping(value="/analytics/export",produces="text/csv")
    public ResponseEntity<String> export(HttpServletRequest r,@RequestParam String date,@RequestParam(defaultValue="week") String period,@RequestParam(defaultValue="logs") String resource,@RequestParam(defaultValue="department") String groupBy,@RequestParam(required=false) String departmentId,@RequestParam(required=false) String teamId,@RequestParam(required=false) String ownerId) {
        String body=service.export(Actor.current(r),new AnalyticsQuery(date,period,groupBy,departmentId,teamId,ownerId),resource);
        return ResponseEntity.ok().contentType(new MediaType("text","csv",java.nio.charset.StandardCharsets.UTF_8)).header(HttpHeaders.CONTENT_DISPOSITION,"attachment; filename=\""+resource+".csv\"").body(body);
    }
    public static String csv(Object value) { return AnalyticsService.csv(value); }
    /** 当前授权范围时间线；ownerId须可见，date/period同列表；只读、无版本或幂等键。 */
    @GetMapping("/timeline") public Map<String,Object> timeline(HttpServletRequest r,@RequestParam String date,@RequestParam(defaultValue="day") String period,@RequestParam(required=false) String ownerId) { return service.timeline(Actor.current(r),date,period,ownerId); }
}