package cn.workpanel.contract;

import java.util.Set;

/**
 * 跨模块身份上下文。它只携带已认证用户的稳定身份和权限快照，禁止携带数据库行或 HTTP 对象。
 */
public record ActorContext(String userId, String companyId, String role, String departmentId,
                           String teamId, boolean active, boolean dispatchEnabled,
                           boolean companyReviewer, Set<String> permissions) {
    public ActorContext {
        permissions = permissions == null ? Set.of() : Set.copyOf(permissions);
    }
}
