package cn.workpanel.module.delivery.application;

import cn.workpanel.*;
import cn.workpanel.module.delivery.domain.DeliveryPolicy;
import cn.workpanel.module.delivery.infrastructure.DeliveryRepository;
import cn.workpanel.module.review.application.ReviewApplicationService;
import cn.workpanel.module.review.domain.ReviewPolicy;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Isolation;
import org.springframework.transaction.annotation.Transactional;
import java.util.*;

@Service
public class OfflineDeliveryService {
    private final DeliveryRepository repo;
    private final ReviewApplicationService reviews;

    public OfflineDeliveryService(DeliveryRepository repo, ReviewApplicationService reviews) {
        this.repo = repo;
        this.reviews = reviews;
    }

    private Actor admin(Actor request, boolean lock) {
        Actor actor = repo.actor(request, lock);
        DeliveryPolicy.requireAdmin(actor);
        return actor;
    }

    @Transactional(readOnly = true, isolation = Isolation.REPEATABLE_READ)
    public Map<String, Object> employees(Actor request, String search, boolean activeOnly, int cursor, int limit) {
        Actor actor = admin(request, false);
        Business.page(cursor, limit);
        String value = search.trim();
        if (value.length() > 100) throw ApiError.bad("INVALID_SEARCH", "关键词最多100字");
        return repo.employees(actor, value, activeOnly, cursor, limit);
    }

    @Transactional(readOnly = true, isolation = Isolation.REPEATABLE_READ)
    public Map<String, Object> list(Actor request, String customer, String employee, boolean pendingOnly, int cursor, int limit) {
        Actor actor = admin(request, false);
        Business.page(cursor, limit);
        if (customer.isEmpty() == employee.isEmpty()) {
            throw ApiError.bad("INVALID_FILTER", "请选择一个客户或员工");
        }
        return repo.list(actor, customer, employee, pendingOnly, cursor, limit);
    }

    @Transactional(readOnly = true, isolation = Isolation.REPEATABLE_READ)
    public Map<String, Object> get(Actor request, String id) {
        Actor actor = admin(request, false);
        var result = new LinkedHashMap<>(repo.get(actor, id, false));
        repo.pending(actor, id).ifPresent(pending -> {
            boolean own = actor.id().equals(pending.get("applicantId"));
            boolean withdraw = own || !Boolean.TRUE.equals(pending.get("eligible"));
            var state = new LinkedHashMap<String, Object>();
            state.put("action", pending.get("action"));
            state.put("canWithdraw", withdraw);
            state.put("canOpen", own);
            if (withdraw) state.put("id", pending.get("id"));
            result.put("pendingReview", state);
        });
        return result;
    }

    @Transactional
    public Map<String, Object> create(Actor request, Map<String, Object> body, String key) {
        Actor actor = admin(request, true);
        Db.fields(body, "customerId", "kind", "title", "businessDate", "ownerId", "participants");
        String customer = DeliveryPolicy.text(body, "customerId", 128);
        var draft = DeliveryPolicy.draft(body);
        validateKey(key);
        repo.lockKey(actor, key);
        String hash = repo.hash(List.of("CREATE", customer, new TreeMap<>(draft.snapshot())));
        return repo.replay(actor, key, hash).orElseGet(() -> {
            repo.customer(actor, customer, true);
            repo.validateEmployees(actor, draft);
            String id = Db.id();
            repo.insert(actor, id, customer, draft);
            repo.auditCreate(actor, id, repo.get(actor, id, false));
            var receipt = Map.<String, Object>of("id", id, "version", 1);
            repo.receipt(actor, key, hash, receipt);
            return receipt;
        });
    }

    @Transactional
    public Map<String, Object> submit(Actor request, String id, Map<String, Object> body, String key) {
        Actor actor = admin(request, true);
        String action = DeliveryPolicy.action(body);
        String reason = DeliveryPolicy.text(body, "reason", 500);
        int version = Db.version(body);
        var draft = "EDIT".equals(action) ? DeliveryPolicy.draft(body) : null;
        validateKey(key);
        Map<String, Object> normalized = draft == null ? Map.of() : new TreeMap<>(draft.snapshot());
        String hash = repo.hash(List.of("CHANGE", id, action, version, reason, normalized));
        repo.lockKey(actor, key);
        return repo.replay(actor, key, hash).orElseGet(() -> {
            var current = repo.get(actor, id, true);
            if (!Objects.equals(version, current.get("version"))) throw ApiError.conflict();
            if (repo.pending(actor, id).isPresent()) {
                throw new ApiError(409, "DELIVERY_REVIEW_PENDING", "该记录已有待审申请");
            }
            DeliveryPolicy.transition(action, current);
            repo.customer(actor, Db.str(current, "customerId"), true);
            var candidate = new LinkedHashMap<>(current);
            if (draft != null) {
                DeliveryPolicy.validateEdit(draft, current);
                repo.validateEmployees(actor, draft);
                candidate.putAll(normalized);
                candidate.remove("ownerName");
                candidate.remove("participantDetails");
            } else {
                candidate.put("activityStatus", action.equals("END_ACTIVITY") ? "ENDED" : current.get("activityStatus"));
                candidate.put("deliveryStatus", action.equals("CONFIRM_DELIVERY") ? "DELIVERED" : current.get("deliveryStatus"));
            }
            candidate.put("action", action);
            var review = reviews.create(actor, ReviewPolicy.OFFLINE_DELIVERY, id, version, current, candidate, reason);
            var receipt = Map.<String, Object>of("id", id, "reviewId", review.get("id"), "version", version, "status", "PENDING");
            repo.receipt(actor, key, hash, receipt);
            return receipt;
        });
    }

    private static void validateKey(String key) {
        if (key == null || !key.matches("[A-Za-z0-9:_.-]{1,128}")) {
            throw ApiError.bad("INVALID_IDEMPOTENCY_KEY", "需要1–128位Idempotency-Key");
        }
    }
}
