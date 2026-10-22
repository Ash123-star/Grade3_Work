package cn.workpanel.module.procedure.application;

import cn.workpanel.*;
import cn.workpanel.contract.ActorContext;
import cn.workpanel.module.procedure.infrastructure.ProcedureRepository;
import cn.workpanel.module.procedure.domain.ProcedureDocument;
import cn.workpanel.module.review.api.ReviewedRevisionApplication;
import cn.workpanel.shared.application.CurrentActors;
import org.springframework.stereotype.Component;
import java.util.*;

@Component
public class ProcedureReviewedRevision implements ReviewedRevisionApplication {
    private final ProcedureRepository repo;private final CurrentActors actors;
    public ProcedureReviewedRevision(ProcedureRepository repo,CurrentActors actors){this.repo=repo;this.actors=actors;}
    public Set<String> kinds(){return Set.of("PROCEDURE");}
    public void apply(String kind,ActorContext applicant,ActorContext approver,String id,int expected,Map<String,Object> c,String reason){
        Actor a=actors.fresh(applicant);a.requireAdmin();if(a.id().equals(approver.userId()))throw ApiError.forbidden();
        repo.lockPublication(a);
        var row=repo.document(a,id,true);if(((Number)row.get("version")).intValue()!=expected)throw ApiError.conflict();
        var b=ProcedureDocument.validate(repo.json(repo.revision(a,id,expected).get("body")));repo.publish(a,id,expected,b,Boolean.TRUE.equals(c.get("withdraw")));
    }
}
