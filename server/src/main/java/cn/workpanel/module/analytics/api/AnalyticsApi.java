package cn.workpanel.module.analytics.api;

import cn.workpanel.contract.ActorContext;
import java.util.Map;

/** 分析查询端口；统计和导出必须复用详情查询的数据范围。 */
public interface AnalyticsApi {
    /** 按业务日期和周期返回指标、分子、分母、口径和更新时间。 */
    Map<String, Object> statistics(ActorContext actor, Map<String, Object> query);

    /** 导出当前范围内资源；实现负责 CSV 公式注入转义和上限控制。 */
    String export(ActorContext actor, Map<String, Object> query);
}
