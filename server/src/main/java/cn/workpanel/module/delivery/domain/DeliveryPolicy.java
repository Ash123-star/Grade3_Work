package cn.workpanel.module.delivery.domain;

import cn.workpanel.Actor;
import cn.workpanel.ApiError;
import cn.workpanel.Db;
import java.time.LocalDate;
import java.time.format.DateTimeParseException;
import java.util.*;

public final class DeliveryPolicy {
    private static final Set<String> KINDS = Set.of("PERFORMANCE", "PRIVATE_BANQUET", "COMPANY_VISIT", "SALON");

    private DeliveryPolicy() {}

    public static void requireAdmin(Actor actor) {
        if (!cn.workpanel.module.review.domain.ReviewPolicy.eligibleOfflineAdmin(actor)) throw ApiError.forbidden();
    }

    public record Draft(String kind, String title, String businessDate, String ownerId, List<String> participants) {
        public Map<String, Object> snapshot() {
            return Map.of("kind", kind, "title", title, "businessDate", businessDate, "ownerId", ownerId,
                    "participants", participants);
        }

        public List<String> employees() {
            var ids = new TreeSet<>(participants);
            ids.add(ownerId);
            return List.copyOf(ids);
        }
    }

    public static Draft draft(Map<String, Object> body) {
        String kind = Db.required(body, "kind");
        if (!KINDS.contains(kind)) throw ApiError.bad("INVALID_KIND", "线下业务类型无效");
        String title = text(body, "title", 120);
        String owner = text(body, "ownerId", 128);
        String date = Db.required(body, "businessDate");
        try {
            if (!date.matches("[0-9]{4}-[0-9]{2}-[0-9]{2}") || LocalDate.parse(date).getYear() < 1) {
                throw ApiError.bad("INVALID_DATE", "业务日期须为有效的 YYYY-MM-DD");
            }
        } catch (DateTimeParseException e) {
            throw ApiError.bad("INVALID_DATE", "业务日期须为有效的 YYYY-MM-DD");
        }
        if (!(body.get("participants") instanceof List<?> values) || values.size() > 50) {
            throw ApiError.bad("INVALID_PARTICIPANTS", "参与员工须为列表，最多50人");
        }
        var participants = new TreeSet<String>();
        for (Object value : values) {
            if (!(value instanceof String id) || id.isBlank() || id.length() > 128
                    || id.equals(owner) || !participants.add(id)) {
                throw ApiError.bad("INVALID_PARTICIPANTS", "参与员工无效、重复或已是负责人");
            }
        }
        return new Draft(kind, title, date, owner, List.copyOf(participants));
    }

    public static String text(Map<String, Object> body, String field, int max) {
        String value = Db.required(body, field);
        if (value.length() > max) throw ApiError.bad("INVALID_FIELD", field + " 最多 " + max + " 字");
        return value;
    }

    public static String action(Map<String, Object> body) {
        String action = Db.required(body, "action");
        switch (action) {
            case "EDIT" -> Db.fields(body, "version", "reason", "action", "kind", "title", "businessDate", "ownerId", "participants");
            case "END_ACTIVITY", "CONFIRM_DELIVERY" -> Db.fields(body, "version", "reason", "action");
            default -> throw ApiError.bad("INVALID_ACTION", "线下业务操作无效");
        }
        return action;
    }

    public static void transition(String action, Map<String, Object> current) {
        boolean scheduled = "SCHEDULED".equals(current.get("activityStatus"));
        boolean pending = "PENDING".equals(current.get("deliveryStatus"));
        if (action.equals("EDIT") || action.equals("END_ACTIVITY") && scheduled
                || action.equals("CONFIRM_DELIVERY") && !scheduled && pending) return;
        throw new ApiError(409, "INVALID_DELIVERY_TRANSITION", "活动或交付状态已改变，请刷新后重试");
    }

    public static void validateEdit(Draft draft, Map<String, Object> current) {
        if (!draft.kind().equals(current.get("kind"))) throw ApiError.bad("IMMUTABLE_KIND", "不能更改活动类型");
        if (draft.snapshot().entrySet().stream().allMatch(e -> Objects.equals(e.getValue(), current.get(e.getKey())))) {
            throw ApiError.bad("NO_CHANGE", "没有需要提交的修改");
        }
    }
}
