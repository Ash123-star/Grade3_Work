package cn.workpanel.module.delivery.application;

import cn.workpanel.*;
import cn.workpanel.contract.ActorContext;
import cn.workpanel.module.delivery.domain.DeliveryPolicy;
import cn.workpanel.module.delivery.infrastructure.DeliveryRepository;
import cn.workpanel.module.review.api.ReviewActors;
import cn.workpanel.module.review.api.ReviewedRevisionApplication;
import cn.workpanel.module.review.domain.ReviewPolicy;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import java.util.*;

@Service
public class DeliveryReviewedRevision implements ReviewedRevisionApplication {
    private final DeliveryRepository repo;

    public DeliveryReviewedRevision(DeliveryRepository repo) { this.repo = repo; }

    @Override public Set<String> kinds() { return Set.of(ReviewPolicy.OFFLINE_DELIVERY); }

    @Override @Transactional(propagation = Propagation.MANDATORY)
    public void apply(String kind, ActorContext applicantContext, ActorContext approverContext, String id,
                      int version, Map<String, Object> candidate, String reason) {
        Actor applicant = ReviewActors.actor(applicantContext);
        Actor approver = ReviewActors.actor(approverContext);
        if (!applicant.company().equals(approver.company()) || applicant.id().equals(approver.id())) throw ApiError.forbidden();
        for (Actor actor : List.of(applicant, approver).stream().sorted(Comparator.comparing(Actor::id)).toList()) {
            DeliveryPolicy.requireAdmin(repo.actor(actor, true));
        }
        var current = repo.get(applicant, id, true);
        if (!Objects.equals(version, current.get("version"))) throw ApiError.conflict();
        repo.customer(applicant, Db.str(current, "customerId"), true);
        String action = Db.str(candidate, "action");
        DeliveryPolicy.transition(action, current);
        if (action.equals("EDIT")) {
            var draft = DeliveryPolicy.draft(candidate);
            DeliveryPolicy.validateEdit(draft, current);
            repo.validateEmployees(applicant, draft);
            repo.edit(applicant, id, version, draft);
        } else {
            repo.advance(applicant, id, version, action.equals("END_ACTIVITY"));
        }
    }
}
