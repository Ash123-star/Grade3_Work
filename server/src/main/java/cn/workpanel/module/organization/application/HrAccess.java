package cn.workpanel.module.organization.application;

import cn.workpanel.Actor;
import cn.workpanel.ApiError;
import cn.workpanel.module.organization.infrastructure.HrRepository;
import cn.workpanel.shared.application.CurrentActors;
import org.springframework.stereotype.Service;

/** 公司级显式人事权限；岗位、直属上级与上传者身份均不授予合同权限。 */
@Service
public class HrAccess {
    private final HrRepository repo;
    private final CurrentActors actors;

    public HrAccess(HrRepository repo, CurrentActors actors) {
        this.repo = repo;
        this.actors = actors;
    }

    public Actor require(Actor request, boolean write) {
        Actor actor = actors.fresh(request);
        if (!allowed(actor.company(), actor.id(), write)) throw ApiError.forbidden();
        return actor;
    }

    public boolean allowed(String company, String user, boolean write) {
        return repo.allowed(company, user, write);
    }

    public boolean isContract(String attachment) {
        return repo.isContractAttachment(attachment);
    }

    public void attachment(Actor actor, String id) {
        require(actor, false);
        repo.requireCompanyAttachment(actor.company(), id);
    }
}
