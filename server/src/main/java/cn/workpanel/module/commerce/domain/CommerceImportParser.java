package cn.workpanel.module.commerce.domain;

import com.fasterxml.jackson.databind.DeserializationFeature;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.ObjectReader;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.math.BigDecimal;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.Currency;
import java.util.HashSet;
import java.util.Iterator;
import java.util.Set;

import static cn.workpanel.module.commerce.domain.CommerceImport.*;

@Component
public class CommerceImportParser {
    private static final Set<String> ROOT_FIELDS = Set.of("members", "orders");
    private static final Set<String> MEMBER_FIELDS =
            Set.of("externalMemberId", "level", "status", "joinedAt", "expiresAt", "sourceUpdatedAt");
    private static final Set<String> ORDER_FIELDS =
            Set.of("externalOrderId", "externalMemberId", "status", "currency", "amount", "orderedAt", "sourceUpdatedAt");
    private final ObjectReader reader;

    public CommerceImportParser(ObjectMapper mapper) {
        this.reader = mapper.reader()
                .with(DeserializationFeature.FAIL_ON_READING_DUP_TREE_KEY)
                .with(DeserializationFeature.FAIL_ON_TRAILING_TOKENS);
    }

    public CommerceImport parse(byte[] data) {
        JsonNode root;
        try {
            String content = StandardCharsets.UTF_8.newDecoder().decode(ByteBuffer.wrap(data)).toString();
            root = reader.readTree(content.startsWith("\uFEFF") ? content.substring(1) : content);
        } catch (IOException e) {
            throw CommerceImportRejected.invalid("file", null, null, "需要有效的 UTF-8 JSON，且字段不能重复");
        }
        Location file = new Location("file", null);
        checkObject(root, ROOT_FIELDS, file);
        JsonNode memberRows = array(root, "members", file);
        JsonNode orderRows = array(root, "orders", file);
        int size = memberRows.size() + orderRows.size();
        if (size < 1 || size > MAX_ROWS) {
            throw file.invalid(null, "会员与订单合计须有 1 至 500 条记录");
        }

        var members = new ArrayList<Row<Member>>(memberRows.size());
        Set<String> memberIds = new HashSet<>();
        for (int index = 0; index < memberRows.size(); index++) {
            Location location = new Location("members", index + 1);
            JsonNode row = memberRows.get(index);
            checkObject(row, MEMBER_FIELDS, location);
            Member member = member(row, location);
            if (!memberIds.add(member.externalMemberId())) {
                throw location.invalid("externalMemberId", "文件内会员 ID 重复");
            }
            members.add(new Row<>(index + 1, member));
        }

        var orders = new ArrayList<Row<Order>>(orderRows.size());
        Set<String> orderIds = new HashSet<>();
        for (int index = 0; index < orderRows.size(); index++) {
            Location location = new Location("orders", index + 1);
            JsonNode row = orderRows.get(index);
            checkObject(row, ORDER_FIELDS, location);
            Order order = order(row, location);
            if (!orderIds.add(order.externalOrderId())) {
                throw location.invalid("externalOrderId", "文件内订单 ID 重复");
            }
            orders.add(new Row<>(index + 1, order));
        }
        return new CommerceImport(members, orders);
    }

    private static Member member(JsonNode row, Location location) {
        String id = text(row, location, "externalMemberId", EXTERNAL_ID_LENGTH, true);
        String level = text(row, location, "level", 100, false);
        MemberStatus status = state(row, location, MemberStatus.class);
        LocalDate joinedAt = date(row, location, "joinedAt");
        LocalDate expiresAt = date(row, location, "expiresAt");
        if (joinedAt != null && expiresAt != null && expiresAt.isBefore(joinedAt)) {
            throw location.invalid("expiresAt", "到期日期须等于或晚于加入日期");
        }
        return new Member(id, level == null ? "" : level, status, joinedAt, expiresAt,
                timestamp(row, location, "sourceUpdatedAt"));
    }

