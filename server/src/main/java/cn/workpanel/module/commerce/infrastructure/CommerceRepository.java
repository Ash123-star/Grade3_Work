package cn.workpanel.module.commerce.infrastructure;

import cn.workpanel.Db;
import cn.workpanel.module.commerce.domain.CommerceImport.Member;
import cn.workpanel.module.commerce.domain.CommerceImport.MemberStatus;
import cn.workpanel.module.commerce.domain.CommerceImport.Order;
import cn.workpanel.module.commerce.domain.CommerceImport.OrderStatus;
import cn.workpanel.module.commerce.domain.CommerceImport.Row;
import cn.workpanel.module.commerce.domain.CommerceOrderScope;
import cn.workpanel.module.commerce.dto.CommerceViews.Counts;
import cn.workpanel.module.commerce.dto.CommerceViews.ImportReceipt;
import cn.workpanel.module.commerce.dto.CommerceViews.MemberView;
import cn.workpanel.module.commerce.dto.CommerceViews.OrderGroup;
import cn.workpanel.module.commerce.dto.CommerceViews.OrderView;
import cn.workpanel.shared.api.ApiContracts.PageResponse;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.Instant;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

@Repository
public class CommerceRepository {
    private static final String MEMBER_COLUMNS =
            "external_member_id,level,status,joined_at,expires_at,source_updated_at,import_id,source_row";
    private static final String ORDER_COLUMNS =
            "external_order_id,external_member_id,status,currency,amount,ordered_at,source_updated_at,import_id,source_row";

    private final Db db;
    private final JdbcTemplate jdbc;

    public CommerceRepository(Db db, JdbcTemplate jdbc) {
        this.db = db;
        this.jdbc = jdbc;
    }

    public void lockCompany(String company) {
        db.one("SELECT id FROM companies WHERE id=? FOR NO KEY UPDATE", company);
    }

    public Optional<ImportReceipt> replay(String company, String sha256) {
        return receipt("SELECT * FROM commerce_imports WHERE company_id=? AND sha256=?", company, sha256, true);
    }

    public Optional<ImportReceipt> receipt(String company, String id) {
        return receipt("SELECT * FROM commerce_imports WHERE company_id=? AND id=?", company, id, false);
    }

    private Optional<ImportReceipt> receipt(String sql, String company, String key, boolean replayed) {
        return first(sql, (rs, n) -> new ImportReceipt(rs.getString("id"), rs.getString("sha256"),
                instant(rs, "imported_at"), counts(rs, "member"), counts(rs, "order"), replayed), company, key);
    }

    public void startImport(String company, String id, String actor, String sha256) {
        db.update("INSERT INTO commerce_imports(company_id,id,actor_id,sha256) VALUES (?,?,?,?)",
                company, id, actor, sha256);
    }

    public void completeImport(String company, String id, Counts members, Counts orders) {
        db.update("""
                UPDATE commerce_imports
                SET member_applied=?,member_unchanged=?,member_stale=?,
                    order_applied=?,order_unchanged=?,order_stale=?
                WHERE company_id=? AND id=?
                """, members.applied(), members.unchanged(), members.stale(),
                orders.applied(), orders.unchanged(), orders.stale(), company, id);
    }

    public Optional<Member> member(String company, String externalId) {
        return first("SELECT " + MEMBER_COLUMNS + " FROM commerce_members WHERE company_id=? AND external_member_id=?",
                (rs, n) -> member(rs), company, externalId);
    }

    public void saveMember(String company, String importId, Row<Member> row) {
        Member member = row.snapshot();
        db.update("""
                INSERT INTO commerce_members(company_id,external_member_id,level,status,joined_at,expires_at,
                                             source_updated_at,import_id,source_row)
                VALUES (?,?,?,?,?,?,?,?,?)
                ON CONFLICT(company_id,external_member_id) DO UPDATE SET
                    level=EXCLUDED.level,status=EXCLUDED.status,joined_at=EXCLUDED.joined_at,
                    expires_at=EXCLUDED.expires_at,source_updated_at=EXCLUDED.source_updated_at,
                    import_id=EXCLUDED.import_id,source_row=EXCLUDED.source_row
                """, company, member.externalMemberId(), member.level(), member.status().name(),
                member.joinedAt(), member.expiresAt(), offset(member.sourceUpdatedAt()), importId, row.number());
    }

    public Optional<Order> order(String company, String externalId) {
        return first("SELECT " + ORDER_COLUMNS + " FROM commerce_orders WHERE company_id=? AND external_order_id=?",
                (rs, n) -> order(rs), company, externalId);
    }

    public void saveOrder(String company, String importId, Row<Order> row) {
        Order order = row.snapshot();
        db.update("""
                INSERT INTO commerce_orders(company_id,external_order_id,external_member_id,status,currency,amount,
                                            ordered_at,source_updated_at,import_id,source_row)
                VALUES (?,?,?,?,?,?,?,?,?,?)
                ON CONFLICT(company_id,external_order_id) DO UPDATE SET
                    status=EXCLUDED.status,amount=EXCLUDED.amount,source_updated_at=EXCLUDED.source_updated_at,
                    import_id=EXCLUDED.import_id,source_row=EXCLUDED.source_row
                """, company, order.externalOrderId(), order.externalMemberId(), order.status().name(),
                order.currency(), order.amount(), offset(order.orderedAt()), offset(order.sourceUpdatedAt()),
                importId, row.number());
    }

