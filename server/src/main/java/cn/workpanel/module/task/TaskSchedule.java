package cn.workpanel.module.task;

import cn.workpanel.ApiError;
import java.time.*;

/** 上海业务排期领域规则；不读取设备时区或数据库。 */
public final class TaskSchedule {
    public static final ZoneId ZONE = ZoneId.of("Asia/Shanghai");
    private TaskSchedule() {}
    public record Interval(String startAt, String deadline) {}
    public static Interval move(String start, String end, int days) {
        if (days == 0) throw ApiError.bad("INVALID_MOVE_DAYS", "移动天数不能为零");
        try {
            var deadline = OffsetDateTime.parse(end).atZoneSameInstant(ZONE);
            var begin = start == null || start.isBlank() ? null : OffsetDateTime.parse(start).atZoneSameInstant(ZONE);
            if (begin != null && !begin.isBefore(deadline)) throw new IllegalArgumentException();
            var nextEnd = deadline.plusDays(days);
            var nextStart = begin == null ? null : begin.plusDays(days);
            if (!nextEnd.toLocalTime().equals(deadline.toLocalTime()) || nextStart != null &&
                (!nextStart.toLocalTime().equals(begin.toLocalTime()) || !Duration.between(begin,deadline).equals(Duration.between(nextStart,nextEnd)))) throw new IllegalArgumentException();
            if (nextEnd.getYear()<1 || nextEnd.getYear()>9999 || nextStart!=null && (nextStart.getYear()<1 || nextStart.getYear()>9999)) throw new IllegalArgumentException();
            return new Interval(nextStart==null?null:nextStart.toOffsetDateTime().toString(),nextEnd.toOffsetDateTime().toString());
        } catch (RuntimeException error) {
            if(error instanceof ApiError api) throw api;
            throw ApiError.bad("INVALID_DATE", "原排期无效或移动后日期越界");
        }
    }
    public static int integer(Object value, boolean positive, String code) {
        if (!(value instanceof Byte || value instanceof Short || value instanceof Integer || value instanceof Long || value instanceof java.math.BigInteger)) throw ApiError.bad(code,"必须为整数");
        try {
            int n = new java.math.BigInteger(value.toString()).intValueExact();
            if (positive ? n<=0 : n==0) throw new ArithmeticException();
            return n;
        } catch (ArithmeticException e) { throw ApiError.bad(code,"整数超出有效范围"); }
    }
    public static String reason(Object value) {
        if (!(value instanceof String s)) throw ApiError.bad("INVALID_REASON","请填写改期原因");
        int begin=0,end=s.length();
        while(begin<end && space(s.codePointAt(begin))) begin+=Character.charCount(s.codePointAt(begin));
        while(end>begin && space(s.codePointBefore(end))) end-=Character.charCount(s.codePointBefore(end));
        s=s.substring(begin,end);
        if(s.isEmpty() || s.codePointCount(0,s.length())>1000 || s.codePoints().anyMatch(c->c>=0xD800&&c<=0xDFFF)) throw ApiError.bad("INVALID_REASON","原因需要 1–1000 个字符");
        return s;
    }
    private static boolean space(int c) { return Character.isWhitespace(c)||Character.isSpaceChar(c); }
    public static void key(String key) {
        if(key==null || !key.matches("[!-~]{1,128}")) throw ApiError.bad("IDEMPOTENCY_REQUIRED","需要 1–128 位无空白可见 ASCII 幂等键");
    }
    public static String instant(Object value) {
        if(value==null)return null;
        if(value instanceof java.sql.Timestamp t)return t.toInstant().toString();
        if(value instanceof OffsetDateTime t)return t.toString();
        return value.toString();
    }
    public static int nextVersion(int version) {
        if(version==Integer.MAX_VALUE) throw new ApiError(409,"VERSION_EXHAUSTED","任务版本已达上限");
        return Math.addExact(version,1);
    }
}
