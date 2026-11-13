package cn.workpanel.module.push.domain;

import java.time.*;
import java.util.*;

/** Necessary notification selection and Shanghai quiet hours; no business body is sent. */
public final class PushRules {
    private PushRules() {}
    public static final ZoneId SHANGHAI=ZoneId.of("Asia/Shanghai");
    public record Notice(String category,String title) {}
    public static Notice notice(String type,Map<String,Object> body,boolean membership) {
        return switch(type) {
            case "TASK_ASSIGNED","TASK_DISPATCHED" -> new Notice("tasks","你有一项新任务");
            case "TASK_REASSIGNED","TASK_REVISED","TASK_RESCHEDULED" -> new Notice("tasks","你的任务安排有变更");
            case "TASK_EVENT" -> switch(String.valueOf(body.get("action"))) {
                case "WITHDRAWN" -> new Notice("tasks","你的任务已撤回");
                case "RETURNED" -> new Notice("tasks","任务成果需要补充");
                default -> null;
            };
            case "DEADLINE" -> new Notice("deadlines","OVERDUE".equals(body.get("stage"))?"你有一项任务已逾期":"你有一项任务即将截止");
            case "REVIEW_PENDING" -> new Notice("reviews","你有一项申请待审批");
            case "REVIEW_REJECTED" -> new Notice("reviews",membership?"你的入职申请已有审核结果":"你的申请已被驳回");
            case "REVIEW_APPROVED" -> membership?new Notice("reviews","你的入职申请已有审核结果"):null;
            default -> null;
        };
    }
    public static Instant quietUntil(Instant now,boolean enabled,int start,int end) {
        if(!enabled) return now;
        var local=now.atZone(SHANGHAI); int hour=local.getHour();
        boolean quiet=start<end?hour>=start&&hour<end:hour>=start||hour<end;
        if(!quiet) return now;
        var date=local.toLocalDate(); if(start>end&&hour>=start) date=date.plusDays(1);
        return date.atTime(end,0).atZone(SHANGHAI).toInstant();
    }
    public static Duration backoff(int attempt) { return Duration.ofSeconds(Math.min(900,15L<<(attempt-1))); }
}
