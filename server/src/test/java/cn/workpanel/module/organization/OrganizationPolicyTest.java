package cn.workpanel.module.organization;

import cn.workpanel.ApiError;
import cn.workpanel.module.organization.domain.OrganizationPolicy;
import org.junit.jupiter.api.Test;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;

class OrganizationPolicyTest {
    Map<String, Object> candidate() { return new HashMap<>(Map.of("name", "人员", "role", "EMPLOYEE", "status", "ACTIVE", "departmentId", "d", "teamId", "", "managerId", "", "dispatchEnabled", true, "companyReviewer", false)); }
    @Test void rolesStatusPermissionsAndRequiredOrganization() {
        var command = candidate(); assertDoesNotThrow(() -> OrganizationPolicy.userFields(command));
        command.put("role", "ROOT"); assertThrows(ApiError.class, () -> OrganizationPolicy.userFields(command));
        command.put("role", "LEADER"); assertThrows(ApiError.class, () -> OrganizationPolicy.userFields(command));
        command.put("role", "EMPLOYEE"); command.put("status", "PENDING"); assertThrows(ApiError.class, () -> OrganizationPolicy.userFields(command));
        command.put("status", "ACTIVE"); command.put("dispatchEnabled", "true"); assertThrows(ApiError.class, () -> OrganizationPolicy.userFields(command));
    }
    @Test void reportingCycleAndLastAdministrator() {
        Set<String> seen = new HashSet<>(Set.of("self"));
        OrganizationPolicy.reportingNode(seen, "manager");
        assertThrows(ApiError.class, () -> OrganizationPolicy.reportingNode(seen, "self"));
        var command = candidate();
        assertThrows(ApiError.class, () -> OrganizationPolicy.lastAdministrator(command, 0));
        assertDoesNotThrow(() -> OrganizationPolicy.lastAdministrator(command, 1));
        command.put("role", "ADMIN"); assertDoesNotThrow(() -> OrganizationPolicy.lastAdministrator(command, 0));
        command.put("status", "DISABLED"); assertThrows(ApiError.class, () -> OrganizationPolicy.lastAdministrator(command, 0));
    }
}
