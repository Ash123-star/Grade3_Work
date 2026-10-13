package cn.workpanel.module.ai.api;

import cn.workpanel.contract.ActorContext;
import java.util.Map;

/** AI 应用边界；模型只能生成带来源草稿，不能直接写业务数据。 */
public interface AiApi {
    /** 创建 AI 异步任务；输入必须先经过当前用户范围和敏感字段过滤。 */
    Map<String, Object> createJob(ActorContext actor, Map<String, Object> command);

    /** 编辑带版本的 AI 草稿；来源失权或版本冲突时拒绝更新。 */
    Map<String, Object> updateDraft(ActorContext actor, String jobId, Map<String, Object> command);

    /** 人工确认后进入普通任务派发用例；必须携带幂等键并再次校验权限。 */
    Map<String, Object> confirmTask(ActorContext actor, String jobId, Map<String, Object> command, String idempotencyKey);
}
