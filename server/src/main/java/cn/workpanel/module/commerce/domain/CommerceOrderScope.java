package cn.workpanel.module.commerce.domain;

import cn.workpanel.module.commerce.domain.CommerceImport.OrderStatus;

import java.time.Instant;

/** 已校验并解析客户绑定后的订单筛选。公司由认证上下文提供。 */
public record CommerceOrderScope(Instant from, Instant toExclusive, String externalMemberId,
                                 String externalOrderId, OrderStatus status, String currency) {}
