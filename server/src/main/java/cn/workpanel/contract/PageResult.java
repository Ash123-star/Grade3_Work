package cn.workpanel.contract;

import java.util.List;

/** 公共分页返回契约，避免各模块定义不同的列表字段。 */
public record PageResult<T>(List<T> items, long total, String nextCursor) {
    public PageResult { items = items == null ? List.of() : List.copyOf(items); }
}
