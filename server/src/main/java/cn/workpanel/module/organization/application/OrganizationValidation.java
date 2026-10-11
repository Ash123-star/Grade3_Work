package cn.workpanel.module.organization.application;

import cn.workpanel.Db;
import cn.workpanel.module.organization.domain.OrganizationPolicy;
import cn.workpanel.module.organization.infrastructure.OrganizationRepository;
import org.springframework.stereotype.Component;
import java.util.*;

/** 组织候选创建与最终应用共用的验证；调用方必须处于事务中。 */
@Component
public class OrganizationValidation {
    private final OrganizationRepository repository;
    public OrganizationValidation(OrganizationRepository repository) { this.repository = repository; }
    public void user(String company, String id, Map<String, Object> candidate) {
        repository.lockCompany(company);
        OrganizationPolicy.userFields(candidate);
        if (!Db.str(candidate, "departmentId").isBlank()) repository.department(Db.str(candidate, "departmentId"), company);
        if (!Db.str(candidate, "teamId").isBlank()) repository.team(Db.str(candidate, "teamId"), company, candidate.get("departmentId"));
        String manager = Db.str(candidate, "managerId"); var seen = new HashSet<String>(); seen.add(id);
        while (!manager.isBlank()) {
            OrganizationPolicy.reportingNode(seen, manager);
            repository.activeManager(manager, company);
            manager = repository.manager(manager);
        }
        OrganizationPolicy.lastAdministrator(candidate, repository.otherAdministrators(company, id));
    }
    /** 兼容旧 review 调用点，规则与查询仍由组织模块维护。 */
    public static void validateUser(Db db, String company, String id, Map<String, Object> candidate) {
        new OrganizationValidation(new OrganizationRepository(db)).user(company, id, candidate);
    }
}