    public List<OrderGroup> overview(String company, CommerceOrderScope scope) {
        Selection selection = scopedOrders(company, scope);
        return jdbc.query("""
                SELECT status,currency,count(*) AS order_count,sum(amount) AS amount
                FROM commerce_orders
                """ + selection.sql + " GROUP BY status,currency ORDER BY status,currency",
                (rs, n) -> new OrderGroup(OrderStatus.valueOf(rs.getString("status")), rs.getString("currency"),
                        rs.getLong("order_count"), rs.getBigDecimal("amount").toPlainString()),
                selection.args.toArray());
    }

    public PageResponse<OrderView> orders(String company, CommerceOrderScope scope, int cursor, int limit) {
        return page(ORDER_COLUMNS, "commerce_orders", scopedOrders(company, scope),
                "ordered_at DESC,external_order_id", cursor, limit, (rs, n) -> {
                    Order order = order(rs);
                    return new OrderView(order.externalOrderId(), order.externalMemberId(), order.status(),
                            order.currency(), order.amount().toPlainString(), order.orderedAt(),
                            order.sourceUpdatedAt(), rs.getString("import_id"), rs.getInt("source_row"));
                });
    }

    public PageResponse<MemberView> members(String company, String externalId, int cursor, int limit) {
        Selection selection = new Selection(company);
        selection.add("external_member_id=?", externalId);
        return page(MEMBER_COLUMNS, "commerce_members", selection, "external_member_id", cursor, limit,
                (rs, n) -> {
                    Member member = member(rs);
                    return new MemberView(member.externalMemberId(), member.level(), member.status(),
                            member.joinedAt(), member.expiresAt(), member.sourceUpdatedAt(),
                            rs.getString("import_id"), rs.getInt("source_row"));
                });
    }

    private static Selection scopedOrders(String company, CommerceOrderScope scope) {
        Selection selection = new Selection(company);
        selection.add("ordered_at>=?", offset(scope.from()));
        selection.add("ordered_at<?", offset(scope.toExclusive()));
        selection.add("external_member_id=?", scope.externalMemberId());
        selection.add("external_order_id=?", scope.externalOrderId());
        selection.add("status=?", scope.status() == null ? null : scope.status().name());
        selection.add("currency=?", scope.currency());
        return selection;
    }

    private <T> PageResponse<T> page(String columns, String table, Selection selection, String sort,
                                     int cursor, int limit, RowMapper<T> mapping) {
        String from = " FROM " + table + selection.sql;
        long total = db.count("SELECT count(*)" + from, selection.args.toArray());
        if (cursor >= total) return new PageResponse<>(List.of(), total, null);

        var pageArgs = new ArrayList<>(selection.args);
        pageArgs.add(limit);
        pageArgs.add(cursor);
        List<T> items = jdbc.query("SELECT " + columns + from + " ORDER BY " + sort + " LIMIT ? OFFSET ?",
                mapping, pageArgs.toArray());
        long next = (long) cursor + items.size();
        return new PageResponse<>(items, total, next < total ? Long.toString(next) : null);
    }

    private static final class Selection {
        private final StringBuilder sql = new StringBuilder(" WHERE company_id=?");
        private final List<Object> args = new ArrayList<>();

        private Selection(String company) {
            args.add(company);
        }

        private void add(String condition, Object value) {
            if (value != null) {
                sql.append(" AND ").append(condition);
                args.add(value);
            }
        }
    }

    private <T> Optional<T> first(String sql, RowMapper<T> mapping, Object... args) {
        return jdbc.query(sql, mapping, args).stream().findFirst();
    }

    private static Member member(ResultSet rs) throws SQLException {
        return new Member(rs.getString("external_member_id"), rs.getString("level"),
                MemberStatus.valueOf(rs.getString("status")), rs.getObject("joined_at", LocalDate.class),
                rs.getObject("expires_at", LocalDate.class), instant(rs, "source_updated_at"));
    }

    private static Order order(ResultSet rs) throws SQLException {
        return new Order(rs.getString("external_order_id"), rs.getString("external_member_id"),
                OrderStatus.valueOf(rs.getString("status")), rs.getString("currency"), rs.getBigDecimal("amount"),
                instant(rs, "ordered_at"), instant(rs, "source_updated_at"));
    }

    private static Counts counts(ResultSet rs, String prefix) throws SQLException {
        return new Counts(rs.getInt(prefix + "_applied"), rs.getInt(prefix + "_unchanged"),
                rs.getInt(prefix + "_stale"));
    }

    private static Instant instant(ResultSet rs, String column) throws SQLException {
        return rs.getObject(column, OffsetDateTime.class).toInstant();
    }

    private static OffsetDateTime offset(Instant instant) {
        return instant == null ? null : instant.atOffset(ZoneOffset.UTC);
    }
}
