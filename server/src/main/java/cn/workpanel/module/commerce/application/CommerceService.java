package cn.workpanel.module.commerce.application;

import cn.workpanel.Actor;
import cn.workpanel.ApiError;
import cn.workpanel.Business;
import cn.workpanel.Db;
import cn.workpanel.module.commerce.domain.CommerceImport;
import cn.workpanel.module.commerce.domain.CommerceImport.Member;
import cn.workpanel.module.commerce.domain.CommerceImport.Order;
import cn.workpanel.module.commerce.domain.CommerceImport.OrderStatus;
import cn.workpanel.module.commerce.domain.CommerceImport.Row;
import cn.workpanel.module.commerce.domain.CommerceImportParser;
import cn.workpanel.module.commerce.domain.CommerceImportRejected;
import cn.workpanel.module.commerce.domain.CommerceOrderScope;
import cn.workpanel.module.commerce.dto.CommerceViews.Counts;
import cn.workpanel.module.commerce.dto.CommerceViews.ImportReceipt;
import cn.workpanel.module.commerce.dto.CommerceViews.MemberView;
import cn.workpanel.module.commerce.dto.CommerceViews.OrderGroup;
import cn.workpanel.module.commerce.dto.CommerceViews.OrderView;
import cn.workpanel.module.commerce.dto.CommerceViews.Overview;
import cn.workpanel.module.commerce.infrastructure.CommerceRepository;
import cn.workpanel.module.customer.application.CustomerService;
import cn.workpanel.shared.api.ApiContracts.PageResponse;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Isolation;
import org.springframework.transaction.annotation.Transactional;

import java.io.IOException;
import java.io.InputStream;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.EnumMap;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import java.util.Optional;

@Service
public class CommerceService {
    private static final ZoneId SHANGHAI = ZoneId.of("Asia/Shanghai");

    private final CommerceRepository repository;
    private final CommerceImportParser parser;
    private final CustomerService customers;
    private final Db db;

    public CommerceService(CommerceRepository repository, CommerceImportParser parser, CustomerService customers, Db db) {
        this.repository = repository;
        this.parser = parser;
        this.customers = customers;
        this.db = db;
    }

    @Transactional
    public ImportReceipt importFile(Actor actor, InputStream file) {
        requireAccess(actor);
        byte[] bytes = readFile(file);
        CommerceImport source = parser.parse(bytes);
        String fingerprint = sha256(bytes);
        String company = actor.company();

        repository.lockCompany(company);
        Optional<ImportReceipt> replay = repository.replay(company, fingerprint);
        if (replay.isPresent()) return replay.get();

        String batch = Db.id();
        repository.startImport(company, batch, actor.id(), fingerprint);
        var members = new EnumMap<Outcome, Integer>(Outcome.class);
        for (Row<Member> row : source.members()) {
            members.merge(importMember(company, batch, row), 1, Integer::sum);
        }
        var orders = new EnumMap<Outcome, Integer>(Outcome.class);
        for (Row<Order> row : source.orders()) {
            orders.merge(importOrder(company, batch, row), 1, Integer::sum);
        }

        Counts memberCounts = counts(members);
        Counts orderCounts = counts(orders);
        repository.completeImport(company, batch, memberCounts, orderCounts);
        db.audit(actor, "COMMERCE_IMPORTED", batch, null, Map.of("members", memberCounts, "orders", orderCounts), "");
        return repository.receipt(company, batch).orElseThrow();
    }

    public ImportReceipt receipt(Actor actor, String id) {
        requireAccess(actor);
        return repository.receipt(actor.company(), id).orElseThrow(ApiError::notFound);
    }

    @Transactional(readOnly = true, isolation = Isolation.REPEATABLE_READ)
    public Overview overview(Actor actor, OrderFilter filter) {
        requireAccess(actor);
        List<OrderGroup> groups = scope(actor, filter)
                .map(scope -> repository.overview(actor.company(), scope))
                .orElseGet(List::of);
        return new Overview(groups.stream().mapToLong(OrderGroup::orderCount).sum(), groups);
    }

    @Transactional(readOnly = true, isolation = Isolation.REPEATABLE_READ)
    public PageResponse<OrderView> orders(Actor actor, OrderFilter filter, int cursor, int limit) {
        requireAccess(actor);
        Business.page(cursor, limit);
        return scope(actor, filter).map(scope -> repository.orders(actor.company(), scope, cursor, limit))
                .orElseGet(() -> new PageResponse<>(List.of(), 0, null));
    }

    @Transactional(readOnly = true, isolation = Isolation.REPEATABLE_READ)
    public PageResponse<MemberView> members(Actor actor, String customerId, String externalMemberId, int cursor, int limit) {
        requireAccess(actor);
        Business.page(cursor, limit);
        return memberScope(actor, customerId, externalMemberId)
                .map(scope -> repository.members(actor.company(), scope.id(), cursor, limit))
                .orElseGet(() -> new PageResponse<>(List.of(), 0, null));
    }

