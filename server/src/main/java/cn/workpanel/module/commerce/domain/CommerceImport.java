package cn.workpanel.module.commerce.domain;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.Objects;

public record CommerceImport(List<Row<Member>> members, List<Row<Order>> orders) {
    public static final int MAX_ROWS = 500;
    public static final int MAX_BYTES = 1024 * 1024;
    public static final int EXTERNAL_ID_LENGTH = 200;

    public enum MemberStatus { ACTIVE, EXPIRED, DISABLED }

    public enum OrderStatus { PENDING_PAYMENT, PAID, COMPLETED, CANCELLED, REFUNDED, PARTIALLY_REFUNDED }

    public record Row<T>(int number, T snapshot) {}

    public record Member(String externalMemberId, String level, MemberStatus status, LocalDate joinedAt,
                         LocalDate expiresAt, Instant sourceUpdatedAt) {}

    public record Order(String externalOrderId, String externalMemberId, OrderStatus status, String currency,
                        BigDecimal amount, Instant orderedAt, Instant sourceUpdatedAt) {
        public String changedIdentityField(Order other) {
            if (!Objects.equals(externalMemberId, other.externalMemberId)) return "externalMemberId";
            if (!currency.equals(other.currency)) return "currency";
            if (!orderedAt.equals(other.orderedAt)) return "orderedAt";
            return null;
        }
    }
}
