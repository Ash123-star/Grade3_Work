package cn.workpanel.module.push.application;
import java.time.Instant;
/** Provider acceptance is not a device delivery receipt. No implementation may log credentials or payloads. */
public interface PushGateway {
    boolean configured();
    String send(String device,String notification,String binding,String category,String title,Instant expires) throws Failure;
    final class Failure extends Exception {
        public final String code; public final boolean retryable;
        public Failure(String code,boolean retryable) { super("推送供应商暂不可用"); this.code=code; this.retryable=retryable; }
    }
}
