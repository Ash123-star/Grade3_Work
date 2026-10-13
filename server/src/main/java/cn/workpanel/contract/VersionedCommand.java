package cn.workpanel.contract;

/**
 * 带乐观锁版本的写命令。创建记录使用 version=0，更新记录必须携带客户端读取到的当前版本。
 */
public record VersionedCommand(int version, String idempotencyKey) {
    public VersionedCommand {
        if (version < 0) throw new IllegalArgumentException("version must be non-negative");
    }
}
