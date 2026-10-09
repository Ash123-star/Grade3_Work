package cn.workpanel.shared.domain;

import cn.workpanel.contract.DomainEvent;

/** 跨模块事件端口。发布模块只发布事件，不直接调用通知、统计或 AI 模块的 Controller。 */
public interface DomainEventPublisher {
    /** 在当前事务语义下发布事件；实现负责 outbox 持久化或可靠投递。 */
    void publish(DomainEvent event);
}
