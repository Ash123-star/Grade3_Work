package cn.workpanel.module.review.api;
import cn.workpanel.Actor;
import cn.workpanel.contract.ActorContext;
import java.util.Set;

/** 内部审核事务中的身份契约适配；调用前必须已重新读取服务端身份。 */
public final class ReviewActors {
    private ReviewActors() {}
    public static ActorContext context(Actor a) { return new ActorContext(a.id(),a.company(),a.role(),a.department(),a.team(),a.status().equals("ACTIVE"),a.dispatch(),a.reviewer(),Set.of()); }
    public static Actor actor(ActorContext a) { return new Actor(a.userId(),a.companyId(),a.role(),a.departmentId(),a.teamId(),a.dispatchEnabled(),a.companyReviewer(),false,a.active()?"ACTIVE":"PENDING"); }
}
