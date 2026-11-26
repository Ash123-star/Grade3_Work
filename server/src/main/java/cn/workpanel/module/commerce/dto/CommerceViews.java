package cn.workpanel.module.commerce.dto;

import cn.workpanel.module.commerce.domain.CommerceImport.MemberStatus;
import cn.workpanel.module.commerce.domain.CommerceImport.OrderStatus;

import java.time.Instant;
import java.time.LocalDate;
import java.util.List;

public final class CommerceViews {
    private CommerceViews() {}

    public record Counts(int applied, int unchanged, int stale) {}

    public record ImportReceipt(String id, String sha256, Instant importedAt, Counts members, Counts orders,
                                boolean replayed) {}

    public record ImportFailure(String code, String message, String traceId, String section, Integer row,
                                String field) {}

    public record MemberView(String externalMemberId, String level, MemberStatus status, LocalDate joinedAt,
                             LocalDate expiresAt, Instant sourceUpdatedAt, String importId, int sourceRow) {}

    public record OrderView(String externalOrderId, String externalMemberId, OrderStatus status, String currency,
                            String amount, Instant orderedAt, Instant sourceUpdatedAt, String importId,
                            int sourceRow) {}

    public record OrderGroup(OrderStatus status, String currency, long orderCount, String amount) {}

    public record Overview(long orderCount, List<OrderGroup> groups) {}

}