    private Outcome importMember(String company, String batch, Row<Member> row) {
        Member next = row.snapshot();
        Optional<Member> existing = repository.member(company, next.externalMemberId());
        if (existing.isPresent()) {
            Member current = existing.get();
            int version = next.sourceUpdatedAt().compareTo(current.sourceUpdatedAt());
            if (version < 0) return Outcome.STALE;
            if (version == 0) {
                if (next.equals(current)) return Outcome.UNCHANGED;
                throw versionConflict("members", row.number());
            }
        }
        repository.saveMember(company, batch, row);
        return Outcome.APPLIED;
    }

    private Outcome importOrder(String company, String batch, Row<Order> row) {
        Order next = row.snapshot();
        Optional<Order> existing = repository.order(company, next.externalOrderId());
        if (existing.isPresent()) {
            Order current = existing.get();
            int version = next.sourceUpdatedAt().compareTo(current.sourceUpdatedAt());
            if (version < 0) return Outcome.STALE;
            String field = next.changedIdentityField(current);
            if (field != null) {
                throw CommerceImportRejected.conflict("orders", row.number(), field, "已有订单的身份字段不一致");
            }
            if (version == 0) {
                if (next.equals(current)) return Outcome.UNCHANGED;
                throw versionConflict("orders", row.number());
            }
        } else if (next.externalMemberId() != null && repository.member(company, next.externalMemberId()).isEmpty()) {
            throw CommerceImportRejected.invalid("orders", row.number(), "externalMemberId", "当前公司未导入此会员");
        }
        repository.saveOrder(company, batch, row);
        return Outcome.APPLIED;
    }

    private Optional<CommerceOrderScope> scope(Actor actor, OrderFilter filter) {
        if (filter.from() != null && filter.to() != null && filter.to().isBefore(filter.from())) {
            throw ApiError.bad("INVALID_COMMERCE_DATES", "结束日期须等于或晚于开始日期");
        }
        Instant from = dateBoundary(filter.from(), false);
        Instant to = dateBoundary(filter.to(), true);
        String orderId = normalizeId(filter.externalOrderId());
        String currency = filter.currency();
        if (currency != null && !CommerceImportParser.validCurrency(currency)) {
            throw ApiError.bad("INVALID_COMMERCE_CURRENCY", "币种无效");
        }
        return memberScope(actor, filter.customerId(), filter.externalMemberId())
                .map(member -> new CommerceOrderScope(from, to, member.id(), orderId, filter.status(), currency));
    }

    private Optional<MemberScope> memberScope(Actor actor, String customerId, String externalMemberId) {
        String customer = normalizeId(customerId);
        String member = normalizeId(externalMemberId);
        if (customer != null && member != null) {
            throw ApiError.bad("INVALID_COMMERCE_FILTER", "客户 ID 和外部会员 ID 只能使用其中一项");
        }
        if (customer == null) return Optional.of(new MemberScope(member));
        return customers.mallMemberId(actor, customer).map(MemberScope::new);
    }

    private static String normalizeId(String value) {
        if (value == null) return null;
        String id = value.trim();
        if (!CommerceImportParser.validText(id, CommerceImport.EXTERNAL_ID_LENGTH) || id.isEmpty()) {
            throw ApiError.bad("INVALID_COMMERCE_ID", "记录 ID 无效");
        }
        return id;
    }

    private static Instant dateBoundary(LocalDate date, boolean exclusive) {
        if (date == null) return null;
        if (date.getYear() < 1 || date.getYear() > 9999) {
            throw ApiError.bad("INVALID_COMMERCE_DATES", "需提供有效日期");
        }
        return (exclusive ? date.plusDays(1) : date).atStartOfDay(SHANGHAI).toInstant();
    }

    private static void requireAccess(Actor actor) {
        actor.requireAdmin();
        if (!"ACTIVE".equals(actor.status())) throw ApiError.forbidden();
        if (actor.mustChange()) {
            throw new ApiError(403, "PASSWORD_CHANGE_REQUIRED", "首次登录请修改密码");
        }
    }

    private static byte[] readFile(InputStream file) {
        byte[] bytes;
        try {
            bytes = file.readNBytes(CommerceImport.MAX_BYTES + 1);
        } catch (IOException e) {
            throw CommerceImportRejected.invalid("file", null, null, "无法读取导入文件");
        }
        if (bytes.length > CommerceImport.MAX_BYTES) {
            throw new CommerceImportRejected(413, "COMMERCE_FILE_TOO_LARGE", "文件大小上限为 1 MiB", "file", null, null);
        }
        return bytes;
    }

    private static String sha256(byte[] bytes) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256 unavailable", e);
        }
    }

    private static CommerceImportRejected versionConflict(String section, int row) {
        return CommerceImportRejected.conflict(section, row, "sourceUpdatedAt", "同一源更新时间的内容不一致");
    }

    private static Counts counts(Map<Outcome, Integer> values) {
        return new Counts(values.getOrDefault(Outcome.APPLIED, 0), values.getOrDefault(Outcome.UNCHANGED, 0),
                values.getOrDefault(Outcome.STALE, 0));
    }

    public record OrderFilter(LocalDate from, LocalDate to, String customerId, String externalMemberId,
                              String externalOrderId, OrderStatus status, String currency) {}

    private record MemberScope(String id) {}

    private enum Outcome { APPLIED, UNCHANGED, STALE }
}
