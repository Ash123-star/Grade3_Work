package cn.workpanel.module.auth.application;

import cn.workpanel.contract.ActorContext;
import cn.workpanel.module.auth.api.AuthApi;
import java.util.Map;

/**
 * 认证用例服务契约。HTTP 适配器通过该边界调用认证用例，数据库和会话实现由基础设施提供。
 */
public interface AuthApplicationService extends AuthApi {
    /** 修改当前用户密码并撤销旧会话；要求旧密码正确且新密码满足策略。 */
    Map<String, Object> changePassword(ActorContext actor, Map<String, Object> command);

    /** 撤销当前会话；操作具有幂等语义。 */
    Map<String, Object> logout(ActorContext actor);
}
