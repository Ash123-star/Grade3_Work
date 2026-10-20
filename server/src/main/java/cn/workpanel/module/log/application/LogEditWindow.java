package cn.workpanel.module.log.application;

import cn.workpanel.*;
import java.time.*;
import java.util.*;

/** 首次提交开启不可重置的窗口；审核申请后可以跨窗口完成审批。 */
public final class LogEditWindow {
    private LogEditWindow() {}
    public static Instant submittedAt(Map<String,Object> log) {
        Object value=log.get("submitted_at");
        if(value==null) return null;
        if(value instanceof java.sql.Timestamp t) return t.toInstant();
        if(value instanceof OffsetDateTime t) return t.toInstant();
        if(value instanceof Instant t) return t;
        return OffsetDateTime.parse(value.toString()).toInstant();
    }
    public static boolean open(Map<String,Object> log,Instant now) {
        Instant start=submittedAt(log);
        return start==null ? !Boolean.TRUE.equals(log.get("submitted")) : now.isBefore(start.plus(Duration.ofHours(24)));
    }
    public static void requireOpen(Map<String,Object> log,Instant now) {
        if(!open(log,now)) throw new ApiError(409,"LOG_EDIT_WINDOW_EXPIRED","日志首次提交已满24小时，不可修改或撤回");
    }
    public static Map<String,Object> view(Db db,Actor actor,Map<String,Object> log,Instant now) {
        var result=new LinkedHashMap<>(Business.logDto(db,log));
        Instant start=submittedAt(log);
        boolean owner=actor.id().equals(log.get("owner_id"));
        boolean submitted=Boolean.TRUE.equals(log.get("submitted"));
        result.put("submittedAt",start);
        result.put("editableUntil",start==null?null:start.plus(Duration.ofHours(24)));
        result.put("canEdit",(owner||(submitted&&actor.admin()))&&open(log,now));
        result.put("canWithdraw",owner&&submitted&&open(log,now));
        return result;
    }
}
