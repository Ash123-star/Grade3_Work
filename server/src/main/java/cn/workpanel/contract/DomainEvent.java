package cn.workpanel.contract;

import java.time.Instant;
import java.util.Map;

/** 跨模块领域事件；事件消费者不得反向调用发布模块的 Controller。 */
public record DomainEvent(String type, String companyId, String actorId, String objectId,
                         Instant occurredAt, Map<String, Object> attributes) {
    public DomainEvent {
        attributes = attributes == null ? Map.of() : Map.copyOf(attributes);
    }
}
