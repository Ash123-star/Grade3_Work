package cn.workpanel.module.log.api;

import cn.workpanel.contract.ActorContext;
import java.util.Map;

/** 日志模块公共接口；草稿隐私和上海业务日期规则由模块内部保证。 */
public interface LogApi {
    /** 按业务日期保存本人草稿；同一用户同一天只能有一份主日报，草稿仅本人可见且更新必须携带版本。 */
    Map<String, Object> saveDraft(ActorContext actor, Map<String, Object> command);

    /** 提交日报并记录提交时间和历史版本；提交后上级才能按范围读取，旧版本不得覆盖。 */
    Map<String, Object> submit(ActorContext actor, String logId, int version);

    /** 查询本人或授权下属的已提交日志；下属入口仅管理者可用，且不得返回未提交草稿或私人备注。 */
    Map<String, Object> list(ActorContext actor, Map<String, Object> query);
}
