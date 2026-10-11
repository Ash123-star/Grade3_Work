package cn.workpanel.module.organization.application;

import cn.workpanel.*;
import cn.workpanel.contract.ActorContext;
import cn.workpanel.module.organization.api.OrganizationApi;
import cn.workpanel.module.organization.infrastructure.OrganizationRepository;
import cn.workpanel.module.review.application.ReviewApplicationService;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.util.*;

/** 组织查询和候选变更用例；有效修改仍由审核事务应用。 */
@Service
public class OrganizationApplicationService implements OrganizationApi {
    private final OrganizationRepository repository;
    private final OrganizationValidation validation;
    private final ReviewApplicationService reviews;
    public OrganizationApplicationService(OrganizationRepository repository, OrganizationValidation validation, ReviewApplicationService reviews) {
        this.repository = repository; this.validation = validation; this.reviews = reviews;
    }
    @Override public Map<String, Object> tree(ActorContext context) { return tree(actor(context)); }
    @Override public Map<String, Object> people(ActorContext context, String search, boolean dispatch, int cursor, int limit) { return people(actor(context), search, dispatch, cursor, limit); }
    @Override @Transactional public Map<String, Object> submitRevision(ActorContext context, Map<String, Object> command) {
        String kind = Db.required(command, "kind"), id = Db.str(command, "id");
        var body = new LinkedHashMap<>(command); body.remove("kind");
        if (kind.equals("USER")) { body.remove("id"); return revise(actor(context), id, body); }
        return unit(actor(context), kind, body);
    }
    private Actor actor(ActorContext context) { return Actor.from(repository.user(context.userId(), context.companyId())); }
    private static void requireActive(Actor actor) {
        if (!actor.status().equals("ACTIVE")) throw new ApiError(403, "MEMBERSHIP_PENDING", "部门归属尚未确认");
        if (actor.mustChange()) throw new ApiError(403, "PASSWORD_CHANGE_REQUIRED", "首次登录请修改密码");
    }
    public Map<String, Object> tree(Actor actor) {
        requireActive(actor);
        // 保留既有 users 分页对象形状；树请求返回完整授权范围，不沿用默认100人截断。
        var users = repository.people(actor, "", false, 0, Integer.MAX_VALUE);
        return Map.of("departments", repository.treeDepartments(actor), "teams", repository.treeTeams(actor), "users", users);
    }
    public List<Map<String, Object>> departments(Actor actor) { requireActive(actor); return repository.departments(actor.company()); }
    public Map<String, Object> people(Actor actor, String search, boolean dispatch, int cursor, int limit) {
        requireActive(actor); Business.page(cursor, limit); if (dispatch) actor.requireDispatch();
        return repository.people(actor, search, dispatch, cursor, limit);
    }
    @Transactional public Map<String, Object> membership(Actor actor, Map<String, Object> body) {
        Db.fields(body, "departmentId", "version", "reason");
        if (!actor.status().equals("PENDING")) throw ApiError.conflict();
        String department = Db.required(body, "departmentId"); repository.department(department, actor.company());
        if (repository.pendingMembership(actor.id()) > 0) throw ApiError.conflict();
        return reviews.create(actor, "MEMBERSHIP", actor.id(), Db.version(body), Map.of("status", "PENDING", "departmentId", actor.department()), Map.of("status", "ACTIVE", "departmentId", department), Db.required(body, "reason"));
    }
    public Map<String, Object> policy(Actor actor) { requireActive(actor); actor.requireAdmin(); return repository.policy(actor.company()); }
    @Transactional public Map<String, Object> policyRevision(Actor actor, Map<String, Object> body) {
        requireActive(actor); actor.requireAdmin(); Db.fields(body, "version", "reason", "taskTeamReview", "taskDepartmentReview");
        var candidate = new LinkedHashMap<>(repository.policyValues(actor.company())); var before = new LinkedHashMap<>(candidate);
        for (String key : List.of("taskTeamReview", "taskDepartmentReview")) if (body.containsKey(key)) {
            if (!(body.get(key) instanceof Boolean)) throw ApiError.bad("INVALID_POLICY", "复核策略必须为布尔值");
            candidate.put(key, body.get(key));
        }
        return reviews.create(actor, "POLICY", actor.company(), Db.version(body), before, candidate, Db.required(body, "reason"));
    }
    @Transactional public Map<String, Object> reviewer(Actor actor, Map<String, Object> body) {
        requireActive(actor); Db.fields(body, "reason", "version"); if (actor.reviewer()) throw ApiError.conflict();
        var user = repository.user(actor.id(), actor.company());
        return reviews.create(actor, "REVIEWER", actor.id(), Db.version(body), Map.of("companyReviewer", user.get("company_reviewer")), Map.of("companyReviewer", true), Db.required(body, "reason"));
    }
    @Transactional public Map<String, Object> revise(Actor actor, String id, Map<String, Object> body) {
        requireActive(actor); actor.requireAdmin(); Db.fields(body, "version", "reason", "name", "departmentId", "teamId", "role", "status", "dispatchEnabled", "companyReviewer", "managerId");
        var old = repository.user(id, actor.company()); var candidate = new LinkedHashMap<String, Object>();
        candidate.put("name", old.get("name")); candidate.put("departmentId", Db.str(old, "department_id")); candidate.put("teamId", Db.str(old, "team_id"));
        candidate.put("role", old.get("role")); candidate.put("status", old.get("status")); candidate.put("dispatchEnabled", old.get("dispatch_enabled"));
        candidate.put("companyReviewer", old.get("company_reviewer")); candidate.put("managerId", repository.manager(id));
        var before = new LinkedHashMap<>(candidate);
        for (String key : candidate.keySet()) if (body.containsKey(key)) candidate.put(key, body.get(key));
        validation.user(actor.company(), id, candidate);
        return reviews.create(actor, "USER", id, Db.version(body), before, candidate, Db.required(body, "reason"));
    }
    @Transactional public Map<String, Object> unit(Actor actor, String kind, Map<String, Object> body) {
        requireActive(actor); actor.requireAdmin(); Db.fields(body, "id", "name", "departmentId", "version", "reason");
        if (!Set.of("departments", "teams").contains(kind)) throw ApiError.notFound();
        String id = Db.str(body, "id"); int version = Db.version(body); Object before = Map.of();
        if (id.isBlank()) { if (version != 0) throw ApiError.conflict(); id = Db.id(); } else before = repository.unit(kind, id, actor.company());
        var candidate = new LinkedHashMap<String, Object>(); candidate.put("name", Db.required(body, "name"));
        if (kind.equals("teams")) { String department = Db.required(body, "departmentId"); repository.department(department, actor.company()); candidate.put("departmentId", department); }
        return reviews.create(actor, kind.equals("teams") ? "TEAM" : "DEPARTMENT", id, version, before, candidate, Db.required(body, "reason"));
    }
    public Map<String, Object> audit(Actor actor, int cursor, int limit) { requireActive(actor); actor.requireAdmin(); Business.page(cursor, limit); return repository.audit(actor.company(), cursor, limit); }
}
