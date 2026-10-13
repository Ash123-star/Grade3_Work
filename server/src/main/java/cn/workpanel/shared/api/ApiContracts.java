package cn.workpanel.shared.api;

import java.util.List;
import java.util.Map;

/** 公共 HTTP 契约类型。业务模块只能依赖这些稳定类型，不能依赖其他模块的数据库行结构。 */
public final class ApiContracts {
    private ApiContracts() { }

    /** 统一分页返回字段，兼容现有 items、total、nextCursor 协议。 */
    public record PageResponse<T>(List<T> items, long total, String nextCursor) { }

    /** 统一错误响应字段；traceId 用于从客户端追踪到服务端日志。 */
    public record ErrorResponse(String code, String message, String traceId) { }

    /** 版本化命令的公共字段；更新使用当前版本，创建使用 0。 */
    public record VersionCommand(int version, String idempotencyKey, Map<String, Object> attributes) { }
}
