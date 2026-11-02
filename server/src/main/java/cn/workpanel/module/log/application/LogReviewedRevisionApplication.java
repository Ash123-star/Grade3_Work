package cn.workpanel.module.log.application;

import cn.workpanel.*;
import cn.workpanel.contract.ActorContext;
import cn.workpanel.module.review.api.ReviewedRevisionApplication;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.*;
import java.util.*;

/** 保留历史LOG类型注册以读取审计；正文候选不再允许应用，避免绕过直接更新的作者/时间窗口。 */
@Service
public class LogReviewedRevisionApplication implements ReviewedRevisionApplication {
    public LogReviewedRevisionApplication(Db db) { }
    public Set<String> kinds() { return Set.of("LOG"); }
    @Transactional(propagation=Propagation.MANDATORY)
    public void apply(String kind,ActorContext applicant,ActorContext approver,String target,int version,Map<String,Object> candidate,String reason) {
        throw new ApiError(409,"DIRECT_CONTENT_REQUIRED","历史日报审核候选已停用，请在24小时窗口内直接修改正文");
    }
}