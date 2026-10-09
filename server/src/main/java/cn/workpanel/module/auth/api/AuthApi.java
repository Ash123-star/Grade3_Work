package cn.workpanel.module.auth.api;

import cn.workpanel.contract.ActorContext;
import java.util.Map;

/**
 * 认证模块的应用边界。HTTP Controller 只负责把请求映射到这些用例，不直接操作数据库。
 */
public interface AuthApi {
    /** 注册待确认员工；请求不得包含 role，返回用户标识和归属审核标识。 */
    Map<String, Object> register(Map<String, Object> command);

    /** 使用账号和密码创建会话；密码错误、停用账号和限流由实现映射为统一错误。 */
    Map<String, Object> login(Map<String, Object> command);

    /** 返回当前用户公开资料；不得包含密码、手机号或私人备注。 */
    Map<String, Object> current(ActorContext actor);
}
