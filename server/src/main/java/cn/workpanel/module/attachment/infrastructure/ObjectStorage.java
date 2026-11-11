package cn.workpanel.module.attachment.infrastructure;

/** 私有对象端口；调用方在读取前鉴权，不向客户端暴露Key或凭据。 */
public interface ObjectStorage {
    /** 写入配置前缀下的私有对象；同Key重试覆盖同一对象，失败映射为安全的存储异常。 */
    void put(String key, byte[] bytes, String contentType);
    /** 调用方先完成业务鉴权；读取不得超过上限，长度与哈希由应用层继续核对。 */
    byte[] get(String key, long maximumBytes);
    /** 幂等删除对象；调用方通过持久化任务记录失败，稍后重新执行。 */
    void delete(String key);
    /** 从相对路径构造受控Key，拒绝越出配置前缀的路径，不接受客户端任意对象地址。 */
    String key(String relative);
}
