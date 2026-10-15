package cn.workpanel;

import cn.workpanel.module.ai.application.AiApplicationService;
import cn.workpanel.module.review.application.ReviewApplicationService;

import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import java.net.URI;
import java.net.http.*;
import java.nio.charset.StandardCharsets;
import java.time.*;
import java.util.*;

/** 模型只返回 JSON 文本；预算和输出含义由业务层控制。 */
@Service
public class MemoryModel {
    final Db db; final Memory memory; final TransactionTemplate tx;
    final org.springframework.data.redis.core.StringRedisTemplate redis;
    final Limiter limiter;
    final String key,url,model;
    final int daily,maxTokens,timeout;
    final HttpClient http=HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10)).build();
    MemoryModel(Db db,Memory memory,PlatformTransactionManager manager,
        org.springframework.data.redis.core.StringRedisTemplate redis,Limiter limiter,
        @org.springframework.beans.factory.annotation.Value("${app.deepseek-key}") String key,
        @org.springframework.beans.factory.annotation.Value("${app.deepseek-url}") String url,
        @org.springframework.beans.factory.annotation.Value("${app.deepseek-model}") String model,
        @org.springframework.beans.factory.annotation.Value("${app.ai-daily-tokens}") int daily,
        @org.springframework.beans.factory.annotation.Value("${app.ai-max-tokens}") int maxTokens,
        @org.springframework.beans.factory.annotation.Value("${app.ai-timeout-seconds}") int timeout) {
        this.db=db;this.memory=memory;tx=new TransactionTemplate(manager);
        this.redis=redis;this.limiter=limiter;this.key=key;this.url=url;this.model=model;
        this.daily=daily;this.maxTokens=maxTokens;this.timeout=timeout;
    }
    boolean configured() { return !key.isBlank(); }
    record Answer(Map<String,Object> json,int tokens) {}
    Answer complete(Actor actor,String purpose,String system,Map<String,Object> input) throws Exception {
        Actor a=memory.fresh(actor); if(!configured()) throw new ApiError(503,"AI_NOT_CONFIGURED","DeepSeek 尚未配置");
        String body=db.write(Map.of("model",model,"stream",false,"max_tokens",maxTokens,"response_format",Map.of("type","json_object"),"messages",List.of(Map.of("role","system","content",system),Map.of("role","user","content",db.write(input)))));
        if(body.length()>16000) throw ApiError.bad("AI_INPUT_TOO_LARGE","检索上下文超出预算");
        int reserve=Math.max(maxTokens,body.getBytes(StandardCharsets.UTF_8).length+maxTokens); String call=Db.id();
        String budgetKey="workpanel:ai-budget:"+a.id()+":"+LocalDate.now(ZoneOffset.UTC);
        tx.executeWithoutResult(t->{
            db.one("SELECT id FROM users WHERE company_id=? AND id=? FOR UPDATE",a.company(),a.id());
            long spent=db.count("SELECT coalesce(sum(tokens),0) FROM memory_model_calls WHERE company_id=? AND owner_id=? AND created_at>=date_trunc('day',now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC'",a.company(),a.id())+db.count("SELECT coalesce(sum(tokens),0) FROM ai_jobs WHERE company_id=? AND owner_id=? AND created_at>=date_trunc('day',now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC'",a.company(),a.id());
            if(spent+reserve>daily) throw new ApiError(429,"AI_BUDGET","每日 AI 预算不足");
            db.update("INSERT INTO memory_model_calls(id,company_id,owner_id,purpose,request_hash,tokens) VALUES (?,?,?,?,?,?)",call,a.company(),a.id(),purpose,Db.hash(body),reserve);
        });
        try {
            Long budget=redis.execute(new org.springframework.data.redis.core.script.DefaultRedisScript<>("local n=tonumber(redis.call('GET',KEYS[1]) or '0'); if n+tonumber(ARGV[1])>tonumber(ARGV[2]) then return -1 end; redis.call('INCRBY',KEYS[1],ARGV[1]); redis.call('EXPIRE',KEYS[1],172800); return n+tonumber(ARGV[1])",Long.class),List.of(budgetKey),String.valueOf(reserve),String.valueOf(daily));
            if(budget==null||budget<0) { db.update("UPDATE memory_model_calls SET tokens=0 WHERE id=?",call); throw new ApiError(429,"AI_BUDGET","每日 AI 预算不足"); }
            limiter.check("memory-model:"+a.id(),5,60);
            var req=HttpRequest.newBuilder(URI.create(url+"/chat/completions")).timeout(Duration.ofSeconds(timeout)).header("Authorization","Bearer "+key).header("Content-Type","application/json").POST(HttpRequest.BodyPublishers.ofString(body,StandardCharsets.UTF_8)).build();
            var response=http.send(req,HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
            if(response.statusCode()!=200) throw new ApiError(503,"AI_PROVIDER_FAILED","模型服务暂不可用");
            Map<String,Object> envelope=db.read(response.body()); var choices=AiApplicationService.maps(envelope,"choices",10);
            if(choices.isEmpty()) throw ApiError.bad("AI_SCHEMA","模型响应格式无效");
            String content=Db.required(db.read(choices.getFirst().get("message")),"content"); if(content.length()>20000) throw ApiError.bad("AI_SCHEMA","模型响应过长");
            int usage=reserve; if(envelope.get("usage") instanceof Map<?,?> u&&u.get("total_tokens") instanceof Number n&&n.intValue()>0) usage=n.intValue();
            db.update("UPDATE memory_model_calls SET state='SUCCEEDED',tokens=? WHERE id=?",usage,call);
            redis.opsForValue().increment(budgetKey,usage-reserve);
            return new Answer(db.read(content),usage);
        } catch(Exception e) { db.update("UPDATE memory_model_calls SET state='FAILED' WHERE id=?",call); throw e; }
    }
}
