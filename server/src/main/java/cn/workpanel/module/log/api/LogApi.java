package cn.workpanel.module.log.api;

import cn.workpanel.contract.ActorContext;
import java.util.Map;

/** 日志模块公共接口；草稿隐私和上海业务日期规则由模块内部保证。 */
public interface LogApi {
    /** 按业务日期保存本人草稿；同一用户同一天只能有一份主日报。 */
    Map<String, Object> saveDraft(ActorContext actor, Map<String, Object> command);

    /** 提交日报并记录提交时间；提交后上级才能按范围读取。 */
    Map<String, Object> submit(ActorContext actor, String logId, int version);

    /** 查询本人或授权下属的已提交日志；不得返回未提交草稿或私人备注。 */
    Map<String, Object> list(ActorContext actor, Map<String, Object> query);
}
