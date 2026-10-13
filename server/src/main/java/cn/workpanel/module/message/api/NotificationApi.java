package cn.workpanel.module.message.api;

import cn.workpanel.contract.ActorContext;
import java.util.Map;

/** 消息查询端口；业务模块发布事件，不直接调用通知 Controller。 */
public interface NotificationApi {
    /** 分页读取当前用户通知并返回未读数。 */
    Map<String, Object> list(ActorContext actor, Map<String, Object> query);

    /** 将当前用户全部通知标记为已读；操作应具备幂等性。 */
    void markAllRead(ActorContext actor);
}
