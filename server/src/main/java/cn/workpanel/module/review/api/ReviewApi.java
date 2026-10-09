package cn.workpanel.module.review.api;

import cn.workpanel.contract.ActorContext;
import java.util.Map;

/** 审核模块公共接口；其他模块通过该接口提交候选，不直接操作审核表。 */
public interface ReviewApi {
    /** 创建候选审核请求；实现负责生成分层审核步骤并通知审核人。 */
    Map<String, Object> create(ActorContext actor, Map<String, Object> command);

    /** 读取申请人或当前审核步骤可见的审核详情。 */
    Map<String, Object> get(ActorContext actor, String reviewId);

    /** 通过或驳回审核；申请人不得自审，驳回必须有原因。 */
    Map<String, Object> decide(ActorContext actor, String reviewId, boolean approve, String reason);
}