    private static Order order(JsonNode row, Location location) {
        String id = text(row, location, "externalOrderId", EXTERNAL_ID_LENGTH, true);
        String memberId = text(row, location, "externalMemberId", EXTERNAL_ID_LENGTH, false);
        OrderStatus status = state(row, location, OrderStatus.class);
        String currency = text(row, location, "currency", 3, true);
        if (!validCurrency(currency)) {
            throw location.invalid("currency", "需要有效的三位大写币种代码");
        }
        String amount = text(row, location, "amount", 20, true);
        if (!amount.matches("[0-9]{1,15}(?:\\.[0-9]{1,4})?")) {
            throw location.invalid("amount", "金额须为非负十进制字符串，最多 15 位整数和 4 位小数");
        }
        Instant orderedAt = timestamp(row, location, "orderedAt");
        Instant updatedAt = timestamp(row, location, "sourceUpdatedAt");
        if (updatedAt.isBefore(orderedAt)) {
            throw location.invalid("sourceUpdatedAt", "源更新时间须等于或晚于下单时间");
        }
        return new Order(id, memberId, status, currency, new BigDecimal(amount).setScale(4), orderedAt, updatedAt);
    }

    public static boolean validCurrency(String value) {
        if (!value.matches("[A-Z]{3}")) return false;
        try {
            Currency.getInstance(value);
            return true;
        } catch (IllegalArgumentException e) {
            return false;
        }
    }

    public static boolean validText(String value, int maxLength) {
        return value.length() <= maxLength
                && value.codePoints().noneMatch(cp -> Character.isISOControl(cp)
                        || Character.getType(cp) == Character.SURROGATE);
    }

    private static void checkObject(JsonNode value, Set<String> allowed, Location location) {
        if (value == null || !value.isObject()) throw location.invalid(null, "需要 JSON 对象");
        for (Iterator<String> fields = value.fieldNames(); fields.hasNext();) {
            if (!allowed.contains(fields.next())) throw location.invalid(null, "包含未声明字段");
        }
    }

    private static JsonNode array(JsonNode root, String section, Location file) {
        if (!root.has(section)) return root.path(section);
        JsonNode value = root.get(section);
        if (!value.isArray()) throw file.invalid(section, "需要 JSON 数组");
        return value;
    }

    private static String text(JsonNode row, Location location, String field, int maxLength, boolean required) {
        JsonNode node = row.path(field);
        if (!required && (node.isMissingNode() || node.isNull())) return null;
        if (!node.isTextual()) throw location.invalid(field, "需要文本");
        String value = node.textValue().trim();
        if (!validText(value, maxLength) || required && value.isEmpty()) {
            throw location.invalid(field, "字段为空、超出长度限制或含无效字符");
        }
        return value.isEmpty() ? null : value;
    }

    private static <E extends Enum<E>> E state(JsonNode row, Location location, Class<E> type) {
        String value = text(row, location, "status", 24, true);
        try {
            return Enum.valueOf(type, value);
        } catch (IllegalArgumentException e) {
            throw location.invalid("status", "状态值无效");
        }
    }

    private static LocalDate date(JsonNode row, Location location, String field) {
        String value = text(row, location, field, 10, false);
        if (value == null) return null;
        try {
            LocalDate date = LocalDate.parse(value);
            if (date.getYear() > 0 && date.getYear() <= 9999) return date;
        } catch (DateTimeParseException ignored) {
            // Return the corresponding file location below.
        }
        throw location.invalid(field, "需要有效日期 YYYY-MM-DD");
    }

    private static Instant timestamp(JsonNode row, Location location, String field) {
        String value = text(row, location, field, 35, true);
        try {
            OffsetDateTime timestamp = OffsetDateTime.parse(value);
            Instant instant = timestamp.toInstant();
            int utcYear = instant.atOffset(java.time.ZoneOffset.UTC).getYear();
            if (utcYear > 0 && utcYear <= 9999 && timestamp.getNano() % 1000 == 0) return instant;
        } catch (DateTimeParseException ignored) {
            // Return the corresponding file location below.
        }
        throw location.invalid(field, "需要有时区偏移的 ISO 8601 时间，最多微秒精度");
    }

    private record Location(String section, Integer row) {
        CommerceImportRejected invalid(String field, String message) {
            return CommerceImportRejected.invalid(section, row, field, message);
        }
    }
}
