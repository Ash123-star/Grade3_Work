package cn.workpanel.module.task.api;

import cn.workpanel.contract.ActorContext;
import java.util.Map;

/** 任务模块公共接口；调用方不得直接依赖 tasks 表或任务 Controller。 */
public interface TaskApi {
    /** 按当前公司和组织范围分页查询正式任务；显式投影包含只读phase和真实dispatchAt、参与人和标签，不返回正文或事件。phase来自已生效流转，缺失/未知不得猜测；GET只读、无幂等键，参数/越权错误沿用统一模型。 */
    Map<String, Object> list(ActorContext actor, Map<String, Object> query);

    /** 获取任务详情及事件时间线；越权资源应映射为统一资源错误。 */
    Map<String, Object> get(ActorContext actor, String taskId);

    /** 提交任务创建申请；校验派发资格、参与人集合、幂等键和跨公司隔离。返回TASK_CREATE审核，id为审核ID，target_id为任务ID；仅APPROVED时任务已生效。 */
    Map<String, Object> create(ActorContext actor, Map<String, Object> command, String idempotencyKey);

    /** 追加任务生命周期事件；实现负责校验当前阶段和操作者权限。 */
    Map<String, Object> appendEvent(ActorContext actor, String taskId, Map<String, Object> command);

    /** 提交任务关键字段修订；版本冲突或需要审核时不得直接覆盖生效值。 */
    Map<String, Object> revise(ActorContext actor, String taskId, Map<String, Object> command);

    /** 提交转派复核申请；通过前不得改变负责人、参与人或任务状态。 */
    Map<String, Object> requestReassignment(ActorContext actor, String taskId, Map<String, Object> command);

    /** 提交改期复核申请；通过前不得改变截止时间或任务状态。 */
    Map<String, Object> requestReschedule(ActorContext actor, String taskId, Map<String, Object> command);

    /** 日期平移专用模式；与 HTTP 同用例，同键/同约束版本返回原审核，禁止整份候选。 */
    default Map<String,Object> requestReschedule(ActorContext actor,String taskId,Map<String,Object> command,String key,String revision) {
        throw new UnsupportedOperationException("Task movement is unavailable");
    }
}
