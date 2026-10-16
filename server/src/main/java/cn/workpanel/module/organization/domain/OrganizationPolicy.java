package cn.workpanel.module.organization.domain;

import cn.workpanel.ApiError;
import cn.workpanel.Db;
import java.util.*;

/** 组织纯规则；组织存在性与并发锁由应用验证器提供。 */
public final class OrganizationPolicy {
    private OrganizationPolicy() { }
    public static void userFields(Map<String, Object> candidate) {
        String role = Db.required(candidate, "role"), status = Db.required(candidate, "status");
        if (!Set.of("ADMIN", "FOUNDER", "DIRECTOR", "LEADER", "EMPLOYEE").contains(role) || !Set.of("ACTIVE", "DISABLED").contains(status))
            throw ApiError.bad("INVALID_ROLE", "角色或状态无效");
        Db.required(candidate, "name");
        if (!(candidate.get("dispatchEnabled") instanceof Boolean) || !(candidate.get("companyReviewer") instanceof Boolean))
            throw ApiError.bad("INVALID_PERMISSION", "权限开关必须为布尔值");
        for (String key : List.of("departmentId", "teamId", "managerId"))
            if (candidate.get(key) != null && !(candidate.get(key) instanceof String)) throw ApiError.bad("INVALID_FIELD", "需要文本字段: " + key);
        if (role.equals("DIRECTOR") && Db.str(candidate, "departmentId").isBlank() || role.equals("LEADER") && Db.str(candidate, "teamId").isBlank())
            throw ApiError.bad("MISSING_ORGANIZATION", "管理角色需配置对应部门/团队");
    }
    public static void reportingNode(Set<String> seen, String manager) {
        if (!seen.add(manager)) throw ApiError.bad("REPORTING_CYCLE", "禁止循环汇报关系");
    }
    public static void lastAdministrator(Map<String, Object> candidate, long otherAdministrators) {
        if ((!candidate.get("role").equals("ADMIN") || !candidate.get("status").equals("ACTIVE")) && otherAdministrators == 0)
            throw ApiError.bad("LAST_ADMIN", "不能停用或降级最后一个管理员");
    }
}
