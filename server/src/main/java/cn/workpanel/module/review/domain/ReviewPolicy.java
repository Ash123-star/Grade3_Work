package cn.workpanel.module.review.domain;

import cn.workpanel.*;
import java.util.Map;

/** 审核输入、自审和终态规则；不依赖 HTTP 或数据库。 */
public final class ReviewPolicy {
    private ReviewPolicy() { }
    public static boolean decision(Map<String, Object> command) {
        Db.fields(command, "approve", "reason");
        if (!(command.get("approve") instanceof Boolean)) throw ApiError.bad("INVALID_DECISION", "approve 必须为布尔值");
        if (command.containsKey("reason") && !(command.get("reason") instanceof String)) throw ApiError.bad("INVALID_FIELD", "reason 必须为文本");
        return (boolean) command.get("approve");
    }
    public static void request(String actor, String applicant, String status) {
        if (actor.equals(applicant)) throw new ApiError(403, "SELF_REVIEW", "禁止审核自己的申请");
        if (!status.equals("PENDING")) throw ApiError.conflict();
    }
    public static void reason(boolean approve, String reason) {
        if (!approve && reason.isBlank()) throw ApiError.bad("REASON_REQUIRED", "驳回需填写原因");
    }
}
