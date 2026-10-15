package cn.workpanel.module.review.api;
import cn.workpanel.contract.ActorContext;
import java.util.Map;
import java.util.Set;

/** 已全部独立审核通过的最终应用边界。调用方持有审核锁，传入重新读取的身份。
 * 实现必须加入同一事务，重新校验业务状态和版本；异常整体回滚，禁止创建新的申请代替应用。
 * 权限不足403、版本冲突409、无效输入400；不得重复写入事件。 */
public interface ReviewedRevisionApplication {
    Set<String> kinds();
    void apply(String kind,ActorContext applicant,ActorContext approver,String targetId,int expectedVersion,Map<String,Object> candidate,String reason);
}
