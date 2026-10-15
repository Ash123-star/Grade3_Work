package cn.workpanel.module.task.api;

import cn.workpanel.contract.ActorContext;
import java.util.Map;

/** 任务模块公共接口；调用方不得直接依赖 tasks 表或任务 Controller。 */
public interface TaskApi {
    /** 按当前数据范围分页查询任务；列表只含 id、负责人、派发人、标题、截止时间、版本、创建时间，不得包含完成或状态字段。 */
    Map<String, Object> list(ActorContext actor, Map<String, Object> query);

    /** 获取任务详情及事件时间线；越权资源应映射为统一资源错误。 */
    Map<String, Object> get(ActorContext actor, String taskId);

    /** 创建任务；必须校验派发资格、一个主负责人、幂等键和跨公司隔离。 */
    Map<String, Object> create(ActorContext actor, Map<String, Object> command, String idempotencyKey);

    /** 追加任务生命周期事件；实现负责校验当前阶段和操作者权限。 */
    Map<String, Object> appendEvent(ActorContext actor, String taskId, Map<String, Object> command);

    /** 提交任务关键字段修订；版本冲突或需要审核时不得直接覆盖生效值。 */
    Map<String, Object> revise(ActorContext actor, String taskId, Map<String, Object> command);

    /** 提交转派复核申请；通过前不得改变负责人、参与人或任务状态。 */
    Map<String, Object> requestReassignment(ActorContext actor, String taskId, Map<String, Object> command);

    /** 提交改期复核申请；通过前不得改变截止时间或任务状态。 */
    Map<String, Object> requestReschedule(ActorContext actor, String taskId, Map<String, Object> command);
}
