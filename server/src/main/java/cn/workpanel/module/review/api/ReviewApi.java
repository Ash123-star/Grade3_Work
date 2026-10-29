package cn.workpanel.module.review.api;

import cn.workpanel.contract.ActorContext;
import java.util.Map;

/** 审核模块公共接口；其他模块通过该接口提交候选，不直接操作审核表。 */
public interface ReviewApi {
    /** 创建候选申请；直属单级审核，MEMBERSHIP为管理员例外，创始人仅在已有权限内免审。 */
    Map<String, Object> create(ActorContext actor, Map<String, Object> command);

    /** 读取申请人或当前审核步骤可见的审核详情。 */
    Map<String, Object> get(ActorContext actor, String reviewId);

    /**
     * 通过或驳回审核。expectedVersion 必须是决定请求携带的申请版本，不得用数据库当前版本代替；
     * 申请人不得自审，驳回必须有原因；关系失效、状态不符或版本不一致均拒绝。
     */
    Map<String, Object> decide(ActorContext actor, String reviewId, boolean approve, String reason, int expectedVersion);
}
