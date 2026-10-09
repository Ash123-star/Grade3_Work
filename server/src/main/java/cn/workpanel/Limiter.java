package cn.workpanel;

import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.script.DefaultRedisScript;
import org.springframework.stereotype.Component;
import java.util.List;

/** Redis 固定窗口限流器。Redis 不可用时显式返回服务不可用。 */
@Component
public class Limiter {
    final StringRedisTemplate redis;
    public Limiter(StringRedisTemplate redis) { this.redis=redis; }
    public void check(String key,long limit,long seconds) {
        try {
            Long n=redis.execute(new DefaultRedisScript<>("local n=redis.call('INCR',KEYS[1]); if n==1 then redis.call('EXPIRE',KEYS[1],ARGV[1]) end; return n",Long.class),List.of("workpanel:"+key),String.valueOf(seconds));
            if(n!=null&&n>limit) throw new ApiError(429,"RATE_LIMITED","请求过于频繁");
        } catch(ApiError e) { throw e; } catch(Exception e) { throw new ApiError(503,"LIMITER_UNAVAILABLE","限流服务不可用"); }
    }
}
