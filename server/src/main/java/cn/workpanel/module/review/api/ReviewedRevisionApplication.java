package cn.workpanel.module.review.api;

import cn.workpanel.contract.ActorContext;
import java.util.Map;

/**
 * 待 C/E 接入的受审核业务应用边界；该接口定义本身不代表已完成跨模块替换。
 * 实现必须参与调用方本地事务，对当前权限/状态与 expectedVersion 重新验证，
 * 业务值、历史版本、审计及事务 outbox 原子一致；失败抛出统一业务错误且不产生部分写入。
 */
public interface ReviewedRevisionApplication {
    /** 返回唯一支持的候选 kind，例如 TASK 或 LOG；不能由客户端选择任意实现。 */
    String kind();
    /** 全部独立审核完成后应用一次候选；版本冲突409、越权403、无效输入400，重试不能重复写入。 */
    void apply(ActorContext applicant, ActorContext approver, String targetId, int expectedVersion, Map<String, Object> candidate);
}
