package cn.workpanel.contract;

/** 公共分页查询参数；cursor 使用当前 API 的偏移量语义，limit 由应用层限制在 1 到 100。 */
public record PageQuery(int cursor, int limit) {
    public PageQuery {
        if (cursor < 0 || limit < 1 || limit > 100) throw new IllegalArgumentException("invalid page");
    }
}
