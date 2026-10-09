package cn.workpanel.module.organization.api;

import cn.workpanel.contract.ActorContext;
import java.util.Map;

/** 组织查询和变更的模块边界；人员、团队和部门内部存储不能泄漏给其他模块。 */
public interface OrganizationApi {
    /** 返回当前用户授权范围内的组织树。 */
    Map<String, Object> tree(ActorContext actor);

    /** 分页搜索当前用户可见人员；dispatch=true 时还必须具备派发资格。 */
    Map<String, Object> people(ActorContext actor, String search, boolean dispatch, int cursor, int limit);

    /** 提交组织或人员候选变更；最终生效由审核模块完成。 */
    Map<String, Object> submitRevision(ActorContext actor, Map<String, Object> command);
}
